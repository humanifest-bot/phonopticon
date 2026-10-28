# Flutter acoustic sonar MVP build plan

Build a local Flutter experiment runner with **tone movement** and **chirp ranging** modes. Begin with deterministic simulated audio and a replaceable capture backend. The first deliverable is a working simulated experiment, not a desktop GUI, native microphone implementation, or physical validation.

The original brief and subsequent decisions are preserved in [docs/ORIGINAL_REQUEST.md](docs/ORIGINAL_REQUEST.md). This plan incorporates the user's approval of Flutter and both measurement modes. Implementation, verification, human acceptance, and activation remain distinct.

## Scope and completion

The initial goal is complete when a runnable Flutter app supports explicit Start/Stop and a ten-second limit, processes deterministic simulated PCM through the same analysis interface intended for physical recordings, displays inspectable results, exports reproducible local artifacts, and passes recorded offline verification. Both modes, invalid input, cancellation, and transmitter-off controls must work. Setup and exact commands, example outputs, provenance, limitations, and a concrete native iPhone milestone are required.

Physical capture is a later milestone: do not claim physical feasibility from fixtures. No medical classification, surveillance deployment, room reconstruction, phone synchronization, cloud services, machine learning, automatic/background emission, deployment, paid services, or deletion of existing material.

The user subsequently authorized regular commits and pushes to https://github.com/humanifest-bot/phonopticon. Publish only coherent task milestones there, using the existing configured identity and SSH authentication; no deployment or messages are authorized.

## Evidence and starting state

Local inspection on 2026-10-28 reported effective user legion on Darwin. The checkout is /Users/legion/dev/humanifest/phonopticon, branch main, initially clean with README.md only. Flutter and Dart executable links exist under /opt/homebrew/bin; installation presence does not establish runtime health. The shell reports umask 022; task commands that create files must explicitly use 077 without changing global settings.

Prior research inspected upstream commit 3677815c2e955a554aaa6e2e1e23c8bd4b5f04fd. Its four Python scripts use NumPy, SciPy, Matplotlib and PyAudio. The root listing has no dependency manifest, tests, standalone license text or AGENTS.md. The supplied WAV was read as mono Float32, 44,100 Hz, 441,000 finite samples, ten seconds. SHA-256: c9ad5c1b5ef5cb2b6343c8340806a3e8c2775a79889cb8dee59aa2da712195f8. Structural readability is not a successful reproduction or ground truth.

Upstream code contains sample repetition in place of whole-chirp repetition, a correlation index/lag confusion, fixed frame/bin assumptions, and no calibrated distance output. Preserve legacy behavior as a separately labelled reproduction; do not silently call corrected output a reproduction.

The selected Apple developer directory was /Library/Developer/CommandLineTools. `xcrun --sdk iphoneos --show-sdk-path` failed because the iPhoneOS SDK could not be located. Do not install Xcode, change developer selection or configure signing automatically.

No Metamaps projection, Orca lifecycle interface or protected acceptance integration is present in this checkout. The traceability and receipts below are local records, not a substitute integration or authority to approve work.

## Waveform decisions

A sustained tone is the simplest movement probe. Doppler sidebands and, later, coherent phase changes can reveal movement. A single tone cannot establish unambiguous absolute distance. The tone screen must never display a distance estimate inferred from a single carrier.

Repeated FMCW chirps support delay/range estimation and a range-versus-time plot. A chirp can be repeated continuously during a bounded trial; it need not be an isolated ping. Higher carrier frequency increases Doppler/phase sensitivity, while wider usable sweep bandwidth improves range separation. These are separate parameters.

For approximately colocated transducers, use fD = 2*v*f0/c and r_equivalent = c*tau/2. For FMCW, S = B/T and tau = fb/S. At c = 343 m/s, nominal full-band range resolution is c/(2*B): approximately 8.58 cm for B = 2 kHz and 2.45 cm for B = 7 kHz. Windowing, sweep-boundary exclusion and effective bandwidth worsen practical resolution. FFT zero padding does not create resolution.

