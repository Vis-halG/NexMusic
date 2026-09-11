import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_data.dart';

/// Playback, preferences and Firebase access stay in one controller so the
/// project remains deliberately compact.
class MusicController extends ChangeNotifier {
  MusicController(
    SharedPreferences preferences, {
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : this._withFirebase(preferences, auth, firestore, storage);

  MusicController._withFirebase(
    this._prefs,
    this._auth,
    this._firestore,
    this._storage,
  ) {
    guestMode = _prefs.getBool('guestMode') ?? false;
    signedIn = _auth?.currentUser != null || guestMode;
    darkMode = _prefs.getBool('darkMode') ?? false;
    browserPillOne = _prefs.getString('browserPillOne');
    browserPillTwo = _prefs.getString('browserPillTwo');
    liked.addAll(_prefs.getStringList('liked') ?? const []);
    recentTrackIds.addAll(
      (_prefs.getStringList('recentTrackIds') ?? const []).where(
        (id) => tracks.any((track) => track.id == id),
      ),
    );
    try {
      final saved = jsonDecode(_prefs.getString('offlineMedia') ?? '{}');
      if (saved is Map) {
        offlinePaths.addAll(
          saved.map((key, value) => MapEntry('$key', '$value')),
        );
      }
    } catch (_) {
      _prefs.remove('offlineMedia');
    }
    _subs.add(
      _audio.playerStateStream.listen((state) {
        playing = state.playing;
        loading =
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        notifyListeners();
        if (state.processingState == ProcessingState.completed) next();
      }),
    );
    _subs.add(
      _audio.positionStream.listen((value) {
        position = value;
        // Playback position is a high-frequency signal. Sending it through
        // the controller's global ChangeNotifier rebuilt the app shell,
        // every song tile and even the offstage tabs several times a second.
        // Player widgets listen to this narrow channel instead.
        positionListenable.value = value;
      }),
    );
    _subs.add(
      _audio.durationStream.listen((value) {
        if (value != null) duration = value;
        notifyListeners();
      }),
    );
    if (_auth != null) {
      _subs.add(
        _auth.authStateChanges().listen((user) {
          signedIn = user != null || guestMode;
          if (user != null) unawaited(loadCloudLibrary());
          notifyListeners();
        }),
      );
      if (_auth.currentUser != null) unawaited(loadCloudLibrary());
    }
  }

  final SharedPreferences _prefs;
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final AudioPlayer _audio = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  final ValueNotifier<Duration> positionListenable = ValueNotifier(
    Duration.zero,
  );
  final Set<String> liked = {};
  final List<String> recentTrackIds = [];
  final Map<String, String> offlinePaths = {};
  List<Track> queue = tracks;
  List<MediaFolder> mediaFolders = const [
    MediaFolder(id: 'local-imports', name: 'My Imports'),
  ];
  List<SavedMedia> savedMedia = const [];
  Track? current;
  Duration position = Duration.zero, duration = Duration.zero;
  bool signedIn = false,
      guestMode = false,
      darkMode = false,
      playing = false,
      loading = false,
      shuffle = false,
      repeat = false;
  String? notice;
  String? browserPillOne, browserPillTwo;

  bool get backendConfigured =>
      _auth != null && _firestore != null && _storage != null;
  String get profileName {
    final name = _auth?.currentUser?.displayName?.trim();
    return name == null || name.isEmpty ? 'Guest listener' : name;
  }

  String get profileEmail {
    final email = _auth?.currentUser?.email?.trim();
    return email == null || email.isEmpty ? 'Local preview mode' : email;
  }

  String get profileInitials {
    final words = profileName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }

  List<Track> get likedTracks =>
      tracks.where((track) => liked.contains(track.id)).toList();
  List<Track> get recentTracks => recentTrackIds.map(trackById).toList();
  bool isLiked(Track track) => liked.contains(track.id);
  bool isDownloaded(SavedMedia item) => offlinePaths.containsKey(item.id);

  Future<void> googlePreviewLogin() async {
    if (_auth == null) return;
    loading = true;
    notice = null;
    notifyListeners();
    try {
      if (kIsWeb) {
        guestMode = false;
        await _prefs.setBool('guestMode', false);
        await _auth.signInWithRedirect(GoogleAuthProvider());
        return;
      } else {
        final googleUser = await GoogleSignIn.instance.authenticate();
        final googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        await _auth.signInWithCredential(credential);
      }
      guestMode = false;
      await _prefs.setBool('guestMode', false);
    } on FirebaseAuthException catch (error) {
      notice = _googleLoginMessage(error);
    } catch (error) {
      notice = 'Google login failed: $error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> guestLogin() async {
    guestMode = true;
    signedIn = true;
    await _prefs.setBool('guestMode', true);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _audio.stop();
    if (_auth?.currentUser != null) {
      if (!kIsWeb) await GoogleSignIn.instance.signOut();
      await _auth!.signOut();
    }
    guestMode = false;
    signedIn = false;
    current = null;
    mediaFolders = const [MediaFolder(id: 'local-imports', name: 'My Imports')];
    savedMedia = const [];
    await _prefs.setBool('guestMode', false);
    notifyListeners();
  }

  Future<void> play(Track track, {List<Track>? from}) async {
    current = track;
    recentTrackIds
      ..remove(track.id)
      ..insert(0, track.id);
    if (recentTrackIds.length > 12) {
      recentTrackIds.removeRange(12, recentTrackIds.length);
    }
    await _prefs.setStringList('recentTrackIds', recentTrackIds);
    queue = from == null || from.isEmpty ? tracks : List.of(from);
    position = Duration.zero;
    positionListenable.value = Duration.zero;
    duration = track.duration;
    loading = true;
    notice = null;
    notifyListeners();
    try {
      await _audio.setUrl(track.url);
      await _audio.play();
    } catch (_) {
      loading = false;
      notice = 'Audio load nahi hua. Internet connection check karein.';
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (current == null) return play(tracks.first);
    return _audio.playing ? _audio.pause() : _audio.play();
  }

  Future<void> seek(Duration value) => _audio.seek(value);

  Future<void> next() async {
    if (current == null || queue.isEmpty) return;
    var index = queue.indexWhere((track) => track.id == current!.id);
    index = shuffle
        ? DateTime.now().millisecondsSinceEpoch % queue.length
        : (index + 1) % queue.length;
    await play(queue[index], from: queue);
  }

  Future<void> previous() async {
    if (current == null || queue.isEmpty) return;
    if (position > const Duration(seconds: 4)) return seek(Duration.zero);
    var index = queue.indexWhere((track) => track.id == current!.id) - 1;
    if (index < 0) index = queue.length - 1;
    await play(queue[index], from: queue);
  }

  void toggleLike(Track track) {
    if (!liked.add(track.id)) liked.remove(track.id);
    _prefs.setStringList('liked', liked.toList());
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    repeat = !repeat;
    await _audio.setLoopMode(repeat ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  void setDarkMode(bool value) {
    darkMode = value;
    _prefs.setBool('darkMode', value);
    notifyListeners();
  }

  void setBrowserPillText(int slot, String value) {
    if (slot == 1) {
      browserPillOne = value;
      _prefs.setString('browserPillOne', value);
    } else if (slot == 2) {
      browserPillTwo = value;
      _prefs.setString('browserPillTwo', value);
    }
  }

  CollectionReference<Map<String, dynamic>> _userCollection(String name) {
    final uid = _auth!.currentUser!.uid;
    return _firestore!.collection('users').doc(uid).collection(name);
  }

  Future<void> loadCloudLibrary() async {
    if (_auth?.currentUser == null || _firestore == null) return;
    try {
      final folderSnapshot = await _userCollection(
        'folders',
      ).orderBy('createdAt').get();
      final mediaSnapshot = await _userCollection(
        'media',
      ).orderBy('createdAt', descending: true).get();
      if (folderSnapshot.docs.isEmpty) {
        final reference = await _userCollection('folders').add({
          'name': 'My Imports',
          'createdAt': FieldValue.serverTimestamp(),
        });
        mediaFolders = [MediaFolder(id: reference.id, name: 'My Imports')];
      } else {
        mediaFolders = folderSnapshot.docs
            .map(
              (doc) => MediaFolder(
                id: doc.id,
                name: doc.data()['name'] as String? ?? 'Untitled',
              ),
            )
            .toList();
      }
      savedMedia = mediaSnapshot.docs.map((doc) {
        final row = doc.data();
        return SavedMedia(
          id: doc.id,
          title: row['title'] as String? ?? 'Untitled',
          kind: row['kind'] as String? ?? 'link',
          folderId: row['folderId'] as String? ?? '',
          sourceUrl: row['sourceUrl'] as String?,
          storagePath: row['storagePath'] as String?,
        );
      }).toList();
      notifyListeners();
    } catch (error) {
      notice = 'Firebase library load nahi hui: $error';
      notifyListeners();
    }
  }

  Future<MediaFolder?> createMediaFolder(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return null;
    if (cleanName.length > 80) {
      notice = 'Folder name 80 characters ya usse kam hona chahiye.';
      notifyListeners();
      return null;
    }
    if (_auth?.currentUser == null || _firestore == null) {
      final folder = MediaFolder(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        name: cleanName,
      );
      mediaFolders = [...mediaFolders, folder];
      notifyListeners();
      return folder;
    }
    try {
      final reference = await _userCollection(
        'folders',
      ).add({'name': cleanName, 'createdAt': FieldValue.serverTimestamp()});
      final folder = MediaFolder(id: reference.id, name: cleanName);
      mediaFolders = [...mediaFolders, folder];
      notifyListeners();
      return folder;
    } on FirebaseException catch (error) {
      notice = _firebaseMessage(error, operation: 'Folder save');
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateMediaFolder(MediaFolder folder, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return false;
    if (cleanName.length > 80) {
      notice = 'Folder name 80 characters ya usse kam hona chahiye.';
      notifyListeners();
      return false;
    }
    try {
      if (_auth?.currentUser != null && _firestore != null) {
        await _userCollection(
          'folders',
        ).doc(folder.id).update({'name': cleanName});
      }
      mediaFolders = mediaFolders
          .map(
            (item) =>
                item.id == folder.id ? item.copyWith(name: cleanName) : item,
          )
          .toList();
      notice = 'Folder update ho gaya.';
      notifyListeners();
      return true;
    } on FirebaseException catch (error) {
      notice = _firebaseMessage(error, operation: 'Folder update');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMediaFolder(MediaFolder folder) async {
    if (mediaFolders.length <= 1) {
      notice = 'Last folder delete nahi ho sakta.';
      notifyListeners();
      return false;
    }
    if (savedMedia.any((item) => item.folderId == folder.id)) {
      notice =
          'Folder empty nahi hai. Pehle saved items move ya delete karein.';
      notifyListeners();
      return false;
    }
    try {
      if (_auth?.currentUser != null && _firestore != null) {
        await _userCollection('folders').doc(folder.id).delete();
      }
      mediaFolders = mediaFolders
          .where((item) => item.id != folder.id)
          .toList();
      notice = 'Folder delete ho gaya.';
      notifyListeners();
      return true;
    } on FirebaseException catch (error) {
      notice = _firebaseMessage(error, operation: 'Folder delete');
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveSharedLink({
    required String url,
    required String title,
    required String folderId,
  }) async {
    final cleanUrl = url.trim();
    final cleanTitle = title.trim().isEmpty ? 'Shared video' : title.trim();
    final cleanFolderId = folderId.trim();
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      notice = 'Valid web link enter karein.';
      notifyListeners();
      return false;
    }
    if (!_validMediaInput(title: cleanTitle, folderId: cleanFolderId)) {
      notifyListeners();
      return false;
    }
    if (_auth?.currentUser == null || _firestore == null) {
      notice =
          'Link local preview me hai. Cloud save ke liye Google login karein.';
      savedMedia = [
        SavedMedia(
          id: 'local-${DateTime.now().millisecondsSinceEpoch}',
          title: cleanTitle,
          kind: 'link',
          folderId: cleanFolderId,
          sourceUrl: cleanUrl,
        ),
        ...savedMedia,
      ];
      notifyListeners();
      return true;
    }
    try {
      final reference = await _userCollection('media').add({
        'title': cleanTitle,
        'kind': 'link',
        'folderId': cleanFolderId,
        'sourceUrl': cleanUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
      savedMedia = [
        SavedMedia(
          id: reference.id,
          title: cleanTitle,
          kind: 'link',
          folderId: cleanFolderId,
          sourceUrl: cleanUrl,
        ),
        ...savedMedia,
      ];
      notice = 'Link Firebase me save ho gaya.';
      notifyListeners();
      return true;
    } catch (error) {
      notice = 'Link save nahi hua: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateMedia(
    SavedMedia item, {
    required String title,
    required String folderId,
    String? sourceUrl,
  }) async {
    final cleanTitle = title.trim();
    final cleanFolderId = folderId.trim();
    final cleanUrl = sourceUrl?.trim();
    if (!_validMediaInput(title: cleanTitle, folderId: cleanFolderId)) {
      notifyListeners();
      return false;
    }
    if (item.kind == 'link') {
      final uri = Uri.tryParse(cleanUrl ?? '');
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        notice = 'Valid web link enter karein.';
        notifyListeners();
        return false;
      }
    }

    try {
      if (_auth?.currentUser != null && _firestore != null) {
        final update = <String, dynamic>{
          'title': cleanTitle,
          'folderId': cleanFolderId,
        };
        if (item.kind == 'link') update['sourceUrl'] = cleanUrl;
        await _userCollection('media').doc(item.id).update(update);
      }
      savedMedia = savedMedia
          .map(
            (media) => media.id == item.id
                ? media.copyWith(
                    title: cleanTitle,
                    folderId: cleanFolderId,
                    sourceUrl: item.kind == 'link' ? cleanUrl : null,
                  )
                : media,
          )
          .toList();
      notice = 'Item update ho gaya.';
      notifyListeners();
      return true;
    } on FirebaseException catch (error) {
      notice = _firebaseMessage(error, operation: 'Update');
      notifyListeners();
      return false;
    } catch (error) {
      notice = 'Update failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadOwnedAudio({
    required String filePath,
    required String title,
    required String folderId,
  }) async {
    return uploadOwnedMedia(
      filePath: filePath,
      title: title,
      folderId: folderId,
      kind: 'audio',
      contentType: _contentTypeFor(filePath, kind: 'audio'),
    );
  }

  Future<bool> uploadOwnedMedia({
    required String filePath,
    required String title,
    required String folderId,
    required String kind,
    required String contentType,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'Imported media' : title.trim();
    final cleanFolderId = folderId.trim();
    if (!_validMediaInput(title: cleanTitle, folderId: cleanFolderId)) {
      notifyListeners();
      return false;
    }
    if (kind != 'audio' && kind != 'video') {
      notice = 'Unsupported media type.';
      notifyListeners();
      return false;
    }
    if (_auth?.currentUser == null || _firestore == null || _storage == null) {
      notice = 'Media upload ke liye Google login zaroori hai.';
      notifyListeners();
      return false;
    }
    Reference? uploadedReference;
    try {
      final uid = _auth!.currentUser!.uid;
      final sourceFile = filePath.startsWith('file:')
          ? File.fromUri(Uri.parse(filePath))
          : File(filePath);
      if (!await sourceFile.exists()) {
        throw const FileSystemException('Selected media file is unavailable.');
      }
      final fileSize = await sourceFile.length();
      if (fileSize == 0) {
        throw const FileSystemException('Selected media file is empty.');
      }
      if (fileSize >= 100 * 1024 * 1024) {
        throw const FileSystemException(
          'File is larger than the 100 MB upload limit.',
        );
      }
      final sourceExtension = path.extension(sourceFile.path).toLowerCase();
      final extension = sourceExtension.isEmpty
          ? (kind == 'video' ? '.mp4' : '.m4a')
          : sourceExtension;
      final objectPath =
          'users/$uid/$cleanFolderId/${DateTime.now().millisecondsSinceEpoch}$extension';
      uploadedReference = _storage.ref(objectPath);
      await uploadedReference.putFile(
        sourceFile,
        SettableMetadata(
          contentType: _contentTypeFor(
            sourceFile.path,
            kind: kind,
            fallback: contentType,
          ),
          customMetadata: {'ownerUid': uid, 'folderId': cleanFolderId},
        ),
      );

      DocumentReference<Map<String, dynamic>> reference;
      try {
        reference = await _userCollection('media').add({
          'title': cleanTitle,
          'kind': kind,
          'folderId': cleanFolderId,
          'storagePath': objectPath,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (error, stackTrace) {
        // Do not leave an inaccessible, billed Storage object behind when the
        // matching Firestore metadata write is rejected or interrupted.
        try {
          await uploadedReference.delete();
        } catch (_) {}
        Error.throwWithStackTrace(error, stackTrace);
      }
      savedMedia = [
        SavedMedia(
          id: reference.id,
          title: cleanTitle,
          kind: kind,
          folderId: cleanFolderId,
          storagePath: objectPath,
        ),
        ...savedMedia,
      ];
      notice =
          '${kind == 'video' ? 'Video' : 'Audio'} Firebase Storage me save ho gaya.';
      notifyListeners();
      return true;
    } on FirebaseException catch (error) {
      notice = _firebaseMessage(error, operation: 'Upload');
      notifyListeners();
      return false;
    } on FileSystemException catch (error) {
      notice = 'Upload failed: ${error.message}';
      notifyListeners();
      return false;
    } catch (error) {
      notice = 'Upload failed. Please try again. ($error)';
      notifyListeners();
      return false;
    }
  }

  Future<bool> downloadMedia(SavedMedia item) async {
    if (kIsWeb) {
      notice = 'Offline app download Android/iOS build me available hai.';
      notifyListeners();
      return false;
    }
    if (_storage == null || item.storagePath == null) {
      notice = 'Is item ke saath downloadable cloud file nahi hai.';
      notifyListeners();
      return false;
    }
    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(path.join(documents.path, 'offline_media'));
      await directory.create(recursive: true);
      final cloudExtension = path.extension(item.storagePath!);
      final extension = cloudExtension.isEmpty
          ? (item.kind == 'video' ? '.mp4' : '.m4a')
          : cloudExtension;
      final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '');
      final localFile = File(
        path.join(
          directory.path,
          '${safeTitle.isEmpty ? 'media' : safeTitle}-${item.id}$extension',
        ),
      );
      await _storage.ref(item.storagePath!).writeToFile(localFile);
      offlinePaths[item.id] = localFile.path;
      await _saveOfflinePaths();
      notice = 'Offline download nexMusic ke andar save ho gaya.';
      notifyListeners();
      return true;
    } catch (error) {
      notice = 'Download failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> removeDownload(SavedMedia item) async {
    final localPath = offlinePaths.remove(item.id);
    if (!kIsWeb && localPath != null) {
      final file = File(localPath);
      if (await file.exists()) await file.delete();
    }
    await _saveOfflinePaths();
    notice = 'Offline copy remove ho gayi.';
    notifyListeners();
  }

  Future<bool> deleteMedia(SavedMedia item) async {
    try {
      if (_auth?.currentUser != null && _firestore != null) {
        if (item.storagePath != null && _storage != null) {
          try {
            await _storage.ref(item.storagePath!).delete();
          } on FirebaseException catch (error) {
            if (error.code != 'object-not-found') rethrow;
          }
        }
        await _userCollection('media').doc(item.id).delete();
      }
      await removeDownload(item);
      savedMedia = savedMedia.where((media) => media.id != item.id).toList();
      notice = 'Item permanently delete ho gaya.';
      notifyListeners();
      return true;
    } catch (error) {
      notice = 'Delete failed: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> _saveOfflinePaths() =>
      _prefs.setString('offlineMedia', jsonEncode(offlinePaths));

  bool _validMediaInput({required String title, required String folderId}) {
    if (title.isEmpty) {
      notice = 'Title empty nahi ho sakta.';
      return false;
    }
    if (title.length > 160) {
      notice = 'Title 160 characters ya usse kam hona chahiye.';
      return false;
    }
    if (folderId.isEmpty) {
      notice = 'Folder select karein.';
      return false;
    }
    return true;
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  static String _contentTypeFor(
    String filePath, {
    required String kind,
    String? fallback,
  }) {
    return switch (path.extension(filePath).toLowerCase()) {
      '.mp3' => 'audio/mpeg',
      '.aac' => 'audio/aac',
      '.m4a' => 'audio/mp4',
      '.mov' => 'video/quicktime',
      '.mp4' => kind == 'video' ? 'video/mp4' : 'audio/mp4',
      _ => fallback ?? (kind == 'video' ? 'video/mp4' : 'audio/mp4'),
    };
  }

  static String _firebaseMessage(
    FirebaseException error, {
    required String operation,
  }) {
    return switch (error.code) {
      'object-not-found' =>
        '$operation failed: Firebase Storage bucket is not set up for this project. The project owner must enable Blaze billing and create the default Storage bucket.',
      'unauthorized' || 'permission-denied' =>
        '$operation failed: your account is not allowed to write this file.',
      'unauthenticated' =>
        '$operation failed: please sign in with Google again.',
      'quota-exceeded' =>
        '$operation failed: Firebase Storage quota or billing limit was reached.',
      'canceled' => '$operation cancelled.',
      'retry-limit-exceeded' || 'unavailable' =>
        '$operation failed because Firebase is temporarily unreachable. Check the connection and retry.',
      _ => '$operation failed: ${error.message ?? error.code}',
    };
  }

  static String _googleLoginMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'unauthorized-domain' =>
        'Google login blocked: add this domain in Firebase Auth authorized domains. Use localhost for local testing.',
      'operation-not-allowed' =>
        'Google login provider disabled hai. Firebase Authentication me Google sign-in enable karein.',
      'popup-blocked' =>
        'Google popup block ho gaya. Browser popup allow karke dobara try karein.',
      'popup-closed-by-user' =>
        'Google login complete hone se pehle close ho gaya.',
      'network-request-failed' =>
        'Google login network issue ki wajah se fail hua. Internet check karke try karein.',
      _ => error.message ?? 'Google login failed (${error.code}).',
    };
  }

  @override
  void dispose() {
    for (final subscription in _subs) {
      subscription.cancel();
    }
    _audio.dispose();
    positionListenable.dispose();
    super.dispose();
  }
}
