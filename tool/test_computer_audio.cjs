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
  connect(){emissions++;if(mode!=='waiting') queueMicrotask(()=>this.port.onmessage({data:{samples:new Float32Array(this.tx.length),missing:mode==='missing'?128:0}}));}
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
 assert.deepEqual(during.stats(),{stopped:1,closed:1,emissions:1});
 const missing=bridge(async s=>s,'missing');
 await assert.rejects(missing.api.start(c,pcm),/Missing microphone input/);
 assert.deepEqual(missing.stats(),{stopped:1,closed:1,emissions:1});
 const invalid=bridge(async s=>s);
 await assert.rejects(invalid.api.start(JSON.stringify({sampleRate:48000,durationSeconds:11,amplitude:.02}),pcm),/Invalid physical waveform/);
 assert.equal(invalid.stats().emissions,0);
 console.log('PASS: bridge completion/cleanup, permission denial, late permission cancellation, no emission before grant, active Stop/partial capture, missing-input failure, duration guard');
})().catch(e=>{console.error(e);process.exitCode=1;});
