import 'dart:math' as math;
import 'dart:typed_data';

int nextPowerOfTwo(int n) { var p = 1; while (p < n) { p *= 2; } return p; }

// Iterative radix-2 FFT. Power normalized by sum of the applied window.
List<double> spectrum(List<double> data, {int? fftSize}) {
  final n = fftSize ?? nextPowerOfTwo(data.length);
  if (n < data.length || n & (n - 1) != 0 || data.length < 2) {
    throw ArgumentError('FFT requires a power-of-two size and at least two samples.');
  }
  final re = Float64List(n), im = Float64List(n);
  var weight = 0.0;
  for (var i = 0; i < data.length; i++) {
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (data.length - 1));
    re[i] = data[i] * w; weight += w;
  }
  for (int i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    while (j & bit != 0) { j ^= bit; bit >>= 1; }
    j ^= bit;
    if (i < j) { final v = re[i]; re[i] = re[j]; re[j] = v; }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    for (var start = 0; start < n; start += len) {
      var wr = 1.0, wi = 0.0;
      for (var j = 0; j < len ~/ 2; j++) {
        final a = start + j, b = a + len ~/ 2;
        final vr = re[b] * wr - im[b] * wi, vi = re[b] * wi + im[b] * wr;
        re[b] = re[a] - vr; im[b] = im[a] - vi;
        re[a] += vr; im[a] += vi;
        final next = wr * math.cos(angle) - wi * math.sin(angle);
        wi = wr * math.sin(angle) + wi * math.cos(angle); wr = next;
      }
    }
  }
  return [for (var k = 0; k <= n ~/ 2; k++) (re[k] * re[k] + im[k] * im[k]) / (weight * weight)];
}
