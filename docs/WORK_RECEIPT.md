# Implementation and verification receipt

## Scope and authorization

2026-10-28: user approved the Flutter simulated MVP, regular commits/pushes to humanifest-bot/phonopticon, and offline Flutter package resolution/validation using Legion's existing SDK/cache. No downloads, upgrades, live audio, deployment, secrets, permission changes or external messages. Runtime identity: legion on Darwin. Task writes use umask 077. Existing shell/global permissions unchanged.

SSH `ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -T git@github.com` returned `Hi humanifest-bot!` (GitHub's normal no-shell exit status 1). Existing Git author configuration is preserved. Planning commit 2366a72 was pushed to origin/main. The sandbox initially denied .git/index.lock; the authorized commit/push succeeded with sandbox escalation, without changing filesystem permissions.

## Core implementation milestone

New local Dart modules implement configuration, deterministic waveform/echo synthesis, a radix-2 FFT, tone-sideband movement analysis, chirp dechirping/range estimation and a replaceable AudioBackend. No upstream code or WAV/image assets are copied. Native backend explicitly reports unavailable and never falls back silently. The simulation does not open speakers/microphones or sockets.

Inspected test entry point: `tool/verify_core.dart` imports only Dart standard libraries and the authored local modules, constructs in-memory fixtures, emits console assertions and runs bounded event-loop lifecycle checks. No files, subprocesses, services, credentials or network are accessed by this script.

Executed:

```sh
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart --disable-dart-dev tool/verify_core.dart
```

Result: exit 0, 46 checks passed. Both moving fixtures detected. Stationary, transmitter-off and silence controls did not report movement. Invalid/clipped PCM rejected. Chirp alignment recovered a 73-sample offset at four fixture ranges; estimates met native-bin plus delay-quantization tolerance. Independent 140-sample delay recovered within declared tolerance. Cancellation, restart, duplicate-start, disposal and unavailable-native behavior passed. Synthetic evidence only.

## Offline Flutter setup

Inspected Flutter launchers, shared bootstrap, SDK pubspecs and cache-lock behavior before execution. Used the already compiled tool snapshot directly to avoid shell SDK upgrade/bootstrap paths. Version check reports Flutter 3.47.4, Dart 3.13.3. No toolchain repair performed.

Approved invocation prefix:

```sh
FLUTTER_ROOT=/opt/homebrew/Caskroom/flutter/3.47.4/flutter CI=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true /opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart /opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/flutter_tools.snapshot --suppress-analytics --no-version-check
```

Commands appended: `--version`, then `pub get --offline`. Both exit 0. Package resolution selected 24 SDK/cached packages and generated project package metadata/lockfile. The offline command prints a generic “Downloading packages...” heading, but offline resolution does not authorize or request online retrieval. It also added build/platform directory exclusions to analysis_options.yaml. Expected tool writes include SDK lock/cache metadata, approved tool settings and local project .dart_tool files. No SDK upgrade or live audio execution.

Flutter UI, rendered-runner behavior, exports and native builds are not yet verified at this milestone. The selected toolchain still lacks the iPhoneOS SDK; no physical validation is claimed.

## Flutter interface milestone

New Flutter UI implements mode/scene selection, constrained settings, explicit Start/Stop, countdown, simulated-source labels, absolute-power heatmaps, movement traces and a numerical frame inspector. Local exports are JSON bundles containing Float32 WAVs, manifest, analysis arrays, metrics CSV and standalone SVG plots. Web export uses a browser download; the IO adapter uses a new temporary directory. Neither uploads data.

Inspected `test/widget_test.dart` and pubspec before execution. Tests render in the cached flutter_tester subprocess, simulate button actions/time and exercise local in-memory DSP; no hardware audio or network. Expected writes: build/test caches, SDK lock metadata. Commands used the approved cached-tool prefix with `test --no-pub` and `analyze --no-pub`.

Initial results: static analysis found three console-print lint notices in the verification CLI; replaced with explicit stdout logging. Widget tests exposed scene/backend dropdown overflow at wide and phone widths; fixed selector constraints without relaxing tests. Rerun: analyzer exit 0, no issues; widget tests exit 0, all 3 passed (tone/chirp result workflow, stop/cancel and 390 px phone layout).

A local web build is being checked separately; widget success is not browser verification or native-platform validation.

## Expanded verification and examples

Added independent signed Doppler checks, held-out seeds 17/99 in audible and near-ultrasonic presets, raw WAV/export round-trip checks, known FNV vector, synthetic-truth independence, end-of-trial drift rejection, out-of-gate echoes, mixer-alias configuration rejection, sample discontinuity, stop during preparation and the exact ten-second PCM bound.

The latest dependency-free `tool/verify_core.dart` run exited 0 with **69 checks passed**. It remains in-memory/console-only. The Flutter suite imports this verifier as one numerical test. The expanded suite also covers native-unavailable and invalid-input UI states, cancellation, both modes, phone layout, and two completed-chirp renders. The last `test --no-pub` run exited 0 with **7 tests passed**, including the 69 numerical assertions.

Render tests read only already cached Roboto/MaterialIcons fonts and write PNGs into new private system-temp directories. Initial Ahem-font renders were unsuitable for text inspection; actual-font renders were regenerated and visually inspected at 1400 px and 390 px widths. Text/controls, heatmaps, movement traces, numerical estimates, export control and source/caveat labels are readable without layout overflow. These are flutter_tester renders, not screenshots of a browser or physical phone.

Inspected example/unpack entry points before running. They use Dart standard/local modules, create new output directories, write local JSON/WAV/CSV/SVG files and never run subprocesses, services or network/audio. Executed:

```sh
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart --disable-dart-dev tool/generate_examples.dart --out /private/tmp/phonopticon-examples-v1
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart --disable-dart-dev tool/unpack_bundle.dart /private/tmp/phonopticon-examples-v1/chirp-moving.json /private/tmp/phonopticon-chirp-moving-v1
/usr/bin/afinfo /private/tmp/phonopticon-chirp-moving-v1/received.wav
```

All exited 0. Eight bundles generated. The unpacked received WAV was independently reported as mono Float32, 48,000 Hz, 96,000 samples/two seconds. Copied only reproducible summary/configuration into examples/summary.json and configs/examples.json; raw output remains outside source. Seed-99 stationary chirp example: median 0.5971875 m for a 0.60 m fixture, native bin width 0.0376923 m. This is synthetic error, not physical accuracy.

## Web build and scoped browser probe

Using the cached-tool prefix, `build web --no-pub --no-web-resources-cdn --no-wasm-dry-run` exited 0. Local engine/font resources are bundled. The builder prints a CupertinoIcons font-family warning although the app uses Material icons; actual-font widget renders show the used icons. No Cupertino dependency was added merely to suppress this warning.

Started `python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web` for a temporary local demo. This binds loopback only and serves generated static files; no external publication. Added a page policy restricting resource connections to the same origin.

Browser tool: cua_repl, ChatGPT in-app browser, target http://127.0.0.1:8765/. Creation/read probe returned title Phonopticon and Flutter's Enable accessibility control. Screenshot capture reported `Unable to capture screenshot`; mouse activation timed out on CDP `Input.dispatchMouseEvent`. Documented keyboard activation did not yield a verified completed trial or export. No provider/profile switch, OS permission change, browser restart or desktop capture was attempted. The transport/input failure is not a diagnosis of app or model incompatibility. Browser interaction/export verification remains a coverage limit; widget/runtime and serialization verification are separate passing evidence.

## Delivery audit

- M0: original brief/steering, detailed plan and attribution preserved; rights uncertainty stays explicit and upstream code/assets are not copied.
- M1: explicit Start/Stop, configuration, unavailable native adapter, ten-second cap and cancellation/restart are implemented and exercised.
- M2: received-PCM estimators, independent delay/Doppler expectations, controls, invalid data and timing limitations are covered by 71 checks.
- M3: inspectable tone/range-time plots and numerical frame inspection are implemented; actual-font renders inspected; local bundle serialization/WAV unpacking verified. Browser download action remains unverified because of the scoped browser failure.
- M4: exact setup/run/verification commands, example configurations/results, this receipt, limitations and physical/iPhone procedure are present. Native builds and physical performance remain unverified.
- M5: supplied-recording legacy reproduction remains explicitly deferred under the user's mobile simulated-runner steering; the WAV's earlier structural inspection is not represented as reproduction.
- M6/M7: native iPhone capture and physical trials are future milestones with concrete prerequisites/protocol, not current results.

No scientific/editorial acceptance, release approval, deployment, physical validation or Metamaps/Orca integration is asserted by this worker receipt.

## Accessibility and foreground lifecycle

The app now keeps a semantics handle for its lifetime so assistive tools can inspect controls without a hidden accessibility opt-in. Added an inactive/resumed lifecycle check: backgrounding cancels a running simulation and resuming does not restart it. Reran analyzer and all seven Flutter tests after these changes: exit 0, no analyzer issues, 69 numerical assertions and all seven tests passing.


## Final backend contract and accessibility checks

Captures now carry actual sample rate, channel count and device metadata separately from requested configuration. Analysis rejects a mono/rate mismatch rather than assuming a preference was honored; WAV export records the actual received rate. Added two independent format/export checks: final numerical coverage is **71 assertions**, with **7 Flutter tests passing**. Latest static analysis exits 0 with no issues. Repeated example generation into /private/tmp/phonopticon-examples-v2 produced summary/configuration files byte-identical to the checked-in examples (cmp exit 0).

The final browser probe waited for the app controls, then read the full DOM/native accessibility tree. Isolated panel semantics fixed an observed progress-indicator grouping that hid controls from the native tree. After the fix, Start, Stop, modes, scene/backend selectors, sliders and export appear as independent native accessibility nodes. CDP mouse input still timed out, and documented native AX activation focused Start without an observed state transition. No completed browser trial, browser download or browser screenshot is claimed. This does not negate the independently passing actual Flutter widget/runtime, numerical, export-serialization and unpacked-WAV checks. Native hardware remains outside this milestone.

Regular milestone commits have been pushed throughout (2366a72, a077f17, 855f5d5, 274ee69, afe0232). Final delivery adds the format-contract/semantic-boundary fixes and this evidence. All task files are local/reviewable in Git, and no unrelated user files were changed. The loopback-only demo process is an optional local preview, not a deployment or audio service.

## Final source-bound build

Final compiled source commit: `85afabdddcea3418ee5ef67cc9c4bd07e742c93f`, pushed to origin/main and verified with `git ls-remote origin refs/heads/main`. Working tree was clean. Using the previously recorded cached-tool prefix, executed:

```sh
build web --no-pub --no-web-resources-cdn --no-wasm-dry-run --dart-define=SOURCE_REVISION=85afabdddcea3418ee5ef67cc9c4bd07e742c93f
analyze --no-pub
```

Both exit 0; analyzer reports no issues. The local build has main.dart.js and dependency NOTICES. The known unused-Cupertino font-family build warning remains documented above. The source-bound local page was reloaded, its Start control became visible, and the in-app tab was retained as the user-facing preview. No successful browser click/download is claimed. This final receipt addition changes documentation only; compiled app sources are exactly those at the recorded commit.

## Experimental computer microphone backend 2026 10 30

The user asked to actually test using the computer microphone. Implemented a conditional browser AudioBackend using same-origin Web Audio scripts and an AudioWorklet. No package installation, native iOS adapter, external service, automatic capture or microphone-to-speaker monitoring was added. The existing iTerm foreground server serves the rebuilt assets without migration/restart.

Physical recording requires backend selection, explicit Start and microphone permission. The worklet emits only the supplied bounded waveform, captures mono PCM on its rendering clock, zeroes output beyond the exact sample count, and stops after at most ten seconds. Stop/backgrounding/interruptions dispose microphone tracks and the AudioContext. Pending permission cancellation never emits and releases late-granted tracks. A 15-second setup timeout and recording-completion watchdog report failure without automatic retry. Partial explicit Stop can return cancelled raw PCM. Reported processing settings are retained; they are not treated as proof of unprocessed hardware audio.

PHYSICAL exports use actual context/input settings, input label, browser and reported latency/timing. They omit synthetic range/seed/echo-gain claims and have physicalValidation=false. Scores use uncalibrated fixture thresholds; chirp alignment still has a limited search window and can fail on desktop audio latency. Permission/setup/processor failures are visible; real performance remains unverified until operator-collected recordings are examined.

Reviewed the new JS/Dart code and tests before execution. `node --check web/computer_audio.js` and `node --check web/audio_capture_worklet.js` passed. `node tool/test_computer_audio.cjs` uses Node VM mock audio/permission objects only: exact sample cap, output zero tail, captured PCM, partial Stop, transmitter-off, completion cleanup, denial, late permission cancellation/no pre-grant emission, missing-input failure and duration guard passed. No real hardware was used by these tests.

With the previously recorded cached Flutter prefix: `analyze --no-pub` exited 0/no issues; `test --no-pub` exited 0 with 8 tests including the existing 71 numerical assertions and the new physical-labelled mock export schema check. `build web --no-pub --no-web-resources-cdn --no-wasm-dry-run` exited 0; known font-family warning unchanged. Both new JS files are present in build/web. No dependencies were downloaded.

The browser tool opened the app but continued reporting the old simulator-only controls and script list, while an independent local HTTP GET and the built index both contained the new audio script. Ordinary reload and a cache-ignoring developer reload did not establish updated visible controls; the latter tool call was unexpectedly slow. This is an unresolved browser observation/cache/control boundary, not a confirmed application diagnosis. No microphone permission was requested by the agent, and no physical recording or emission was performed. The operator should reload the app and select the experimental computer backend; if unavailable, report the browser restriction rather than silently switching browsers or devices.

Primary references: https://www.w3.org/TR/mediacapture-streams/ and https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/getSettings . Processing constraints are preferences; browser support and actual input/context formats must be recorded independently.

### Browser delivery follow-up

Resolved the old-interface delivery issue with a local-preview bootstrap that gives main.dart.js a fresh query URL and a versioned bootstrap script URL. A source-tagged build (`SOURCE_REVISION=423a522e349fd843d305853875126681becfbbcc`) passed. The fresh page now exposes the new Trial condition label. The app itself publishes non-sensitive capability booleans as a DOM data attribute; reading that attribute returned secureContext=true, microphoneApi=true, audioContext=true and audioWorklet=true. A direct generic evaluate probe could not inspect navigator/page globals reliably, so its earlier false availability result was discarded rather than treated as hardware evidence.

Node mock tests passed again after the capability report/loader changes. No browser permission, OS setting, device routing or stored privacy state was changed, and no actual microphone capture or speaker emission was initiated. The visible local page is ready for the operator to select Computer mic + speaker and press Start. API presence is not physical validation.

## Physical pilots and provisional calibration — 2026-11-04

The operator completed three real computer tone recordings: seated/stationary, seated/leaning and transmitter-off/leaning. Each exported 192,000 finite, unclipped mono Float32 samples over four seconds. The browser reports the built-in MacBook Pro microphone at 44.1 kHz; the AudioContext exports resampled 48 kHz PCM. Echo cancellation, noise suppression, AGC and voice isolation report false. The operator heard the probe in the moving trial and no probe in the off trial. Actual speaker routing, system volume, distance and trajectory were not independently measured.

All three were below the old fixture threshold. Peak stationary/moving/off scores: 0.0000110419823 / 0.0002300110200 / 0.0003199499062. This establishes foreground capture and operator-reported playback, not successful movement detection. Raw bundles, screenshots and a detailed local receipt are in a private temporary directory and original browser downloads; none are committed.

User requested calibration and fresh repeated trials. Added received-tone ratio calibration, explicit weak-carrier/unknown handling, route/settings/provenance checks, a local Float32 bundle decoder and calibration CLI, local-only profile import, and a fixed 15-attempt validation plan with manual Start/Next. Failed/cancelled attempts are retained; settings are locked during validation; all captured raw trials can be exported together. See TONE_CALIBRATION.md for the rule, exclusions and predeclared targets.

Inspected new test entry points and imports: standard/local Dart math and in-memory synthetic PCM; Flutter tester subprocesses and disposable build/render output only. No test opens real audio or contacts the network. First analyzer attempt was denied SDK lock access by the sandbox. Inspected Legion ownership/modes of the lock and parents, then used the previously authorized offline cached Flutter access; no chmod/chown or SDK changes.

Executed cached Flutter `analyze --no-pub`: exit 0, no issues. Executed `test --no-pub`: exit 0, **16 tests passed**, including the existing 71 numerical assertions, seven calibration tests and a guided validation lifecycle test. Tests cover an independent Doppler sideband, gain invariance, off/weak-probe rejection, route changes, invalid profiles, training reuse, calibration overlap, label independence, WAV decoding and manual Start/Next without automatic capture.

Executed the exact calibration CLI command in TONE_CALIBRATION.md with umask 077. It recomputed the three original physical WAV analyses and created a new private JSON profile: id 645c30b0, threshold 0.0033693911183156873, carrier floor 2.5168013685899415e-9. Pilot data is training only. Fresh held-out physical evaluation remains pending at this entry; no calibrated performance result is asserted.

## FMCW breathing mode, 2026-11-05

The operator redirected physical testing from leaning to small, slow reflector motion. Breathing mode uses a manual 30-second capture, with the audible 3–10 kHz chirp and digital peak amplitude 0.020 as the starting settings. The Mac trial uses the same echo window, room, volume and route for stationary, 0.25 Hz motion, and transmitter-off motion. Move a rigid reflector 5–10 mm peak-to-peak between marks without scraping and use the silent four-second visual pacer. The operator's timing and travel are approximate references.

The analysis matches repeated chirps to locate the direct probe modulo a sweep. It compares the early and late alignment, coherently averages sweeps in about 100 ms groups, and tracks complex echo coefficients across a fixed window of ±9 cm around the selected equivalent range. After direct-probe phase correction and detrending, it measures periodic variation at 0.10–0.60 Hz. This implementation is inspired by [ApneaApp's distance-gated periodic echo tracking](https://apnea.cs.washington.edu/apneaapp.pdf#page=4). Its algorithm and 3–10 kHz test band differ from the paper. Echo ratios do not measure chest displacement in millimeters.

After each attempt, use **Export local trial bundle**. Verify the set with the existing cached Dart SDK and a new output path:

```sh
umask 077
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart --disable-dart-dev tool/verify_breathing.dart STATIONARY.json MOTION.json OFF.json --out NEW_REPORT.json
```

The verifier independently recomputes the traces from the WAVs. Predeclared calibration criteria require an available stationary trace without a matching strong rhythm, an unavailable off trace due to absent chirp coherence, and moving rhythm within 0.05 Hz of 0.25 Hz. Moving periodic fraction must reach 0.25, and normalized periodic RMS must reach both 0.001 and three times stationary RMS. Each control and any analysis failure is reported. Meeting these criteria supports this calibration run only. Physical sensitivity and breathing rate remain separate tests.

Offline verification used cached Flutter `test --no-pub` and `analyze --no-pub` with the SDK prefix above. All 17 tests passed, including the 71 original numerical checks, and analyzer reported no issues. The synthetic breathing fixture recovered the 0.25 Hz rhythm with an 8 mm peak-to-peak reflector and over-one-sweep latency. Its stationary trace stayed below the amplitude floor and its transmitter-off input was rejected. `node tool/test_computer_audio.cjs` passed the mocked capture checks, including the new 30-second limit. `dart --disable-dart-dev tool/verify_breathing.dart` with no arguments printed usage and exited 2. The test runner reads cached SDK assets and writes local build metadata and temporary fixture renders. The replay tool reads named local WAV bundles and writes a new report. This entry records synthetic and mocked checks while the Mac captures are pending.
