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
    for (let j = 0; j < count; j++) {
      output[j] = this.tx[this.position + j];
      this.rx[this.position + j] = input ? input[j] : 0;
    }
    if (!input) this.missing += count;
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
