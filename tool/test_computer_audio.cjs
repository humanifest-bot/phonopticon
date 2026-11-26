// Node VM mocks only. This test never accesses real devices or browser permissions.
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
let Processor;
const worklet = {Float32Array, AudioWorkletProcessor:class { constructor(){ this.messages=[]; this.port={postMessage:m=>this.messages.push(m)};} }, registerProcessor:(_,p)=>Processor=p};
vm.runInNewContext(readFileSync('web/audio_capture_worklet.js','utf8'),worklet);
const tx=Float32Array.from({length:260},(_,i)=>i/10000);
const p=new Processor({processorOptions:{tx}});
for(let i=0;i<3;i++) {
 const output=new Float32Array(128);
 const running=p.process([[new Float32Array(128).fill(.2)]],[[output]]);
 assert.equal(running,i<2);
 for(let j=0;j<Math.min(128,260-i*128);j++) assert.equal(output[j],tx[i*128+j]);
 if(i===2) assert.ok(output.slice(4).every(x=>x===0));
}
assert.equal(p.messages[0].samples.length,260);
assert.equal(p.messages[0].missing,0);
const partial=new Processor({processorOptions:{tx}});
partial.process([[new Float32Array(128).fill(.3)]],[[new Float32Array(128)]]);
partial.port.onmessage({data:{stop:true}});
assert.equal(partial.messages[0].samples.length,128);
assert.equal(partial.messages[0].cancelled,true);
const zero=new Float32Array(128).fill(1);
assert.equal(partial.process([],[[zero]]),false);
assert.ok(zero.every(x=>x===0));
const off=new Processor({processorOptions:{tx:new Float32Array(128)}});
const silent=new Float32Array(128).fill(1);
off.process([[new Float32Array(128)]],[[silent]]);
assert.ok(silent.every(x=>x===0));
const missingInput=new Processor({processorOptions:{tx}});
const missingOutput=new Float32Array(128).fill(1);
assert.equal(missingInput.process([],[[missingOutput]]),false);
assert.ok(missingOutput.every(x=>x===0));
assert.equal(missingInput.messages[0].samples.length,0);
assert.equal(missingInput.messages[0].missing,128);
const shortInput=new Processor({processorOptions:{tx}});
const shortOutput=new Float32Array(128).fill(1);
assert.equal(shortInput.process([[new Float32Array(5)]],[[shortOutput]]),false);
assert.ok(shortOutput.every(x=>x===0));
assert.equal(shortInput.messages[0].missing,128);
const interrupted=new Processor({processorOptions:{tx}});
assert.equal(interrupted.process([[new Float32Array(128).fill(.3)]],[[new Float32Array(128)]]),true);
const interruptedOutput=new Float32Array(128).fill(1);
assert.equal(interrupted.process([],[[interruptedOutput]]),false);
assert.ok(interruptedOutput.every(x=>x===0));
assert.equal(interrupted.messages[0].samples.length,128);
assert.equal(interrupted.messages[0].samples[0],Math.fround(.3));
for (const invalidSample of [NaN, Infinity, -Infinity]) {
 const badInput=new Processor({processorOptions:{tx}});
 assert.equal(badInput.process([[new Float32Array(128).fill(.25)]],[[new Float32Array(128)]]),true);
 const invalidBlock=new Float32Array(128).fill(.25); invalidBlock[9]=invalidSample;
 const invalidOutput=new Float32Array(128).fill(1);
 assert.equal(badInput.process([[invalidBlock]],[[invalidOutput]]),false);
 assert.ok(invalidOutput.every(x=>x===0));
 assert.equal(badInput.messages[0].invalid,true);
 assert.equal(badInput.messages[0].samples.length,128);
 assert.ok(badInput.messages[0].samples.every(Number.isFinite));
}
console.log('PASS: worklet exact sample cap, PCM capture, zero tail, partial stop and transmitter-off output');

