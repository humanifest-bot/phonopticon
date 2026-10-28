import 'dart:io';

Future<String> saveBundle(String json, String trialId) async {
  final dir = await Directory.systemTemp.createTemp('phonopticon-');
  final file = File('${dir.path}/$trialId.json');
  await file.writeAsString(json, flush: true);
  return file.path;
}
