# Phonopticon

A Flutter acoustic-sonar feasibility runner with **tone movement** and **chirp ranging** modes. It supports deterministic simulation and an experimental browser microphone/speaker backend. Physical audio starts only after explicit Start and microphone permission. Neither mode estimates health conditions or establishes validated physical sonar performance.

Tone mode shows a Doppler spectrum and movement score; a single tone provides no absolute range. Chirp mode shows equivalent range versus time, a movement score, alignment and numerical frame inspection. The browser computer-audio backend and simulator share `AudioBackend`; native iOS/Android adapters remain unavailable. There is no silent fallback to simulation.

## Foucault and the risk of acoustic surveillance

The name Phonopticon invites a comparison with Jeremy Bentham's panopticon and Michel Foucault's account of it in *Discipline and Punish*. Bentham's design allowed an observer to watch people who could not tell when they were being watched. Foucault treated this uncertainty as a means of discipline: people can come to regulate their own behaviour under the possibility of observation. See [Bentham's design](https://www.ucl.ac.uk/engage/museums-collections/auto-icon-jeremy-bentham/panopticon) and [Foucault's “Panopticism”](https://www.foucault.info/documents/foucault.disciplineAndPunish.panOpticism/).

For acoustic sensing, the concern is who controls observation and whether those affected can understand, refuse or stop it. A more capable or modified system could be used for covert presence or movement monitoring, coercive surveillance at work or at home, or behavioural judgements based on unreliable signals. Raw microphone recordings can also contain conversations unrelated to the experiment. These are possible abuses, not capabilities validated by this MVP or evidence that a third party deploys acoustic surveillance.

Experiments should be overt and voluntary, with informed consent from people affected, a clear purpose and limited retention of recordings. Browser microphone permission from the operator does not establish consent from bystanders. Explicit Start/Stop controls, short trials and local storage reduce exposure, but do not by themselves make every use acceptable.

## Quick start in iTerm2

Choose **Profiles → Phonopticon — local — Legion Mac — all servers**. This starts the project's only required server, the existing Flutter web build at **http://127.0.0.1:8765/**, with logs visible in that pane. Wait for `READY`; a shell prompt alone does not indicate readiness.

Press **Ctrl-C** to stop the owned server. The pane remains open with its exit status: enter `r` to restart, `s` to check readiness, or `q` to close. Selecting the profile again refuses duplicates or unrelated port conflicts without killing anything. It does not build, install, emit audio, start native services or access Norway.

The profile is installed only under Legion's iTerm DynamicProfiles directory. Versioned source: `tool/Phonopticon-Local.iterm.json`; launch contract: `tool/dev_launch.json`; foreground launcher: `tool/dev_session.zsh`. The local reservation is `/Users/legion/Documents/Codex/dev-ports.json`; lock/diagnostic metadata is `/Users/legion/Documents/Codex/phonopticon-dev`. Logs stay in terminal scrollback; automatic input/session logging is disabled.

To run the same entry directly:

```sh
/bin/zsh -f /Users/legion/dev/humanifest/phonopticon/tool/dev_session.zsh
```

If reinstalling this project's profile is explicitly intended, run `python3 -B tool/install_iterm_profile.py`. It creates only missing project configuration and refuses differing existing profile/registry content. Build updates remain a separate deliberate step using the commands below.

## Run locally

Verified environment: macOS under legion, Flutter 3.47.4, Dart 3.13.3, existing SDK/package artifacts. The app currently has a web runner; native iOS/Android platform projects and physical capture are deferred. No installation, download, signing, account setup or SDK repair is included.

The following function uses the cached Flutter tool directly, avoiding the shell launcher's automatic SDK bootstrap/upgrade path. It suppresses telemetry and update checks. Use a compatible pre-existing SDK; change `sonar_flutter_sdk` only to your authorized SDK location.

```sh
cd /Users/legion/dev/humanifest/phonopticon
umask 077
sonar_flutter_sdk=/opt/homebrew/Caskroom/flutter/3.47.4/flutter
flutter_cached() {
  FLUTTER_ROOT="$sonar_flutter_sdk" CI=true \
  FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true \
  "$sonar_flutter_sdk/bin/cache/dart-sdk/bin/dart" \
  "$sonar_flutter_sdk/bin/cache/flutter_tools.snapshot" \
  --suppress-analytics --no-version-check "$@"
}
flutter_cached pub get --offline
flutter_cached analyze --no-pub
flutter_cached test --no-pub
flutter_cached build web --no-pub --no-web-resources-cdn --no-wasm-dry-run
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

Open **http://127.0.0.1:8765/** in the in-app browser. Stop the local server with Ctrl-C. Build/test tooling writes local `.dart_tool`/`build` state and SDK lock/cache metadata. Offline package resolution requires cached dependencies; do not remove `--offline` to work around a missing package without authorization. Missing SDK artifacts require an explicitly approved setup step, not an automatic download. Web assets are bundled and the page blocks external resource connections. No cloud service is needed.

To bind a build to a committed source version, add `--dart-define=SOURCE_REVISION=YOUR_COMMIT_SHA` to the build command, using the exact checked-out commit. An untagged development build declares `unrecorded-development-build` in exports rather than inventing provenance.

## Use the runner

1. Select Tone movement or Chirp ranging.
2. Choose moving, stationary, transmitter-off, silence or invalid PCM.
3. Optionally select the near-ultrasonic candidate; this changes simulated parameters only.
4. Set 1–10 seconds, digital peak amplitude (default 0.02) and fixture range.
5. Press Start. Stop cancels the trial; leaving the foreground also requests Stop. Nothing starts on launch or resumes automatically.
6. Inspect the heatmap, movement score and frame values. The 0.15 threshold requires at least two frames and is a fixed fixture setting, not a physically calibrated detector.
7. Export a local JSON trial bundle. Web requests a browser download; the IO export adapter writes into a new temporary directory when used by a future native runner. There is no automatic upload or external share.

Browser automation is distinct from widget execution. See [verification receipt](docs/WORK_RECEIPT.md) for the exact observed browser/tool limits and actual commands/results.

## Test with the computer microphone

1. Use the iTerm profile to serve the rebuilt app at `http://127.0.0.1:8765/`, then reload the page.
2. Select **Computer mic + speaker (experimental)** in Audio backend. If unavailable, this browser does not expose the required secure microphone/AudioWorklet APIs; no substitute device is opened.
3. Use built-in speakers and microphone, with low system volume. Begin with **Tone movement**, the audible preset, 4 seconds and default 0.02 digital amplitude. Digital amplitude is not a calibrated sound-pressure level.
4. Choose Stationary reflector, press Start and grant microphone permission for this localhost origin. Repeat with Moving reflector and with Transmitter off. Move a rigid board while leaving the computer fixed; avoid tapping/scraping it.
5. Compare spectra/scores and export each local PHYSICAL bundle. The fixture threshold is uncalibrated; a high score can be ambient noise or processing. Chirp estimates require reliable alignment and calibration, so unavailable ranging is a valid outcome.
6. Stop ends output/capture and releases the microphone. Backgrounding, interruption, denied permission and timeout stop the trial without automatic retry. Do not change system privacy permissions merely to force a pass.

The Web Audio worklet clocks emitted/captured PCM together and caps output at the exact sample count (maximum ten seconds). It requests processing off and exports reported input settings, context sample rate, input label, browser, reported latency and timestamps. Requests do not prove the hardware path is unprocessed; resampling/routing can intervene. There is no microphone-to-speaker monitoring/feedback, upload, new dependency, or audio on page load. Browser support and real acoustic performance still need direct hardware checks.

## Reproduce offline examples

The dependency-free Dart checks can run without Flutter package resolution:

```sh
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart \
  --disable-dart-dev tool/verify_core.dart
```

Generate all eight reference bundles into a **new** directory (existing output directories are rejected):

```sh
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart \
  --disable-dart-dev tool/generate_examples.dart --out /private/tmp/phonopticon-examples-NEW
/opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/cache/dart-sdk/bin/dart \
  --disable-dart-dev tool/unpack_bundle.dart \
  /private/tmp/phonopticon-examples-NEW/chirp-moving.json \
  /private/tmp/phonopticon-chirp-moving-NEW
```

Use a different NEW suffix for each run. The generator uses fixed UTC metadata and seed 99. [Example configurations](configs/examples.json) and [observed summary](examples/summary.json) are checked in; raw bundles stay outside the repository. Exact example-generation commands/results are in the receipt. Other platforms may differ in the last floating-point digits; assess numerical tolerances separately from byte fingerprints.

A bundle contains emitted/received Float32 WAVs encoded as base64, manifest/configuration, timing, full analysis arrays, metrics CSV and standalone SVG heatmap/movement plots. The unpacker restores these to a new local directory and never plays audio. FNV-1a fingerprints detect ordinary content differences; they are noncryptographic and provide no authenticity or approval guarantee.

For example, the held-out seed-99 stationary chirp fixture at 0.60 m yields a median equivalent range of 0.5971875 m, with a native valid-window bin width of about 0.03769 m. This is a synthetic numerical result, not a real-world error specification. Both moving examples report movement; stationary/off examples do not, and chirp transmitter-off reports unavailable alignment. Invalid PCM returns an explicit failure.

## Architecture and next work

- `lib/domain`: configuration, PCM captures, quality and results.
- `lib/audio`: replaceable backend contract, simulation and explicit native stub.
- `lib/signal`: waveform/delay/noise model, FFT and analysis.
- `lib/runner`: bounded trial lifecycle.
- `lib/ui`: plots and numerical inspection.
- `lib/export`: local artifacts and platform export adapters.
- `tool`: dependency-free verification, example generation and unpacking.

The first physical milestone is one foreground iPhone capture/playback adapter that exports schema-compatible PCM with actual route/rate/processing/timestamps. Read the [native port and physical procedure](docs/PHYSICAL_TEST_PLAN.md) before hardware work. The selected local toolchain lacks the iPhoneOS SDK; no native build is claimed.

See [limitations](docs/LIMITATIONS.md), [build plan](BUILD_PLAN.md), [original brief and decisions](docs/ORIGINAL_REQUEST.md), and [attribution/reuse notes](THIRD_PARTY_NOTICES.md). No upstream WAVs or Python code are redistributed.