function bridge(getUserMedia, mode='complete') {
 let stopped=0,closed=0,emissions=0;
 const track={getSettings:()=>({sampleRate:48000,echoCancellation:false}),label:'mock microphone',stop:()=>stopped++};
 const stream={getTracks:()=>[track],getAudioTracks:()=>[track]};
 class Context {
  constructor(o){this.sampleRate=o.sampleRate;this.state='running';this.currentTime=0;this.destination={};this.audioWorklet={addModule:async()=>{}};}
  resume(){return Promise.resolve();}
  close(){closed++;return Promise.resolve();}
  createMediaStreamSource(){return {connect(){},disconnect(){}};}
 }
 class Node {
  constructor(ctx,name,o){this.tx=o.processorOptions.tx;this.port={postMessage:m=>{if(m.stop && mode==='waiting') queueMicrotask(()=>this.port.onmessage({data:{samples:new Float32Array(128),missing:0,cancelled:true}}));}};}
  connect(){emissions++;if(mode!=='waiting' && mode!=='noack') queueMicrotask(()=>{
    // Completion can already be queued when the user requests Stop.
    if(mode==='race' || mode==='missing-race') env.window.phonopticonAudio.stop();
    const failed=mode==='missing' || mode==='missing-empty' || mode==='missing-race';
    const length=mode==='missing-empty'?0:failed || mode==='short' || mode==='invalid'?128:mode==='overlong'?this.tx.length+1:this.tx.length;
    const samples=mode==='malformed'?null:mode==='nonfinite'?Float32Array.from([.25,NaN,.5]):new Float32Array(length);
    this.port.onmessage({data:{samples,missing:failed?128:0,invalid:mode==='invalid',cancelled:failed || mode==='invalid'}});
  });}
  disconnect(){}
 }
 const env={window:{isSecureContext:true,AudioContext:Context,AudioWorkletNode:Node},AudioContext:Context,AudioWorkletNode:Node,
  navigator:{mediaDevices:{getUserMedia:()=>getUserMedia(stream)},userAgent:'mock'},
  document:{hidden:false,addEventListener(){},removeEventListener(){}},Float32Array,JSON,Date,Number,Error,Promise,performance,
  setTimeout,clearTimeout,setInterval,clearInterval};
 vm.runInNewContext(readFileSync('web/computer_audio.js','utf8'),env);
 return {api:env.window.phonopticonAudio,stats:()=>({stopped,closed,emissions})};
}
(async()=>{
 const c=JSON.stringify({sampleRate:48000,durationSeconds:1,amplitude:.02});
 const pcm=new Float32Array(48000);
 const success=bridge(async s=>s);
 const result=JSON.parse(await success.api.start(c,pcm));
 assert.equal(result.cancelled,false);assert.equal(result.samples.length,48000);
 assert.equal(result.metadata.inputSettings.echoCancellation,false);
 assert.deepEqual(success.stats(),{stopped:1,closed:1,emissions:1});
 const denied=bridge(async()=>{throw Error('permission denied');});
 await assert.rejects(denied.api.start(c,pcm),/permission denied/);
 assert.deepEqual(denied.stats(),{stopped:0,closed:1,emissions:0});
 let grant;
 const pending=bridge(s=>new Promise(resolve=>{grant=()=>resolve(s);}));
 const completion=pending.api.start(c,pcm);
 pending.api.stop();
 assert.equal(JSON.parse(await completion).cancelled,true);
 grant(); await new Promise(resolve=>setImmediate(resolve));
 assert.deepEqual(pending.stats(),{stopped:1,closed:1,emissions:0});
 const during=bridge(async s=>s,'waiting');
 const recording=during.api.start(c,pcm);
 await new Promise(resolve=>setImmediate(resolve));
 during.api.stop();
 const partialResult=JSON.parse(await recording);
 assert.equal(partialResult.cancelled,true);assert.equal(partialResult.samples.length,128);
 assert.equal(partialResult.metadata.emittedPrefixSamples,128);
 assert.match(partialResult.metadata.emittedTail,/Unknown/);
 assert.deepEqual(during.stats(),{stopped:1,closed:1,emissions:1});
 const noack=bridge(async s=>s,'noack');
 const pendingAck=noack.api.start(c,pcm);
 await new Promise(resolve=>setImmediate(resolve));
 noack.api.stop();
 const unacknowledged=JSON.parse(await pendingAck);
 assert.equal(unacknowledged.cancelled,true);
 assert.equal(unacknowledged.samples.length,0);
 assert.equal(unacknowledged.metadata.emittedPrefixSamples,0);
 assert.match(unacknowledged.metadata.emittedTail,/Unknown/);
 assert.deepEqual(noack.stats(),{stopped:1,closed:1,emissions:1});
 const race=bridge(async s=>s,'race');
 const racedResult=JSON.parse(await race.api.start(c,pcm));
 assert.equal(racedResult.cancelled,true);
 assert.equal(racedResult.metadata.emittedPrefixSamples,48000);
 assert.deepEqual(race.stats(),{stopped:1,closed:1,emissions:1});
 const missing=bridge(async s=>s,'missing');
 const missingResult=JSON.parse(await missing.api.start(c,pcm));
 assert.equal(missingResult.cancelled,false);
 assert.match(missingResult.failure,/Missing microphone input/);
 assert.equal(missingResult.samples.length,128);
 assert.equal(missingResult.metadata.emittedPrefixSamples,128);
 assert.match(missingResult.metadata.emittedTail,/Unknown/);
 assert.deepEqual(missing.stats(),{stopped:1,closed:1,emissions:1});
 const missingEmpty=bridge(async s=>s,'missing-empty');
 const emptyResult=JSON.parse(await missingEmpty.api.start(c,pcm));
 assert.equal(emptyResult.cancelled,false);
 assert.equal(emptyResult.samples.length,0);
 assert.equal(emptyResult.metadata.emittedPrefixSamples,0);
 assert.match(emptyResult.metadata.emittedTail,/Unknown/);
 const missingRace=bridge(async s=>s,'missing-race');
 const missingRacedResult=JSON.parse(await missingRace.api.start(c,pcm));
 assert.equal(missingRacedResult.cancelled,true);
 assert.match(missingRacedResult.failure,/Missing microphone input/);
 assert.equal(missingRacedResult.samples.length,128);
 for (const [mode, expected, prefix] of [
   ['short', /Incomplete microphone capture/, 128],
   ['malformed', /Invalid microphone capture payload/, 0],
   ['nonfinite', /Nonfinite microphone sample/, 1],
   ['invalid', /Nonfinite microphone input block/, 128],
   ['overlong', /exceeded the configured length/, 48000],
 ]) {
  const fixture=bridge(async s=>s,mode);
  const failedResult=JSON.parse(await fixture.api.start(c,pcm));
  assert.equal(failedResult.cancelled,false);
  assert.match(failedResult.failure,expected);
  assert.equal(failedResult.samples.length,prefix);
  assert.ok(failedResult.samples.every(Number.isFinite));
  assert.equal(failedResult.metadata.emittedPrefixSamples,prefix);
  assert.match(failedResult.metadata.emittedTail,/Unknown/);
  assert.deepEqual(fixture.stats(),{stopped:1,closed:1,emissions:1});
 }
 const invalid=bridge(async s=>s);
 await assert.rejects(invalid.api.start(JSON.stringify({sampleRate:48000,durationSeconds:11,amplitude:.02}),pcm),/Invalid physical waveform/);
 assert.equal(invalid.stats().emissions,0);
 const loud=new Float32Array(48000); loud[42]=.03;
 await assert.rejects(invalid.api.start(c,loud),/Invalid physical waveform/);
 const leaking=new Float32Array(48000); leaking[42]=.001;
 await assert.rejects(invalid.api.start(JSON.stringify({scenario:'transmitterOff',sampleRate:48000,durationSeconds:1,amplitude:.02}),leaking),/Invalid physical waveform/);
 await assert.rejects(invalid.api.start(JSON.stringify({scenario:'silence',sampleRate:48000,durationSeconds:1,amplitude:.02}),leaking),/Invalid physical waveform/);
 assert.deepEqual(invalid.stats(),{stopped:0,closed:0,emissions:0});
 const breathing=bridge(async s=>s);
 const longTrial=JSON.stringify({mode:'breathing',sampleRate:48000,durationSeconds:30,amplitude:.02});
 const longResult=JSON.parse(await breathing.api.start(longTrial,new Float32Array(1440000)));
 assert.equal(longResult.samples.length,1440000);
 assert.deepEqual(breathing.stats(),{stopped:1,closed:1,emissions:1});
 await assert.rejects(invalid.api.start(JSON.stringify({mode:'breathing',sampleRate:48000,durationSeconds:31,amplitude:.02}),new Float32Array(1488000)),/Invalid physical waveform/);
 console.log('PASS: bridge completion/cleanup, permission denial, late permission cancellation, no emission before grant, active Stop/partial capture, missing-input failure, duration guard');
})().catch(e=>{console.error(e);process.exitCode=1;});
