# Experimental received-tone calibration

The first physical session (2026-11-04) captured three complete four-second recordings from a built-in MacBook Pro microphone. At 10 kHz and digital peak amplitude 0.020, the fixed simulator score did not detect the instructed seated leaning motion. Peak scores were 0.00001104 stationary, 0.00023001 moving and 0.00031995 transmitter-off/moving. Raw audio remains local and is not committed.

The first three recordings are now **development/calibration data only**. They cannot count toward fresh performance results. One recording per condition is a provisional calibration, not evidence of general reliability.

## Rule fixed before new evaluation

The existing FFT and 6–80 Hz sideband band are retained. For each frame, sum received power within 3 Hz of the carrier and divide the sideband power by that received carrier power. Keep only frame centres from 0.8 seconds to duration minus 0.8 seconds to limit operator/start/stop transients. A trial score is the 80th percentile of those frame ratios.

Calibration requires stationary/on, moving/on and moving/off recordings with identical route metadata and waveform settings. The stationary carrier's 10th percentile must exceed the off carrier's 95th percentile by at least 20 dB. The geometric mean of these carrier powers is the frozen carrier floor. At least 80% of a fresh trial's interior frames must exceed that floor; otherwise the result is **unknown/probe absent**, not a stationary classification. The evaluation rule does not read the trial's expected motion label.

For every calibration recording, compute the trial ratio score. The smallest moving score must exceed 1.5 times the largest stationary score. Overlap refuses calibration. The geometric mean of those two scores is the frozen motion threshold. No threshold or feature tuning is permitted on the held-out evaluation set.

Profiles bind the sample rate, tone frequency, amplitude, duration and reported input route/processing. Changing those requires fresh calibration; system volume and physical geometry must also remain unchanged, although the browser does not verify them. Training PCM fingerprints prevent accidental reuse during evaluation. These are noncryptographic FNV fingerprints, not an authenticity or acceptance mechanism. Profiles and results always retain physicalValidation=false.

This is an independently designed experimental ratio rule. SoundWave motivates hardware characterization and relative spectral measurements; it does not validate this implementation or its thresholds. [Gupta et al., SoundWave, CHI 2012](https://www.microsoft.com/en-us/research/wp-content/uploads/2012/05/guptasoundwavechi2012.pdf). Input settings describe what the browser reports, and the input and AudioContext rates may differ: [Media Capture and Streams](https://w3c.github.io/mediacapture-main/).

## Exact local calibration command

Use the already approved cached Dart SDK. Inputs must be existing local physical tone bundles; output must be a new file. The CLI decodes raw Float32 WAVs and recomputes the FFT. It does not trust exported analysis arrays or play audio, open a microphone, contact a service or install packages.

```sh
umask 077
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart --disable-dart-dev tool/calibrate_tone.dart fit --out /private/tmp/phonopticon-physical-trials-RC5kzs/tone-calibration-v1.json /private/tmp/phonopticon-physical-trials-RC5kzs/stationary.json /private/tmp/phonopticon-physical-trials-RC5kzs/moving.json /private/tmp/phonopticon-physical-trials-RC5kzs/transmitter-off.json
```

Observed provisional profile 645c30b0: threshold 0.0033693911183156873, carrier floor 2.5168013685899415e-9; one calibration recording per condition. This is a fitted pilot result, not held-out detection performance. Use a different output name when repeating the command; existing outputs are refused.

## Fresh trials in the app

1. Select Computer mic + speaker, Tone movement, 10 kHz, four seconds and amplitude 0.020. Keep the same route, system volume, seating position and computer position.
2. Load the local calibration JSON. This reads a local file; there is no upload.
3. Begin 15-trial validation. The app uses a fixed shuffled order (seed 20261104), with five stationary/on, five moving/on and five transmitter-off/moving trials. It locks waveform/condition controls. Each Start remains manual.
4. Follow each displayed condition: sit still; lean toward/away about 10 cm once per second; or repeat that leaning without the probe. Avoid speaking, touching the desk or moving the computer. Actual trajectories and distances remain unmeasured.
5. After each attempt, review the result and press Next. Failed, cancelled and unavailable trials remain in the session. There is no automatic retry or emission.
6. Export the complete validation session before reload/leaving; it includes the frozen profile, planned order, all attempts, raw WAVs, analysis and per-trial provenance. Data stays local. An incomplete export is not a completed evaluation.

Predeclared **local feasibility** target: at least 4/5 moving trials detected and at most one flag among ten controls. All ten transmitter-on trials must provide available decisions. Report off/probe-absent results separately; do not count unknown results as confirmed stationary scenes. Missing/invalid recordings, other unknown decisions, false detections and misses must be reported explicitly. This small, single-session test cannot establish population-level reliability or transfer to another device, frequency, route, volume or room.

The app's single-trial export remains available. Uncalibrated simulation and chirp ranging retain their existing algorithms. No physical ranging, iPhone result or medical inference is claimed by this tone calibration.

Recompute a downloaded session from its raw WAVs with the frozen profile:

```sh
umask 077
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart --disable-dart-dev tool/verify_tone_session.dart /ABSOLUTE/PATH/SESSION.json --out /private/tmp/phonopticon-held-out-NEW.json
```

The verifier checks condition counts/order, profile consistency, training reuse, repeated PCM and zero emitted waveform for off trials. It recomputes decisions, retains failures, distinguishes probe-absent rejections, reports misses/false flags/unknowns and refuses existing output files. Exit 0 means a report was written; inspect localFeasibilityTargetMet rather than treating successful script execution as a successful physical result.
