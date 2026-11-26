// Deterministic arithmetic check; no recordings, filesystem or network access.
import 'dart:convert';
import '../lib/export/artifacts.dart';

void main() {
  final hello = utf8.encode('hello');
  final long = List<int>.generate(10000, (i) => (i * 73 + 19) & 255);
  final checks = {
    'canonical hello': (fingerprint(hello), '4f9f2cab'),
    'legacy browser hello': (legacyBrowserFingerprint(hello), '8da7dac0'),
    'canonical long': (fingerprint(long), '50259ab5'),
    'legacy browser long': (legacyBrowserFingerprint(long), '4561c61a'),
  };
  for (final entry in checks.entries) {
    if (entry.value.$1 != entry.value.$2) {
      throw StateError('${entry.key}: ${entry.value.$1} != ${entry.value.$2}');
    }
    // This command intentionally reports the known-vector results.
    // ignore: avoid_print
    print('${entry.key}: ${entry.value.$1}');
  }
}
