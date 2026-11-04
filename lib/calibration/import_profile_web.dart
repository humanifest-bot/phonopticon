// Local file selection only; no upload or server request.
import 'dart:async';
import 'dart:html' as html;

Future<String?> importProfile() {
  final done = Completer<String?>();
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  input.addEventListener('cancel', (_) {
    if (!done.isCompleted) done.complete(null);
  });
  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      done.complete(null);
      return;
    }
    if (files.single.size > 100000) {
      done.completeError(FormatException('Calibration profile too large'));
      return;
    }
    final reader = html.FileReader();
    reader.onLoad.first.then((_) => done.complete(reader.result as String));
    reader.onError.first.then(
      (_) => done.completeError(StateError('Profile could not be read')),
    );
    reader.readAsText(files.single);
  });
  input.click();
  return done.future;
}
