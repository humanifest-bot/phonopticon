// Browser-local download only. No upload or external service.
import 'dart:html' as html;

Future<String> saveBundle(String json, String trialId) async {
  final blob = html.Blob([json], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final link = html.AnchorElement(href: url)..download = '$trialId.json';
  link.click();
  // Allow browsers to consume the URL before revoking the temporary handle.
  Future<void>.delayed(
    const Duration(seconds: 5),
    () => html.Url.revokeObjectUrl(url),
  );
  return 'Download requested: $trialId.json';
}
