import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/export/artifacts.dart';

void main() {
  test('FNV-1a uses exact 32-bit multiplication and known vectors', () {
    expect(fingerprint(const []), '811c9dc5');
    expect(fingerprint(utf8.encode('hello')), '4f9f2cab');
    final bytes = List<int>.generate(10000, (i) => (i * 73 + 19) & 255);
    var reference = BigInt.from(0x811c9dc5);
    final mask = BigInt.from(0xffffffff);
    for (final byte in bytes) {
      reference =
          ((reference ^ BigInt.from(byte)) * BigInt.from(0x01000193)) & mask;
    }
    expect(fingerprint(bytes), reference.toRadixString(16).padLeft(8, '0'));
  });

  test(
    'legacy browser arithmetic remains available only for compatibility',
    () {
      expect(legacyBrowserFingerprint(utf8.encode('hello')), '8da7dac0');
      expect(
        legacyBrowserFingerprint(
          List<int>.generate(10000, (i) => (i * 73 + 19) & 255),
        ),
        '4561c61a',
      );
      expect(
        legacyBrowserFingerprint(utf8.encode('hello')),
        isNot(fingerprint(utf8.encode('hello'))),
      );
    },
  );
}
