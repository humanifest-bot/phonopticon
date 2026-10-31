# Current limitations

This MVP demonstrates a simulated experiment workflow and numerical PCM analysis. It now includes an experimental Web Audio computer microphone/speaker adapter. There is still no native iPhone/Android build validation, accepted physical trial result or physically calibrated movement threshold.

## Signal model

The fixture uses colocated-transducer round-trip delay, linear interpolation, a direct component, one target, a fixed background echo and seeded uniform noise. It omits measured transducer response, reverberant rooms, nonlinear distortion, hardware processing, frequency-dependent attenuation and independent audio clocks. A changing delay is an approximation to a moving reflector. Interpolation itself attenuates high-frequency components. Success on the model does not establish physical performance or sensitivity.

The tone analyzer uses a Hann-window FFT of approximately 0.68 seconds at the default rate, with quarter-window hops. Native bin spacing is about 1.465 Hz. It integrates sideband energy 6–80 Hz away from the carrier. Slow motion inside the excluded band can be missed; ordinary sounds in the band can cause detections. Normalization uses a fixed fixture reference, not a tiny live carrier estimate. Single-tone phase/range tracking is not implemented.

The chirp analyzer uses real multiplication and selects the bounded difference-frequency band. Configuration validation rejects sum-frequency alias overlap for this simple mixer; it is not a general-purpose receiver for arbitrary bands. A maximum-range guard removes sweep-boundary contamination. Actual usable bandwidth is smaller than the full sweep, and reported native resolution uses the valid window. Zero padding only samples the spectral display more densely.

Synchronization assumes a strong direct-path positive correlation and an offset shorter than one sweep. Beginning/end lag disagreement greater than one sample rejects dependent ranging. This checks endpoint consistency; it does not prove the absence of all intra-trial jitter, dropped blocks or periodic ambiguities. Long-delay multipath outside the supported 0.15–1.2 m gate can still alias into it. Two clean out-of-gate examples passing are not universal rejection evidence.

A dominant spectrum peak is only an equivalent-range candidate. Multipath and moving-target Doppler can shift or confuse it. Estimates are relative to the aligned direct path under a colocated approximation; transducer separation and physical latency require calibration. No whole-trial mean subtraction or room reconstruction is performed.

## Thresholds and interpretation

The fixed 0.15 movement threshold, two-frame persistence and reference gains are fixture settings. Checks include independent Doppler/delay expectations and held-out noise seeds, but the signal model and evaluation remain authored together. There is no independent scientific acceptance, population evaluation, measured false-alarm rate, medical classification or evidence about third-party acoustic surveillance.

Unknown/invalid results must stay distinct from valid low scores. Transmitter-off chirp captures have no synchronization reference and return unavailable analysis. A low tone movement score means only that this metric did not exceed its threshold; it does not establish that the physical scene was stationary.

## Runtime and evidence

The local Flutter web build and cached flutter_tester execution are separate from browser interaction and native builds. The first in-app browser probe reached the page, but screenshot capture failed and mouse input timed out at Input.dispatchMouseEvent. Keyboard activation did not establish a verified completed trial. Do not describe this as browser QA passing or diagnose a model incompatibility from it. Always-on app semantics and isolated panel semantics now expose the actual controls independently in the native accessibility tree. The tool could read/focus Start but did not establish a completed browser trial. Widget-render PNGs are labelled as widget evidence.

Web export uses dart:html and targets the JavaScript build, not Flutter WebAssembly. A future WebAssembly port needs JS interop replacement. The current web app is local-only, uses bundled engine/font assets and blocks external connections through its page policy. Do not host a development server on a public interface by default.

The computer adapter uses a local AudioWorklet and explicit permission. Input processing constraints may be ignored; reported settings and latencies do not prove acoustic calibration. Missing input/processor failures stop the trial; failed setup can yield no recording. Partial Stop exports may contain fewer samples and are marked cancelled. Real device performance remains unverified until an actual foreground recording is inspected.

The simulated backend waits through the bounded trial then generates PCM and analyzes it; the final DSP is synchronous and results are not live streaming. The backend contract is full-trial PCM for this MVP. A native implementation may add block streaming/versioned timing without changing waveform/artifact meaning. Stop/dispose are explicit and no physical device is opened.

Exported Float32 WAVs round internal Float64 samples. Invalid fixtures deliberately retain nonfinite raw samples with invalid analysis labels. Fingerprints are noncryptographic, and an untagged build records missing source revision explicitly. Export metadata/plots are worker-produced evidence, not trusted acceptance receipts.

## Source reproduction and rights

The upstream sample is structurally readable, but its legacy Python analysis has not been executed or reproduced in this Flutter milestone. No new supplied-recording result is claimed. Its sample/image rights remain unresolved; no source assets are bundled. Original Android/clinical results are not reproduced by the simulation.

The next measurable milestone is a real iPhone producing a foreground local PCM export, followed by separate tone/chirp stationary, moving and transmitter-off trials under a frozen protocol. SDK installation, signing and hardware emission need their applicable authorization.
