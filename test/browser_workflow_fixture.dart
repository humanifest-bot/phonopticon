// Disposable browser-integration fixture. Never opens a real microphone or
// speaker. Build only to a separate temporary directory and serve on a
// separate loopback origin; do not deploy as the real app.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:phonopticon/audio/audio_backend.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/export/artifacts.dart';
import 'package:phonopticon/main.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          PhonopticonApp(backend: _FixtureBackend()),
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.yellow,
                child: Text(
                  'TEST FIXTURE · NO MICROPHONE OR SPEAKER · FNV hello ${fingerprint(utf8.encode('hello'))} · legacy ${legacyBrowserFingerprint(utf8.encode('hello'))}',
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FixtureBackend implements AudioBackend, MicrophoneMeterBackend {
  Completer<void>? _meter;
  Timer? _timer;
  @override
  AudioCapabilities get capabilities => const AudioCapabilities(
    'browser-test-fixture',
    'PHYSICAL',
    true,
    'TEST ONLY: physical audio disabled',
  );
  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double)? onProgress,
  }) async =>
      throw UnsupportedError('Test fixture cannot capture or play audio');
  @override
  Future<void> stop() async {}
  @override
  Future<void> startMeter({
    required void Function(double level) onLevel,
  }) async {
    if (_meter != null) throw StateError('Fixture meter already active');
    final completion = _meter = Completer<void>();
    onLevel(.1); // Synthetic level; no permission request or audio input.
    _timer = Timer(const Duration(seconds: 30), stopMeter);
    await completion.future;
  }

  @override
  Future<void> stopMeter() async {
    _timer?.cancel();
    final completion = _meter;
    _meter = null;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  @override
  Future<void> dispose() => stopMeter();
}