For separated speaker and microphone, half of the total acoustic path is an equivalent range; it is not automatically distance from either transducer. Latency offsets and clock drift require calibration. Phase-based movement is ambiguous, sensitive to multipath and not an initial requirement.

### Initial configurable presets

| Parameter | Tone movement | Chirp ranging |
| --- | --- | --- |
| Simulated sample rate | 48,000 Hz | 48,000 Hz |
| Signal | 10 kHz carrier | Linear 3–10 kHz sweep |
| Sweep length | Not applicable | 20 ms, integer sample count |
| Maximum trial duration | 10 seconds | 10 seconds |
| Digital peak amplitude | 0.02 | 0.02 |
| Initial gate | Declared Doppler sideband band | Declared equivalent-range interval |

These are fixture presets, not validated hardware defaults. Include a separate 18–20 kHz candidate and short frequency-probe trials in the later physical procedure. Do not assume near-ultrasound is inaudible or works on a particular phone. Equal digital amplitude is not equal acoustic output. Never automatically increase amplitude, volume, duration or switch devices to obtain a pass.

Generate integer sample counts, record actual durations, repeat complete chirps, and document phase reset and session ramps. Synthetic signal generation and analysis must not share the same delay-to-range shortcut: analysis must recover results from received PCM.

## Architecture

Use Flutter/Dart for the shared interface, trial state machine, typed configuration, deterministic fixtures, analysis and result display. Keep the Python implementation as a reference/reproduction path; do not embed Python in the mobile app or require it for the simulated runner.

Suggested modules:

- `lib/domain/`: immutable experiment configuration, audio blocks, timestamps, quality flags, results and artifact schema.
- `lib/audio/`: `AudioBackend` contract, simulated implementation, explicit unsupported/native stub.
- `lib/signal/`: waveform generation, seeded noise, delay/echo synthesis, windows, spectral analysis and metrics.
- `lib/runner/`: idle, preparing, running, stopping, complete, cancelled and failed lifecycle.
- `lib/ui/`: mode/scenario selection, parameters, Start/Stop/countdown, plots, quality indicators and export.
- `test/`: independent numerical expectations, lifecycle tests and widget tests.
- `configs/`, `docs/`, `examples/`: reusable fixtures, setup, physical protocol, limitations and receipts.

Keep the interface small: capabilities, start(config), timestamped captured blocks/status, stop(), dispose(). Report supported formats, actual input/output format, processing state and route where available. No generic filesystem, shell, network or deployment capability belongs in this backend.

The native backend owns real-time output/capture timing. Flutter sends trial-level commands and receives bounded data/results; do not schedule individual samples with UI timers or ordinary platform messages. Simulator and physical backends use the same PCM/configuration/result contracts. Backend selection is explicit and visible. No silent fallback from unavailable physical audio to simulation.

Prefer Flutter SDK components and a small auditable Dart signal module initially. Inspect existing SDK/runtime behavior before choosing numerical or export packages. Pin any introduced dependencies and document their licenses; installation/network resolution requires separate authorization.

## Analysis and presentation

### Tone movement

Synthesize a carrier plus delayed static and moving reflections, noise and direct leakage. For the first model, radial velocity produces a changing acoustic delay; document interpolation and geometry approximations. Include stationary, moving, transmitter-off and invalid-input fixtures.

Show a time-frequency spectrum around the carrier, a carrier-excluded sideband-energy movement metric, its units/normalization, frozen threshold and quality flags. Compare signal energy to the fixed calibration noise floor; do not divide by an arbitrarily tiny live carrier value. Stationary/off controls must not be normalized into strong movement. Include positive/negative sidebands; direction estimates are optional and require validated sign conventions. Save window length, hop, spectral resolution, excluded carrier band and detection band. Explain the latency/sensitivity tradeoff.

### Chirp ranging

