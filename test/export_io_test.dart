import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/export/export_io.dart';

void main() {
  const trialId = 'trial-123';

  test('saved export reports the user-selected destination', () {
    expect(
      mobileExportMessage({'status': 'saved'}, trialId),
      'Saved to selected destination: $trialId.json',
    );
  });

  test('completed share names the user-selected destination contract', () {
    expect(
      mobileExportMessage({'status': 'shared'}, trialId),
      'Shared via selected destination: $trialId.json',
    );
  });

  test('cancelled export remains distinct from saved or shared', () {
    expect(
      mobileExportMessage({'status': 'cancelled'}, trialId),
      'Share cancelled: $trialId.json',
    );
  });

  test('native export errors, including activity recreation, are surfaced', () {
    expect(
      () => mobileExportMessage({
        'status': 'error',
        'detail': 'Export interrupted because the app activity was recreated.',
      }, trialId),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('activity was recreated'),
        ),
      ),
    );
  });

  test('unknown or missing native status is not treated as success', () {
    expect(
      () => mobileExportMessage({'status': 'unknown'}, trialId),
      throwsA(isA<StateError>()),
    );
    expect(
      () => mobileExportMessage(null, trialId),
      throwsA(isA<StateError>()),
    );
  });
}
