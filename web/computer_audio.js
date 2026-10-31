// Local-only audio bridge. No capture/emission until an explicit start call.
(() => {
  let active = null;
  const supported = () => !!(window.isSecureContext && navigator.mediaDevices?.getUserMedia && window.AudioContext && window.AudioWorkletNode);
  const stop = () => { if (active) active.cancel(); };
  async function start(configJson, tx) {
    const c = JSON.parse(configJson);
    if (!supported()) throw Error('Computer audio unavailable: secure context, microphone API and AudioWorklet required.');
    if (active) throw Error('A physical trial is already active.');
    if (!(c.durationSeconds >= 1 && c.durationSeconds <= 10 && c.amplitude > 0 && c.amplitude <= .05) ||
        tx.length !== Math.round(c.sampleRate * c.durationSeconds) ||
        !tx.every(x => Number.isFinite(x) && Math.abs(x) <= .050001)) throw Error('Invalid physical waveform/limit.');
    const context = new AudioContext({sampleRate:c.sampleRate, latencyHint:'interactive'});
    let stream, node, source, timer, progress, permissionTimer, resolve, reject, samples = null;
    let settled = false, recording = false, sampleStart = null;
    const startedUtc = new Date().toISOString(), startedMono = performance.now();
    const result = new Promise((yes,no) => { resolve=yes; reject=no; });
    const state = {elapsed:0, cancel() {
      if (settled) return;
      if (node) {
        node.port.postMessage({stop:true});
        clearTimeout(timer);
        timer = setTimeout(() => state.finish(true),200);
      } else state.finish(true);
    }, finish(cancelled, error=null) {
      if (settled) return;
      settled = true;
      clearTimeout(timer); clearTimeout(permissionTimer); clearInterval(progress);
      document.removeEventListener('visibilitychange', hidden);
      if (node) { node.port.postMessage({stop:true}); node.disconnect(); }
      if (source) source.disconnect();
      const metadata = {audioContextRate:context.sampleRate, inputSettings:stream?.getAudioTracks()[0]?.getSettings() || {},
        inputLabel:stream?.getAudioTracks()[0]?.label || 'not granted',
        outputRoute:'browser-selected output; use built-in speakers, not Bluetooth/headphones',
        baseLatency:context.baseLatency ?? null, outputLatency:context.outputLatency ?? null,
        audioContextStartSeconds:sampleStart, browser:navigator.userAgent,
        requestedProcessing:{echoCancellation:false,noiseSuppression:false,autoGainControl:false},
        note:'Input may be resampled to the audio context clock. Settings are not proof of raw hardware response.'};
      if (stream) stream.getTracks().forEach(t => t.stop());
      const close = context.close().catch(() => {});
      if (active === state) active = null;
      if (error) { close.then(() => reject(error)); return; }
      close.then(() => resolve(JSON.stringify({samples:samples ? Array.from(samples) : [], cancelled,
        startedUtc, elapsedMicroseconds:Math.round((performance.now()-startedMono)*1000),
        actualSampleRate:context.sampleRate, metadata})));
    }};
    function hidden() { if (document.hidden) state.cancel(); }
    active = state;
    document.addEventListener('visibilitychange', hidden);
    permissionTimer = setTimeout(() => state.finish(true, Error('Microphone/setup timed out. No automatic retry.')), 15000);
    // Resume is requested in the Start gesture, before awaiting microphone permission.
    const resumed = context.resume();
    resumed.catch(() => {});
    (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({audio:{channelCount:1,sampleRate:c.sampleRate,
          echoCancellation:false,noiseSuppression:false,autoGainControl:false},video:false});
        if (settled) { stream.getTracks().forEach(t=>t.stop()); return; }
        await resumed;
        if (settled) return;
        if (context.state !== 'running' || context.sampleRate !== c.sampleRate) throw Error('Requested PCM clock unavailable; no emission started.');
        await context.audioWorklet.addModule('audio_capture_worklet.js');
        if (settled) return;
        source = context.createMediaStreamSource(stream);
        node = new AudioWorkletNode(context,'sonar-capture',{numberOfInputs:1,numberOfOutputs:1,
          outputChannelCount:[1], channelCount:1,channelCountMode:'explicit', processorOptions:{tx}});
        node.onprocessorerror = () => state.finish(true,Error('AudioWorklet failed; trial stopped.'));
        node.port.onmessage = e => {
          if (settled) return;
          samples = e.data.samples;
          if (e.data.missing) { state.finish(true,Error('Missing microphone input blocks; no physical analysis accepted.')); return; }
          state.finish(!!e.data.cancelled);
        };
        for (const track of stream.getTracks()) track.onended = () => {
          if (!settled) state.finish(true,Error('Microphone disconnected.'));
        };
        clearTimeout(permissionTimer);
        recording = true; sampleStart = context.currentTime;
        source.connect(node); node.connect(context.destination);
        progress = setInterval(() => { state.elapsed = Math.min(c.durationSeconds,context.currentTime-sampleStart); },50);
        timer = setTimeout(() => state.finish(true,Error('Audio completion watchdog expired; capture invalid.')), (c.durationSeconds+2)*1000);
      } catch (error) { state.finish(true,error); }
    })();
    context.onstatechange = () => {
      if (recording && !settled && context.state !== 'running') state.finish(true,Error('Audio context interrupted; capture invalid.'));
    };
    return result;
  }
  window.phonopticonAudio = {get available(){return supported();}, start, stop, get elapsed(){return active?.elapsed || 0;}};
})();