Validate PCM, align using actual correlation lags, segment sweeps, inspect drift, dechirp, low-pass the difference component, exclude sweep-reset contamination, window and transform. Derive axes from actual rates, sweep slopes and valid samples. Restrict estimates to an explicitly supported delay interval.

Keep ordinary range power and movement-sensitive differences separately. Do not subtract a whole moving trial's mean and treat the result as an unbiased static range profile. Show range-versus-time, a movement score and confidence/ambiguity. Return no reliable estimate when evidence is insufficient. Clutter subtraction uses an identified calibration recording and version.

Use frame-to-frame power change in a fixed range gate, normalized to a fixed calibrated reference with a documented floor, as an initial movement metric. Threshold and temporal persistence are selected on calibration fixtures and frozen before evaluation.

All screens and exports display source kind: SIMULATED, SUPPLIED RECORDING or PHYSICAL. Synthetic truth is available as an overlay for comparison, not as an input to the estimator. No medical or authorship/surveillance conclusions.

## Milestones and checks

| ID | Deliverable | Acceptance and evidence |
| --- | --- | --- |
| M0 | Plan and provenance | Original brief, decisions, sources, constraints and unresolved licensing retained |
| M1 | Flutter simulated runner | Both modes; Start/Stop; countdown; ten-second cap; no device audio on app launch; restart without stale output |
| M2 | PCM fixtures and numerical analysis | Deterministic seed; independently calculated delays/Doppler; finite results; invalid/weak input handled |
| M3 | Inspectable UI and artifacts | Tone spectrogram/metric; chirp range-time/metric; configuration and quality visible; local reproducible export |
| M4 | Offline verification and handoff | Tests/analyzer and available runner checks recorded; example artifacts, setup and limitations; no unrun platform claimed verified |
| M5 | Supplied recording reproduction | Optional separately tracked legacy/reference outputs or precise failure; no invented distance truth |
| M6 | Native iPhone capture/export | Deferred physical milestone; native foreground backend produces schema-compatible recordings |
| M7 | Controlled physical feasibility | Calibrated held-out stationary/moving/on/off results, errors and failures |

For M2 test at least stationary reflection, two directions of motion, zero/noise-only input, transmitter off, direct leakage, multiple static echoes, fractional delay, startup offset and an out-of-gate echo. Check known chirp delays at several ranges: e.g. 140 samples at 48 kHz corresponds to about 0.5002 m equivalent range. Require clean synchronization within one sample and clean range error within one native FFT-bin equivalent plus delay quantization. Compute tolerances from actual valid-window bandwidth; prohibit post-hoc tolerance widening. Include frame-boundary discontinuity and clipping failures.

For tone fixtures compare observed sideband frequency to independently calculated Doppler within native spectral resolution, and movement decisions against held-out controls using a frozen threshold. Short-time resolution must support the chosen speed; do not promise millimetre movement from a coarse spectrum.

Lifecycle tests cover stop during preparation/running, timeout, backend error, disposal, repeated start and mode changes. Stop cancels output generation, completes once, and cannot trigger an automatic restart. UI tests verify simulated labels, missing hardware state, parameter validation and distinct unknown/invalid/detected outcomes.

Do not label inspection of a Flutter preview as a native iOS build or physical validation. If runner tools are unavailable, report the exact boundary and continue independent offline work.

## Artifacts and commands

Each run has a unique ID and immutable configuration. Export emitted/received PCM WAVs, manifest JSON, metrics CSV, analysis arrays where practical, quality flags and plot images or a documented equivalent. Include UTC and monotonic times, schema/algorithm versions, source revision or content hashes, fixture seed/model, requested/actual audio format, waveform parameters, thresholds, calibration ID and cancellation/errors. For physical runs include device/OS/route, processing, latency and ground-truth measurement notes. Preserve provenance when reanalyzing; create a new analysis identity.

