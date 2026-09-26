// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_app/app_update.dart';

void main() {
  test('live GitHub update check', () async {
    final service = AppUpdateService();
    // Simulate being on earlier version 0.2.0+4002:
    final update = await service.checkForUpdate(currentVersion: '0.2.0+4002');
    print('Update detected: ${update?.displayVersion}');
    print('Download URL: ${update?.downloadUrl}');
    print('Size: ${update?.formattedSize}');
    expect(update, isNotNull);
    expect(update!.versionName.isNotEmpty, isTrue);
    expect(update.buildNumber, greaterThan(4002));
    expect(update.downloadUrl, endsWith('.apk'));
  });

  test('isNewerVersion logic', () {
    expect(AppUpdateService.isNewerVersion('0.2.9+4013', '0.2.9+4013'), isFalse);
    expect(AppUpdateService.isNewerVersion('0.2.9+4013', '0.2.9+4011'), isTrue);
    expect(AppUpdateService.isNewerVersion('0.2.9+4011', '0.2.9+4013'), isFalse);
    expect(AppUpdateService.isNewerVersion('0.3.0', '0.2.9+4013'), isTrue);
  });
}
