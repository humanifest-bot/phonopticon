# Android and iOS build status

This repository now contains generated Flutter platform projects for Android and iOS. They preserve the shared Dart UI, trial runner, configuration and export schema. Both mobile builds default to `SimulatedBackend`; no mobile physical capture is implemented.

Mobile exports use a platform channel to present an Android share sheet or iOS share sheet. The result must be `shared`, `saved`, `cancelled`, or `error`; cancellation and native errors remain visible and do not advance guided export steps. Exported JSON includes the existing manifest, configuration, raw WAV data, analysis arrays and plots.

The app stops an active trial when `AppLifecycleState` leaves the foreground. The Flutter runner also exposes a manual Stop control with 48 px minimum button height and phone-width layout.

## Local inspection (2026-11-17)

Verified toolchain:

- Flutter 3.47.4, stable
- Dart 3.13.3
- macOS 27.0.1 on arm64
- Java 21/other JDK available at `/usr/bin/java`
- CocoaPods 1.16.2
- Android SDK: not located
- Android emulator/device: none connected
- Xcode/iPhone SDK: incomplete
- iOS device/simulator: not available for a native build

The active Apple developer directory is `/Library/Developer/CommandLineTools`, not a full Xcode installation. `xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-path` fail, and no iPhoneOS SDK is present. Do not install or switch SDKs as an implicit build side effect.

## Android setup and build

Platform project: `android/`.

Install Android Studio and an Android SDK outside this repository, accept the applicable licenses, then configure Flutter:

```sh
flutter config --android-sdk /absolute/path/to/Android/sdk
flutter doctor -v
flutter doctor --android-licenses
```

Install an SDK platform/Build Tools package matching the generated Flutter project, plus an emulator or connect an authorized physical device. Physical capture must not be added merely because the app can compile.

Expected debug build and run commands:

```sh
cd /Users/legion/dev/humanifest/phonopticon
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run --debug
```

For a signed release, generate and protect a release keystore and configure Gradle signing through approved local properties/secrets. The generated project has no release signing configuration; this repository contains no credentials.

Release signing is intentionally not available unless `android/key.properties` is
created outside version control. The file must contain paths and passwords for
an authorized keystore:

```properties
storeFile=/absolute/private/path/release.keystore
storePassword=<keystore-password>
keyAlias=<authorized-key-alias>
keyPassword=<authorized-key-password>
```

Keep `key.properties`, `*.keystore`, and `*.jks` out of Git. The Gradle
configuration reads this file only for the `release` build type; it never uses
the Android debug key. A release build without a complete file is expected to
fail signing verification rather than silently producing an improperly signed
artifact. Debug builds use the SDK/Gradle debug configuration and do not require
release credentials.

The manifest declares `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS`, but the shared app currently selects `SimulatedBackend` and makes no native audio calls. These declarations do not grant permission or establish capture capability. Runtime microphone permission and route handling belong in a future native `AudioBackend` implementation.

## iOS setup and build

Platform project: `ios/`.

Install a full Xcode release from Apple, switch the developer directory, launch Xcode once, and accept its license:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
xcrun --sdk iphoneos --show-sdk-path
flutter doctor -v
```

Open/sign the project in Xcode only after the SDK and signing setup are authorized. For a simulator build after full SDK setup:

```sh
cd /Users/legion/dev/humanifest/phonopticon
flutter pub get
flutter analyze
flutter test
flutter build ios --debug --simulator
flutter run
```

For a physical device, select an approved team/signing identity and install from Xcode or a configured `flutter run -d <device-id>`. Simulator and physical-device builds are not equivalent evidence.

The iOS project declares `NSMicrophoneUsageDescription`:

> Phonopticon uses the microphone only for an explicit foreground acoustic trial. Native capture is not implemented in this build.

This declaration is intentionally not evidence of a native implementation. No background audio mode or background permission is enabled.

## iOS native adapter assessment

The smallest defensible first adapter is:

1. AVAudioSession category `playAndRecord`, mode `measurement`, explicit activation/deactivation, no automatic retry.
2. Microphone permission through `AVAudioApplication.requestRecordPermission(completionHandler:)`; denial and restricted states remain unavailable.
3. Request a preferred sample rate/buffer duration, but export the actual session and AVAudioEngine formats rather than the requested values.
4. Inspect and record built-in input/output route, channel counts, voice-processing/echo-cancellation state and hardware latency. Do not infer either route or processing from an accepted preference.
5. Use AVAudioEngine input tap plus scheduled AVAudioPlayerNode output buffers. Preallocate bounded PCM, keep DSP/file work outside real-time callbacks, and preserve host/sample timestamps.
6. Stop on explicit Stop, timeout, app backgrounding, interruption, route change, node failure or engine failure. No automatic restart.
7. Export mono Float32 WAV plus the existing `manifest/config/actualAudioFormat/deviceMetadata` schema. Export from local files only.

Apple references to verify again against the installed SDK/docs:

- [Recording from the microphone](https://developer.apple.com/documentation/avfaudio/recording-audio-from-a-microphone)
- [AVAudioSession recording permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [AVAudioSession measurement mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement)
- [Preferred sample-rate setting](https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferredsamplerate(_:))
- [AVAudioSession route](https://developer.apple.com/documentation/avfaudio/avaudiosession/currentroute)
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)

Implement this only after full Xcode/iPhoneOS availability, signing and approved hardware. A simulator can compile UI code but cannot establish microphone/speaker response, near-ultrasonic capability, latency, distortion or route behavior. A physical phone should be characterized with fixed transducers and a rigid reflector before scientific evaluation.

## Android native port assumptions

The same Flutter and export contracts should be wrapped by a future Android `AudioBackend`. A concrete first port needs:

- `AudioRecord`/`AudioTrack` or the Oboe implementation for bounded real-time PCM
- `MediaRecorder.AudioSource.UNPROCESSED` only when the selected API/device supports it; fallback must be visible
- permission request and runtime denial/error handling
- sample-rate discovery with `getSampleRate`/`AudioManager` and actual sink/source formats
- communication-device/route inspection, channel mask, buffer size and system volume
- foreground lifecycle stop and no background service
- 48 kHz request with actual hardware format verification

The initial Android target should compile with an emulator/simulator and run only the simulated runner until native audio is implemented and hardware-verified.

## Verification matrix

| Platform | Project available | SDK/build tools | Build/run result |
| --- | --- | --- | --- |
| Android | Yes | SDK absent | Project generated; build/run unverified |
| iOS | Yes | Full Xcode/iPhoneOS SDK absent | Project generated; simulator/device build unverified |
| macOS | No platform directory | Xcode incomplete | Existing desktop mode remains web/macOS verification pending |
| Web | Yes | Chrome/Flutter available | Separate browser/AudioWorklet evidence; not a mobile native build |

Physical phone capture remains unavailable on both generated mobile projects.
