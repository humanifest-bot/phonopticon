import 'package:flutter_test/flutter_test.dart';
import '../tool/verify_core.dart' as verification;

void main() {
  test(
    'independent PCM numerical, export and lifecycle verification',
    verification.main,
  );
}
