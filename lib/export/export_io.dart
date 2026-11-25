import 'dart:io';
import 'package:flutter/services.dart';

const _exportChannel = MethodChannel('com.humanifest.phonopticon/export');

String mobileExportMessage(Map<Object?, Object?>? result, String trialId) {
  final status = result?['status']?.toString();
  final detail = result?['detail']?.toString();
  if (status == 'shared')
    return 'Shared via selected destination: $trialId.json';
  if (status == 'saved') return 'Saved to selected destination: $trialId.json';
  if (status == 'cancelled') return 'Share cancelled: $trialId.json';
  if (status == 'error') {
    throw StateError(
      detail?.isNotEmpty == true ? detail! : 'Mobile export failed',
    );
  }
  throw StateError('Mobile export returned no result');
}

Future<String> saveBundle(String json, String trialId) async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final result = await _exportChannel.invokeMethod<Map<Object?, Object?>>(
        'shareBundle',
        {'json': json, 'filename': '$trialId.json'},
      );
      return mobileExportMessage(result, trialId);
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }
  final dir = await Directory.systemTemp.createTemp('phonopticon-');
  final file = File('${dir.path}/$trialId.json');
  await file.writeAsString(json, flush: true);
  return 'Temporary file written: ${file.path}';
}
