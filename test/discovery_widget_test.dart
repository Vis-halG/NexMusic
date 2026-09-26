import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nex_app/main.dart';
import 'package:nex_app/music_controller.dart';
import 'music_discovery_test.dart' show FakeMusicProvider, track;

void main() {
  testWidgets('four tabs remain and Stream combines both catalogues', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final controller = MusicController(
      await SharedPreferences.getInstance(),
      musicProviders: [
        FakeMusicProvider('jiosaavn', [track('jiosaavn', 'Saavn pick')]),
        FakeMusicProvider('ytmusic', [track('ytmusic', 'YouTube pick')]),
        FakeMusicProvider('ytvideo', [
          track('ytvideo', 'YouTube video', kind: 'video'),
        ]),
      ],
    )..signedIn = true;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: controller, child: const NexApp()),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label),
      ['Home', 'Stream', 'Library', 'Profile'],
    );
    await tester.tap(find.text('Never Played').first);
    await tester.pumpAndSettle();
    expect(find.text('Saavn pick'), findsWidgets);
    expect(find.text('YouTube pick'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stream'));
    await tester.pumpAndSettle();
    expect(find.text('Saavn pick'), findsWidgets);
    expect(find.text('YouTube pick'), findsWidgets);
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.text('YouTube video'), findsOneWidget);
    expect(find.text('Saavn pick'), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