Export remains local and explicit. Flutter web downloads and native file/share export may need distinct adapters; document which target is actually verified. No auto-upload, automatic external share or overwrite. Store bulky/generated trial data outside source where practical and exclude necessary local build outputs from commits.

The implementation must document exact working commands after toolchain inspection. Expected Flutter commands are `flutter analyze`, `flutter test`, and a target-specific `flutter run`; these are planned, not executed evidence. Inspect entry points and configuration first. Use offline/no-resolution flags where supported and suitable, with disposable outputs and umask 077. Flutter commands may write SDK caches, package state or trigger resolution; obtain authorization if those effects exceed local disposable state. Do not run package managers, downloads, SDK repairs or platform installation implicitly.

Record command, revision, expected/observed writes, subprocess/network effects, exit status and output summary in `docs/WORK_RECEIPT.md`. Verification is evidence, not worker approval of release or scientific acceptance.

## Physical protocol and iPhone port

First perform short frequency-response probes, then compare tone and chirp modes in separate trials with documented duration, digital amplitude and system volume. Use a fixed speaker/microphone arrangement and a rigid reflector. Separate calibration positions/data from evaluation. For each mode collect five repeats at 0.30, 0.60 and 0.90 m under transmitter-on stationary, transmitter-on moving, transmitter-off stationary and transmitter-off moving conditions. Randomize order. For moving trials use two seconds stationary, six seconds between marked endpoints roughly ±10 cm, then two seconds stationary. Mark endpoints and keep transducers fixed; do not fabricate continuous ground truth.

Report trial-level detections, false detections, unavailable estimates, range bias, median/max error and invalid trials. Proposed physical targets are at least 80% moving-trial detection, no more than 10% false-positive control trials, and audible-band median range error at most 10 cm. Freeze targets before evaluation and report counts/uncertainty; these are not achieved results. Tone mode is assessed for movement, not absolute range.

The iPhone backend uses Swift, AVAudioEngine/AVAudioPlayerNode and an input tap, AVAudioSession playAndRecord/measurement, explicit microphone permission and usage description, preferred then verified actual sample rate, built-in route validation, disabled/inspected voice processing and available echo-cancellation state. Stop on interruption, backgrounding, route change and timeout; require a new Start. No background audio capability. Preserve sample/host timestamps and calibrate acoustic alignment independently of software scheduling. Capture/export comes before porting further DSP. Android and desktop backends are separate future adapters, not initial acceptance requirements.

An unmodified iPhone is the physical target. Simulator success cannot validate transducer response, residual processing, acoustic latency, multipath, audibility or detection error. The next measurable hardware milestone is one iPhone producing a valid local recording/export and distinguishable transmitter-on moving versus stationary/off controls.

## Attribution and unresolved rights

The upstream README declares MIT and names Joao Nuno Carvalho, but full license text/file-level notices were absent from the inspected tree. Retain declaration, author, commit and adapted-function lineage. Include required permission notices for reused code; do not invent an original copyright year. Record sample/image rights coverage as unresolved rather than representing confirmed clearance. Do not redistribute the paper or ambiguous assets by default. A fresh Dart implementation of documented mathematics can avoid copying exploratory code while retaining scientific attribution. Dependency notices are separate. No patent clearance has been established and no outreach is authorized.

## Sources

- [Upstream pinned source](https://github.com/joaocarvalhoopen/Partial_implementation_of_the_ApneaAPP_paper___FMCW_sonar/tree/3677815c2e955a554aaa6e2e1e23c8bd4b5f04fd)
- [ApneaApp paper, sonar methods and Android implementation](https://apnea.cs.washington.edu/apneaapp.pdf)
- [SoundWave acoustic Doppler research](https://www.microsoft.com/en-us/research/wp-content/uploads/2012/05/guptasoundwavechi2012.pdf)
- [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms)
- [Apple measurement mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement)
- [Apple microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [Apple audio sample-rate preference](https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferredsamplerate(_:))
- [MIT license text](https://opensource.org/license/mit)
