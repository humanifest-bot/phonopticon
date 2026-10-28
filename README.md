# Phonopticon

A Flutter acoustic-sonar feasibility runner with **tone movement** and **chirp ranging** modes. This version generates and analyzes deterministic simulated PCM. It does not access a microphone, emit audio, estimate health conditions or establish physical sonar performance.

Tone mode shows a Doppler spectrum and movement score; a single tone provides no absolute range. Chirp mode shows equivalent range versus time, a movement score, alignment and numerical frame inspection. The native backend is an explicit unavailable adapter behind `AudioBackend`; it never silently switches to simulation.

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
