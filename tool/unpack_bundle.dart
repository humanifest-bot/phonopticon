import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart tool/unpack_bundle.dart BUNDLE.json NEW_DIRECTORY',
    );
    exitCode = 64;
    return;
  }
  final bundle =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  if (bundle['manifest']['schemaVersion'] != 1)
    throw FormatException('Unsupported schema');
  final files = bundle['files'] as Map<String, dynamic>;
  // Decode and validate all input before any writes. File names are fixed here.
  final tx = base64Decode(files['emitted.wav.base64'] as String);
  final rx = base64Decode(files['received.wav.base64'] as String);
  final metrics = files['metrics.csv'] as String;
  final movement = files['movement.svg'] as String;
  final spectrum = files['spectrum.svg'] as String;
  final manifest = const JsonEncoder.withIndent(
    '  ',
  ).convert(bundle['manifest']);
  final analysis = jsonEncode(bundle['analysis']);
  final dir = Directory(args[1]);
  if (dir.existsSync())
    throw StateError('Output directory already exists; no overwrites.');
  dir.createSync(recursive: true);
  File('${dir.path}/emitted.wav').writeAsBytesSync(tx);
  File('${dir.path}/received.wav').writeAsBytesSync(rx);
  File('${dir.path}/metrics.csv').writeAsStringSync(metrics);
  File('${dir.path}/movement.svg').writeAsStringSync(movement);
  File('${dir.path}/spectrum.svg').writeAsStringSync(spectrum);
  File('${dir.path}/manifest.json').writeAsStringSync(manifest);
  File('${dir.path}/analysis.json').writeAsStringSync(analysis);
  stdout.writeln('Unpacked local trial to ${dir.path}. No audio was played.');
}
