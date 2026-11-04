import 'dart:convert';
import 'dart:typed_data';
import '../domain/experiment.dart';

// Decode the authored bundle format; no file/network access here.
AudioCapture readPhysicalBundle(Map<String, dynamic> data) {
  final m = data['manifest'] as Map;
  final c = m['config'] as Map;
  final files = data['files'] as Map;
  final actual = m['actualAudioFormat'] as Map;
  if (m['schemaVersion'] != 1 ||
      m['sourceKind'] != 'PHYSICAL' ||
      c['mode'] != 'tone' ||
      actual['channels'] != 1) {
    throw FormatException('Expected a physical mono tone bundle');
  }
  final config = ExperimentConfig(
    mode: ProbeMode.tone,
    scenario: Scenario.values.byName(c['scenario'] as String),
    sampleRate: c['sampleRate'] as int,
    durationSeconds: (c['durationSeconds'] as num).toDouble(),
    amplitude: (c['amplitude'] as num).toDouble(),
    toneHz: (c['toneHz'] as num).toDouble(),
  );
  config.validate();
  Float64List pcm(String key, int rate) {
    final bytes = base64Decode(files[key] as String);
    if (bytes.length < 44) throw FormatException('Truncated WAV');
    final h = ByteData.sublistView(bytes);
    String tag(int start) => ascii.decode(bytes.sublist(start, start + 4));
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WAVE' ||
        tag(12) != 'fmt ' ||
        tag(36) != 'data' ||
        h.getUint32(16, Endian.little) != 16 ||
        h.getUint16(20, Endian.little) != 3 ||
        h.getUint16(22, Endian.little) != 1 ||
        h.getUint16(34, Endian.little) != 32 ||
        h.getUint32(24, Endian.little) != rate ||
        h.getUint32(40, Endian.little) != bytes.length - 44 ||
        (bytes.length - 44) % 4 != 0 ||
        h.getUint32(4, Endian.little) != bytes.length - 8) {
      throw FormatException('Unsupported or inconsistent Float32 WAV');
    }
    return Float64List.fromList([
      for (var i = 44; i < bytes.length; i += 4) h.getFloat32(i, Endian.little),
    ]);
  }

  return AudioCapture(
    config: config,
    emitted: pcm('emitted.wav.base64', config.sampleRate),
    received: pcm('received.wav.base64', actual['sampleRate'] as int),
    startedUtc: DateTime.parse(m['startedUtc'] as String),
    sourceKind: 'PHYSICAL',
    backendId: m['backend'] as String,
    cancelled: m['cancelled'] as bool,
    status: (m['status'] as List).cast<String>(),
    actualSampleRate: actual['sampleRate'] as int,
    deviceMetadata: Map<String, Object?>.from(m['deviceMetadata'] as Map),
  );
}
