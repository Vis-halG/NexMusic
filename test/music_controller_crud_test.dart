import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/music_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local preview media CRUD keeps controller state consistent', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = MusicController(preferences);
    addTearDown(controller.dispose);

    final sourceFolder = await controller.createMediaFolder('Clips');
    expect(sourceFolder, isNotNull);
    expect(
      controller.mediaFolders.map((folder) => folder.name),
      contains('Clips'),
    );

    final created = await controller.saveSharedLink(
      url: 'https://example.com/video',
      title: 'Demo clip',
      folderId: sourceFolder!.id,
    );
    expect(created, isTrue);
    expect(controller.savedMedia, hasLength(1));
    expect(controller.savedMedia.single.title, 'Demo clip');

    final targetFolder = await controller.createMediaFolder('Archive');
    expect(targetFolder, isNotNull);

    final updated = await controller.updateMedia(
      controller.savedMedia.single,
      title: 'Renamed clip',
      folderId: targetFolder!.id,
      sourceUrl: 'https://example.com/new-video',
    );
    expect(updated, isTrue);
    expect(controller.savedMedia.single.title, 'Renamed clip');
    expect(controller.savedMedia.single.folderId, targetFolder.id);
    expect(
      controller.savedMedia.single.sourceUrl,
      'https://example.com/new-video',
    );

    final deleted = await controller.deleteMedia(controller.savedMedia.single);
    expect(deleted, isTrue);
    expect(controller.savedMedia, isEmpty);

    final folderDeleted = await controller.deleteMediaFolder(sourceFolder);
    expect(folderDeleted, isTrue);
    expect(
      controller.mediaFolders.map((folder) => folder.id),
      isNot(contains(sourceFolder.id)),
    );
  });

  test('local preview CRUD rejects invalid media input', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = MusicController(preferences);
    addTearDown(controller.dispose);

    final invalidLink = await controller.saveSharedLink(
      url: 'not-a-url',
      title: 'Invalid clip',
      folderId: controller.mediaFolders.first.id,
    );
    expect(invalidLink, isFalse);
    expect(controller.savedMedia, isEmpty);

    final tooLongTitle = await controller.saveSharedLink(
      url: 'https://example.com/video',
      title: 'x' * 161,
      folderId: controller.mediaFolders.first.id,
    );
    expect(tooLongTitle, isFalse);
    expect(controller.savedMedia, isEmpty);
  });
}
