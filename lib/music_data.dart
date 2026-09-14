/// Prefix for ids of private library items wrapped in a [Song] for playback.
const privateSongPrefix = 'private-';

/// A shared category. Any signed-in user can create one; only its creator can
/// rename or delete it.
class MusicCategory {
  const MusicCategory({
    required this.id,
    required this.name,
    required this.ownerUid,
  });
  final String id, name, ownerUid;
}

/// A playable audio or video item.
///
/// Public uploads are stored on Cloudinary and listed in the shared `songs`
/// collection. Private library files are wrapped in a [Song] only while they
/// play.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.kind,
    required this.url,
    this.categoryId = '',
    this.ownerUid = '',
    this.ownerName = '',
    this.publicId,
    this.storagePath,
    this.sizeBytes = 0,
    this.createdAt,
  });
  final String id, title, kind, url, categoryId, ownerUid, ownerName;

  /// Cloudinary id of a public upload.
  final String? publicId;

  /// Firebase Storage path of a private library file.
  final String? storagePath;
  final int sizeBytes;
  final DateTime? createdAt;

  bool get isVideo => kind == 'video';
  bool get isPrivate => id.startsWith(privateSongPrefix);

  Song copyWith({String? title, String? categoryId, String? url}) => Song(
    id: id,
    title: title ?? this.title,
    kind: kind,
    url: url ?? this.url,
    categoryId: categoryId ?? this.categoryId,
    ownerUid: ownerUid,
    ownerName: ownerName,
    publicId: publicId,
    storagePath: storagePath,
    sizeBytes: sizeBytes,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind,
    'url': url,
    'categoryId': categoryId,
    'ownerUid': ownerUid,
    'ownerName': ownerName,
    'publicId': publicId,
    'sizeBytes': sizeBytes,
    'createdAt': createdAt?.millisecondsSinceEpoch,
  };

  /// Reads a song saved by [toJson], or returns null for an unusable entry.
  static Song? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final url = json['url'];
    if (id is! String || id.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    final createdAt = json['createdAt'];
    return Song(
      id: id,
      title: json['title'] as String? ?? 'Untitled',
      kind: json['kind'] == 'video' ? 'video' : 'audio',
      url: url,
      categoryId: json['categoryId'] as String? ?? '',
      ownerUid: json['ownerUid'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      publicId: json['publicId'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
    );
  }
}

enum UploadStatus { queued, uploading, done, skipped, failed }

/// One file in the public upload queue. The controller updates it in place
/// and notifies its listeners.
class UploadItem {
  UploadItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.title,
  });

  /// The file that will be uploaded; a trimmed copy once [applyTrim] ran.
  String path, name;
  int sizeBytes;
  String title;

  /// The picked file before trimming, kept so a trim can be redone or undone.
  ({String path, String name, int sizeBytes})? original;
  Duration? trimStart, trimEnd;

  bool get trimmed => original != null;

  /// Swaps in a trimmed copy of the original file.
  void applyTrim({
    required String trimmedPath,
    required int trimmedSize,
    required Duration start,
    required Duration end,
  }) {
    final source = original ??= (path: path, name: name, sizeBytes: sizeBytes);
    final extension =
        RegExp(r'\.[^./\\]+$').firstMatch(trimmedPath)?.group(0) ?? '';
    name = '${source.name.replaceAll(RegExp(r'\.[^.]+$'), '')}$extension';
    path = trimmedPath;
    sizeBytes = trimmedSize;
    trimStart = start;
    trimEnd = end;
  }

  /// Goes back to the picked file and returns the trimmed copy it replaced.
  String? undoTrim() {
    final source = original;
    if (source == null) return null;
    final trimmedPath = path;
    path = source.path;
    name = source.name;
    sizeBytes = source.sizeBytes;
    original = null;
    trimStart = null;
    trimEnd = null;
    return trimmedPath;
  }
  String categoryId = '';
  UploadStatus status = UploadStatus.queued;

  /// Fraction (0–1) of this file sent to Cloudinary.
  double progress = 0;
  String? error;

  /// Set once the file reached Cloudinary, so a retry only repeats the
  /// Firestore write instead of uploading the file again.
  String? uploadedUrl, uploadedPublicId;
  int durationMs = 0;

  bool get finished =>
      status != UploadStatus.queued && status != UploadStatus.uploading;
}

class MediaFolder {
  const MediaFolder({required this.id, required this.name});
  final String id, name;

  MediaFolder copyWith({String? name}) =>
      MediaFolder(id: id, name: name ?? this.name);
}

class SavedMedia {
  const SavedMedia({
    required this.id,
    required this.title,
    required this.kind,
    required this.folderId,
    this.sourceUrl,
    this.storagePath,
  });
  final String id, title, kind, folderId;
  final String? sourceUrl, storagePath;

  SavedMedia copyWith({
    String? title,
    String? folderId,
    String? sourceUrl,
    String? storagePath,
  }) => SavedMedia(
    id: id,
    title: title ?? this.title,
    kind: kind,
    folderId: folderId ?? this.folderId,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    storagePath: storagePath ?? this.storagePath,
  );
}
