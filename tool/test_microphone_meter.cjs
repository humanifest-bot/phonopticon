// Local VM fixtures only. No microphone, network, files, or audio hardware.
const {readFileSync} = require('node:fs');
const assert = require('node:assert/strict');
const vm = require('node:vm');

let Meter;
const worklet = {
  sampleRate: 48000,
  AudioWorkletProcessor: class {
    constructor() {
      this.messages = [];
      this.port = {postMessage: message => this.messages.push(message)};
    }
  },
  registerProcessor: (_, processor) => { Meter = processor; },
};
vm.runInNewContext(readFileSync('web/microphone_meter_worklet.js', 'utf8'), worklet);
const processor = new Meter();
const out = new Float32Array(4800).fill(1);
assert.equal(processor.process([[new Float32Array(4800).fill(0.25)]], [[out]]), true);
assert.ok(out.every(sample => sample === 0));
assert.equal(processor.messages[0].level, 0.25);
assert.equal(processor.messages[0].samples, undefined);
assert.equal(processor.process([], [[new Float32Array(128)]]), false);
assert.equal(processor.messages[1].error, 'Missing microphone input blocks');

function mockBridge(getMedia) {
  let stopped = 0, closed = 0, connected = 0, handler;
  const track = {stop() { stopped++; }, getSettings() { return {}; }};
  const stream = {getTracks() { return [track]; }, getAudioTracks() { return [track]; }};
  class Context {
    constructor() {
      this.state = 'running';
      this.destination = {};
      this.audioWorklet = {addModule: async () => {}};
    }
    resume() { return Promise.resolve(); }
    close() { closed++; return Promise.resolve(); }
    createMediaStreamSource() { return {connect() {}, disconnect() {}}; }
  }
  class Node {
    constructor() { this.port = {}; }
    connect() { connected++; this.port.onmessage({data:{level:0.3}}); }
    disconnect() {}
  }
  const document = {
    hidden:false,
    addEventListener(name, callback) { if (name === 'visibilitychange') handler = callback; },
    removeEventListener() {},
  };
  const env = {
    window:{isSecureContext:true, AudioContext:Context, AudioWorkletNode:Node},
    AudioContext:Context, AudioWorkletNode:Node,
    navigator:{mediaDevices:{getUserMedia:() => getMedia(stream)}},
    document, Float32Array, JSON, Date, Number, Math, Error, Promise,
    performance, setTimeout, clearTimeout, setInterval, clearInterval,
  };
  vm.runInNewContext(readFileSync('web/computer_audio.js','utf8'), env);
  return {
    api:env.window.phonopticonAudio,
    stats:() => ({stopped,closed,connected}),
    hide:() => { document.hidden = true; handler(); },
  };
}

(async () => {
  const meter = mockBridge(async stream => stream);
  const done = meter.api.startMeter();
  assert.equal(meter.api.meterReady, false);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(meter.api.meterLevel, 0.3);
  assert.equal(meter.api.meterReady, true);
  await assert.rejects(meter.api.startMeter(), /already active/);
  meter.api.stopMeter();
  await done;
  assert.deepEqual(meter.stats(), {stopped:1,closed:1,connected:1});
  assert.equal(meter.api.meterLevel, 0);
  assert.equal(meter.api.meterReady, false);

  const background = mockBridge(async stream => stream);
  const backgroundDone = background.api.startMeter();
  await new Promise(resolve => setImmediate(resolve));
  background.hide();
  await backgroundDone;
  assert.deepEqual(background.stats(), {stopped:1,closed:1,connected:1});

  let grant;
  const pending = mockBridge(stream => new Promise(resolve => { grant = () => resolve(stream); }));
  const pendingDone = pending.api.startMeter();
  pending.api.stopMeter();
  await pendingDone;
  grant();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(pending.stats(), {stopped:1,closed:1,connected:0});

  const denied = mockBridge(async () => { throw Error('permission denied'); });
  await assert.rejects(denied.api.startMeter(), /permission denied/);
  assert.deepEqual(denied.stats(), {stopped:0,closed:1,connected:0});
  console.log('PASS: meter reports RMS only, outputs silence, enforces exclusivity and stops on request, background or denied/late permission');
})().catch(error => { console.error(error); process.exitCode = 1; });
