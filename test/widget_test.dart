import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/main.dart';
import 'package:nex_music/music_controller.dart';
import 'package:nex_music/music_data.dart';
import 'package:nex_music/music_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _categories = [
  MusicCategory(id: 'bolly', name: 'Bollywood', ownerUid: 'u1'),
  MusicCategory(id: 'lofi', name: 'Lo-fi', ownerUid: 'u2'),
];

const _songs = [
  Song(
    id: 's1',
    title: 'Tum Hi Ho',
    kind: 'audio',
    url: 'https://example.com/1.mp3',
    categoryId: 'bolly',
    ownerUid: 'u1',
    ownerName: 'Vishal',
  ),
  Song(
    id: 's2',
    title: 'Kesariya',
    kind: 'video',
    url: 'https://example.com/2.mp4',
    categoryId: 'bolly',
    ownerUid: 'u2',
    ownerName: 'Aman',
  ),
  Song(
    id: 's3',
    title: 'Lofi Rain',
    kind: 'audio',
    url: 'https://example.com/3.mp3',
    categoryId: 'lofi',
    ownerUid: 'u2',
    ownerName: 'Riya',
  ),
];

Future<MusicController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  return MusicController(await SharedPreferences.getInstance());
}

Widget _app(MusicController controller, {Widget? home}) =>
    ChangeNotifierProvider.value(
      value: controller,
      child: home == null
          ? const NexMusicApp()
          : MaterialApp(
              theme: NexMusicApp.theme(Brightness.light),
              home: home,
            ),
    );

void _usePhone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the sign-in screen when signed out', (tester) async {
    final controller = await _controller();

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text('nexMusic'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('home lists every upload and filters by category', (
    tester,
  ) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories
      ..songs = _songs;

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Tum Hi Ho'), findsOneWidget);
    expect(find.text('Kesariya'), findsOneWidget);
    expect(find.text('Lofi Rain'), findsOneWidget);

    // The category pill comes before the song subtitles that repeat its name.
    await tester.tap(find.text('Lo-fi').first);
    await tester.pumpAndSettle();
    expect(find.text('Lofi Rain'), findsOneWidget);
    expect(find.text('Tum Hi Ho'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Tum Hi Ho'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('anyone can edit or delete an upload from its menu', (
    tester,
  ) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories
      ..songs = _songs;

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aman'), findsNothing);
    // "Kesariya" was uploaded by someone else.
    await tester.tap(find.byTooltip('More').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Edit or move'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('home shows upload progress while a batch runs', (tester) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories
      ..songs = _songs
      ..uploads = [
        UploadItem(path: 'a.mp3', name: 'a.mp3', sizeBytes: 1000, title: 'A')
          ..status = UploadStatus.done,
        UploadItem(path: 'b.mp3', name: 'b.mp3', sizeBytes: 1000, title: 'B')
          ..status = UploadStatus.uploading
          ..progress = 0.4,
      ];

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text('Uploading 1 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('now playing fits compact portrait and landscape screens', (
    tester,
  ) async {
    _usePhone(tester, const Size(1080, 1920));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories
      ..songs = _songs
      ..current = _songs.first
      ..queue = [_songs.first, _songs.last]
      ..duration = const Duration(minutes: 3, seconds: 20);

    await tester.pumpWidget(_app(controller, home: const NowPlayingScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Tum Hi Ho'), findsOneWidget);
    // Only the category is shown, never the uploader's name.
    expect(find.text('Bollywood'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('upload stays disabled until files and category are chosen', (
    tester,
  ) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories;

    await tester.pumpWidget(_app(controller, home: const UploadScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Choose songs or videos'), findsOneWidget);
    final upload = find.widgetWithText(FilledButton, 'Upload');
    expect(upload, findsOneWidget);
    expect(tester.widget<FilledButton>(upload).onPressed, isNull);

    // Category and rights alone are not enough without any files.
    await tester.tap(find.text('Lo-fi'));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(upload).onPressed, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('finished uploads list each file and offer a retry', (
    tester,
  ) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories
      ..uploads = [
        UploadItem(
            path: 'a.mp3',
            name: 'a.mp3',
            sizeBytes: 3000000,
            title: 'Song A',
          )
          ..status = UploadStatus.done
          ..progress = 1,
        UploadItem(
            path: 'b.mp3',
            name: 'b.mp3',
            sizeBytes: 3000000,
            title: 'Song B',
          )
          ..status = UploadStatus.skipped,
        UploadItem(
            path: 'c.mp3',
            name: 'c.mp3',
            sizeBytes: 3000000,
            title: 'Song C',
          )
          ..status = UploadStatus.failed
          ..error = 'Network error',
      ];

    await tester.pumpWidget(_app(controller, home: const UploadScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Upload finished'), findsOneWidget);
    expect(find.text('3 of 3 done'), findsOneWidget);
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Retry failed (1)'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('category manager lists categories with song counts', (
    tester,
  ) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories
      ..songs = _songs;

    await tester.pumpWidget(
      _app(controller, home: const CategoryManagerScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Bollywood'), findsOneWidget);
    // Nobody is signed in here, so every category belongs to someone else.
    expect(find.text('2 songs · created by someone else'), findsOneWidget);
    expect(find.text('1 song · created by someone else'), findsOneWidget);
    expect(find.byTooltip('Rename'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('upload screen links to category editing', (tester) async {
    _usePhone(tester, const Size(1080, 2340));
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories;

    await tester.pumpWidget(_app(controller, home: const UploadScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Lo-fi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a single audio upload offers trimming', (tester) async {
    _usePhone(tester, const Size(1080, 2340));
    final file = File('${Directory.systemTemp.path}/nexmusic_trim_test.mp3')
      ..writeAsBytesSync(List.filled(2048, 1));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final controller = await _controller()
      ..signedIn = true
      ..categories = _categories;

    await tester.pumpWidget(
      _app(controller, home: UploadScreen(initialPaths: [file.path])),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 file · 2 KB'), findsOneWidget);
    expect(find.text('Trim audio'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
