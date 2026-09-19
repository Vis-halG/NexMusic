import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/app_update.dart';

void main() {
  test('live GitHub update check', () async {
    final service = AppUpdateService();
    // Simulate being on earlier version 0.2.0+4002:
    final update = await service.checkForUpdate(currentVersion: '0.2.0+4002');
    print('Update detected: ${update?.displayVersion}');
    print('Download URL: ${update?.downloadUrl}');
    print('Size: ${update?.formattedSize}');
    expect(update, isNotNull);
    expect(update!.versionName, '0.2.1');
    expect(update.buildNumber, 4003);
    expect(update.downloadUrl, endsWith('.apk'));
  });
}
