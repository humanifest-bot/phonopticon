// Same audio rendering clock for emitted PCM and microphone blocks.
class SonarCapture extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.tx = options.processorOptions.tx;
    this.rx = new Float32Array(this.tx.length);
    this.position = 0;
    this.missing = 0;
    this.stopped = false;
    this.port.onmessage = e => {
      if (e.data.stop && !this.stopped) {
        this.stopped = true;
        this.port.postMessage({samples:this.rx.subarray(0,this.position),missing:this.missing,cancelled:true},[this.rx.buffer]);
      }
    };
  }
  process(inputs, outputs) {
    const output = outputs[0][0], input = inputs[0]?.[0];
    output.fill(0);
    if (this.stopped) return false;
    const count = Math.min(output.length, this.tx.length - this.position);
    // Do not emit into a trial whose microphone stream has already failed.
    // Report only the known synchronized prefix and stop immediately.
    if (!input || input.length < count) {
      this.missing += count;
      this.stopped = true;
      this.port.postMessage({samples:this.rx.subarray(0,this.position),missing:this.missing,cancelled:true},[this.rx.buffer]);
      return false;
    }
    // Reject the entire invalid block before emitting any of its samples.
    // Preserve the finite synchronized prefix from preceding blocks.
    for (let j = 0; j < count; j++) {
      if (!Number.isFinite(input[j])) {
        this.stopped = true;
        this.port.postMessage({samples:this.rx.subarray(0,this.position),invalid:true,cancelled:true},[this.rx.buffer]);
        return false;
      }
    }
    for (let j = 0; j < count; j++) {
      output[j] = this.tx[this.position + j];
      this.rx[this.position + j] = input[j];
    }
    this.position += count;
    if (this.position === this.tx.length) {
      this.stopped = true;
      this.port.postMessage({samples: this.rx, missing: this.missing}, [this.rx.buffer]);
      return false; // Output stays zero after the exact configured sample count.
    }
    return true;
  }
}
registerProcessor('sonar-capture', SonarCapture);
