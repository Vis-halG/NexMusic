import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nex_app/main.dart';
import 'package:nex_app/movie_provider.dart';
import 'package:nex_app/movie_ui.dart';
import 'package:nex_app/music_controller.dart';
import 'music_discovery_test.dart' show FakeMusicProvider, track;

Map<String, dynamic> title(String id) => {
  'subjectId': id,
  'subjectType': 1,
  'title': 'Movie $id',
  'detailPath': 'movie-$id',
};

void main() {
  testWidgets(
    'Movies appears before Profile and Stream combines both catalogues',
    (tester) async {
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
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['Home', 'Stream', 'Library', 'Movies', 'Profile'],
      );
      await tester.tap(find.text('Stream'));
      await tester.pumpAndSettle();
      expect(find.text('Saavn pick'), findsWidgets);
      expect(find.text('YouTube pick'), findsWidgets);
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(find.text('YouTube video'), findsOneWidget);
      expect(find.text('Saavn pick'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('movie searches ignore stale responses after a newer query', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final provider = MovieBoxProvider(
      fetch: (_, body) async {
        if (body == null)
          return {
            'code': 0,
            'data': {
              'operatingList': [
                {
                  'title': 'Trending now',
                  'subjects': [title('home')],
                },
              ],
            },
          };
        if (body['keyword'] == 'old') return pending.future;
        return {
          'code': 0,
          'data': {
            'items': [title('new')],
          },
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: NexApp.theme(Brightness.light),
        home: Scaffold(body: MoviesScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Movie home'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    pending.complete({
      'code': 0,
      'data': {
        'items': [title('old')],
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('Movie new'), findsOneWidget);
    expect(find.text('Movie old'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('movie source failure offers a working retry', (tester) async {
    var failed = true;
    final provider = MovieBoxProvider(
      fetch: (_, _) async {
        if (failed) throw StateError('offline');
        return {
          'code': 0,
          'data': {
            'operatingList': [
              {
                'title': 'Trending now',
                'subjects': [title('recovered')],
              },
            ],
          },
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MoviesScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Movie recovered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
