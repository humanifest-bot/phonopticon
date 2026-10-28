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
