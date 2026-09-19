import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/app_update.dart';

void main() {
  group('AppUpdateService version parsing and comparison', () {
    test('parses version with build number', () {
      final v1 = AppUpdateService.parseVersion('0.2.0+4002');
      expect(v1.name, '0.2.0');
      expect(v1.build, 4002);

      final v2 = AppUpdateService.parseVersion('v1.0.5+5001');
      expect(v2.name, '1.0.5');
      expect(v2.build, 5001);

      final v3 = AppUpdateService.parseVersion('2.1.0');
      expect(v3.name, '2.1.0');
      expect(v3.build, 0);
    });

    test('correctly identifies newer build numbers', () {
      expect(
        AppUpdateService.isNewerVersion('0.2.0+4003', '0.2.0+4002'),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerVersion('0.2.0+4002', '0.2.0+4002'),
        isFalse,
      );
      expect(
        AppUpdateService.isNewerVersion('0.2.0+4001', '0.2.0+4002'),
        isFalse,
      );
    });

    test('correctly identifies newer semantic versions', () {
      expect(
        AppUpdateService.isNewerVersion('0.2.1', '0.2.0'),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerVersion('0.3.0', '0.2.9'),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerVersion('1.0.0', '0.9.9'),
        isTrue,
      );
      expect(
        AppUpdateService.isNewerVersion('0.2.0', '0.2.0'),
        isFalse,
      );
      expect(
        AppUpdateService.isNewerVersion('0.1.9', '0.2.0'),
        isFalse,
      );
    });

    test('formatted size displays megabytes', () {
      const info = AppUpdateInfo(
        tagName: 'v0.2.1+4003',
        versionName: '0.2.1',
        buildNumber: 4003,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: 'Some notes',
        sizeBytes: 15 * 1024 * 1024,
      );
      expect(info.formattedSize, '15.0 MB');
      expect(info.displayVersion, 'v0.2.1 (build 4003)');
    });
  });
}
