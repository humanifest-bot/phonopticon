# Android and iOS build status

This repository now contains generated Flutter platform projects for Android and iOS. They preserve the shared Dart UI, trial runner, configuration and export schema. Both mobile builds default to `SimulatedBackend`; no mobile physical capture is implemented.

Mobile exports use a platform channel to present Android's document-creation picker or the iOS share sheet. The result is `saved`, `shared`, `cancelled`, or `error`; cancellation and native errors remain visible and do not advance guided export steps. Exported JSON includes the existing manifest, configuration, raw WAV data, analysis arrays and plots.

The app stops an active trial when `AppLifecycleState` leaves the foreground. The Flutter runner also exposes a manual Stop control with 48 px minimum button height and phone-width layout.

## Local inspection

Verified toolchain:

- Flutter 3.47.4, stable
- Dart 3.13.3
- macOS 27.2.1 on arm64
- Temurin JDK 17.0.21.1+2 at `$HOME/Library/Java/JavaVirtualMachines/jdk-17.0.21.1+2/Contents/Home`
- Android command-line tools 22.0
- Android platform/build tools 36, NDK 28.2.13676358, platform-tools 37.0.1
- Android Emulator 37.2.13 and API 36 Google APIs ARM64 image
- CocoaPods 1.16.2
- Android SDK installed under `$HOME/Library/Android/sdk`
- Android API 36 emulator available as `emulator-5554`; no physical Android device
- Xcode/iPhone SDK: incomplete
- iOS device/simulator: unavailable

The active Apple developer directory is `/Library/Developer/CommandLineTools`, not a full Xcode installation. `xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-path` fail, and no iPhoneOS SDK is present. The current account is not a sudoer, so it cannot change the system developer directory. An authorized Computer Use attempt to open the App Store timed out; no alternate UI-control path was used. Full Xcode and iOS builds remain blocked pending an administrator/user installation.

## Android setup and build

Platform project: `android/`.

This environment uses the Android command-line tools and a user-local Temurin JDK rather than Android Studio. Official downloads used:

- [Android command-line tools for Mac ARM64](https://dl.google.com/android/repository/commandlinetools-mac_arm64-15859902_latest.zip), SHA-256 `835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e`
- [Eclipse Temurin JDK 17 for Mac ARM64](https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.21.1%2B2/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.21.1_2.tar.gz), SHA-256 `2a88ccb044a8fb00957be93245da6357c11b55717511509d147cbcc5d93b2109`

Install the SDK packages required by this project and Flutter:

```sh
export JAVA_HOME="$HOME/Library/Java/JavaVirtualMachines/jdk-17.0.21.1+2/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
  'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir="$JAVA_HOME"
flutter doctor -v
```

Google Android SDK licenses were explicitly accepted for this local setup. The Emulator 37.2.13 and `system-images;android-36;google_apis;arm64-v8a` were installed for simulated workflow checks. A headless emulator was booted with `-no-audio`; no acoustic output was produced.

Expected debug build and run commands:

```sh
cd /Users/legion/dev/humanifest/phonopticon
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run --debug
```

Verified in this environment:

```sh
flutter build apk --debug --no-pub
flutter run -d emulator-5554 --no-pub --no-resident --no-dds
```

The APK compiled, installed and launched on the API 36 emulator. The first
`flutter run` attempt failed to attach DDS; retrying with `--no-dds` exited 0.
The emulator was headless, so this is not evidence that native document-picker
save/cancel UI or on-device trial controls were manually exercised. Flutter
widget tests cover the corresponding simulated states and phone layouts.

For a signed release, generate and protect a release keystore and configure Gradle signing through approved local properties/secrets. No release signing credentials are present in this repository.

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
the Android debug key. A release build without a complete file fails explicitly rather than silently
using an improperly signed artifact. This was verified locally:
`flutter build apk --release --no-pub` failed with the message that release
signing is not configured. Debug builds use the SDK/Gradle debug configuration and do not
require release credentials; the generated APK was verified with the Android
debug certificate.

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
| Android | Yes | API 36, JDK 17, NDK 28.2; emulator 37.2.13 | Debug APK compiled; app installed/launched on API 36 emulator; native picker workflow not UI-verified |
| iOS | Yes | Full Xcode/iPhoneOS SDK absent; account cannot switch developer directory | Project generated; simulator/device build unverified |
| macOS | No platform directory | Xcode incomplete | Existing desktop mode remains web/macOS verification pending |
| Web | Yes | Chrome/Flutter available | Separate browser/AudioWorklet evidence; not a mobile native build |

Physical phone capture remains unavailable on both generated mobile projects. The Android emulator is simulated UI execution only; no physical Android/iPhone operation or acoustic capability is established.
