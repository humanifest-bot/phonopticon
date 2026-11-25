// Reports levels only. Never retains microphone samples or monitors them.
class MicrophoneMeter extends AudioWorkletProcessor {
  constructor() {
    super();
    this.sumSquares = 0;
    this.count = 0;
  }

  process(inputs, outputs) {
    const output = outputs[0]?.[0];
    if (output) output.fill(0);
    const input = inputs[0]?.[0];
    if (!input) {
      this.port.postMessage({error: 'Missing microphone input blocks'});
      return false;
    }
    for (const sample of input) {
      this.sumSquares += sample * sample;
      this.count++;
    }
    if (this.count >= sampleRate / 10) {
      this.port.postMessage({level: Math.sqrt(this.sumSquares / this.count)});
      this.sumSquares = 0;
      this.count = 0;
    }
    return true;
  }
}
registerProcessor('microphone-meter', MicrophoneMeter);
