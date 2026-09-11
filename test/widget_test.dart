import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/main.dart';
import 'package:nex_music/music_controller.dart';
import 'package:nex_music/music_data.dart';
import 'package:nex_music/music_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the welcome experience on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = MusicController(preferences);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const NexMusicApp(),
      ),
    );
    await tester.pump();

    expect(find.text('nexMusic'), findsOneWidget);
    expect(find.text('Your sound.\nYour moment.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('now playing fits compact screens and queue opens safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = MusicController(preferences)
      ..current = tracks.first
      ..queue = tracks.take(4).toList()
      ..duration = const Duration(minutes: 5, seconds: 44);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const NowPlayingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Up next'), findsOneWidget);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.text('Up next'))).pop();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('primary app tabs render on a compact phone', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'guestMode': true});
    final preferences = await SharedPreferences.getInstance();
    final controller = MusicController(preferences);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const NexMusicApp(),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = [
      (Icons.search_outlined, 'Discover'),
      (Icons.library_music_outlined, 'Library'),
      (Icons.person_outline_rounded, 'You'),
      (Icons.home_outlined, 'Home'),
    ];
    for (final (icon, label) in tabs) {
      await tester.tap(find.byIcon(icon).last);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$label tab should render',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
