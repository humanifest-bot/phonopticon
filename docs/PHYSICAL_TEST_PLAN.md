# Native iPhone port and physical experiment

## First capture adapter

Implement Swift capture/playback behind AudioBackend after the simulated workflow is verified. Keep Flutter controls, results, PCM schema, experiment configurations and offline analysis contracts. iOS and Android require their own audio adapters; shared UI does not establish shared acoustic behavior.

Prerequisites: an approved full Xcode/iPhoneOS SDK installation, compatible device, authorized signing arrangement and explicit permission to conduct short acoustic trials. The selected local Command Line Tools installation cannot currently locate the iPhoneOS SDK. Do not install or switch toolchains automatically. A simulator cannot validate the phone's acoustic path.

1. Add the iOS platform project using approved tooling and review generated files. No cloud backend, analytics or background audio capability.
2. Implement explicit microphone permission with AVAudioApplication.requestRecordPermission and an accurate NSMicrophoneUsageDescription. Permission denial is an unavailable state; do not switch devices or modes silently.
3. Configure AVAudioSession playAndRecord and measurement. Request an appropriate preferred sample rate and buffer duration, activate, select/verify built-in input and speaker route, then read actual rates, node formats and channels. Measurement mode reduces some processing but does not promise raw response.
4. Configure AVAudioEngine input capture and scheduled AVAudioPlayerNode buffers. Disable/inspect voice processing before start; inspect available session echo-cancellation state and record it. Never assume a preference was honored.
5. Preallocate bounded PCM buffers, keep file IO/analysis/UI work outside real-time callbacks, and record host/sample timestamps, output waveform identity, reported latency and all dropped/overflow/underflow conditions.
6. Enforce the ten-second maximum and low initial digital amplitude natively as well as in Flutter. Start only on the explicit foreground action. Stop on manual action, timeout, route change, interruption, backgrounding or failure. Do not resume automatically.
7. Export received/emitted PCM and actual session metadata locally. Check the export through the validated desktop/reference pipeline before adding on-device processing complexity. Do not assume capture/playback scheduling removes acoustic latency.

Acceptance for the first adapter: one valid ten-second-or-shorter foreground recording, matching output/configuration metadata, verified actual route/rate, visible Stop, early-stop export, and a denied-permission/error path. This establishes capture/export only, not sonar detection.

Official API references are linked in BUILD_PLAN.md. Recheck current SDK availability and documentation when implementing the adapter.

## Hardware characterization

Use a fixed phone on a support with a rigid approximately A4-size board. Keep other people/moving objects out of the test area and keep recordings local. Record board material/size, speaker/microphone positions, phone orientation, device/OS, room arrangement, sample rate, amplitude, system volume and ambient conditions. Do not promise inaudibility or infer sound pressure from digital amplitude.

Begin with short low-amplitude tone probes at selected frequencies across the audible and near-ultrasonic bands. Record received carrier/noise levels and harmonics/distortion with transmitter-off controls. This characterizes the combined speaker–room–microphone path, not either transducer in isolation. Select the usable carrier/band before evaluation; never raise amplitude automatically to obtain a result. Near-ultrasonic failure is an acceptable feasibility finding.

Use separate calibration data: empty scene, fixed reflector and measured calibration positions distinct from evaluation positions. Calibrate timing offset/direct path and, where justified, transducer geometry. Save the calibration and algorithm versions. Tone and chirp settings should have documented duration, digital amplitude and system volume; equal digital settings do not imply equal acoustic energy.

## Evaluation protocol

Freeze thresholds, range gate, alignment/quality rules and calibration before collecting evaluation trials. For **each mode** use five repetitions at 0.30, 0.60 and 0.90 m under four conditions, giving 60 trials per mode and 120 total, plus separate calibration trials:

| Condition | Transmitter | Reflector |
| --- | --- | --- |
| A | On | Stationary |
| B | On | Moving |
| C | Off | Stationary |
| D | Off | Moving as in B |

Randomize trial order with a recorded seed/order. Use two seconds stationary, six seconds of repeated movement between marked endpoints approximately ±10 cm, then two seconds stationary. Record actual endpoints and movement instructions. Avoid tapping/scraping the board, moving the phone, or changing route/volume midtrial. Off/moving trials expose handling sounds as a confound. Endpoint marks are not continuous trajectory ground truth.

For ranging, report error at measured stationary/held positions, with range reference and transducer-separation caveats. Do not compare an estimated continuous trajectory against invented true positions. Tone mode is evaluated for movement, not absolute range.

## Report and decision

Publish no results automatically. Produce a local report containing configuration/calibration/revision identities, raw artifact hashes, all trial IDs and exclusions, detections and control false detections as counts and rates, unavailable estimates, dropouts, failures, range bias, median/maximum absolute error and repeatability. Report per mode/band/distance rather than pooling away failures. Small sample sizes require appropriately limited conclusions.

Predeclared initial targets: at least 80% moving-trial detection, at most 10% control-trial false detections, and audible-band median range error at most 10 cm for the measured interval. These are proposed feasibility targets, not achieved performance. Failure prompts a documented change and fresh held-out evaluation; it does not authorize changing thresholds on the same evaluation trials until they pass.
