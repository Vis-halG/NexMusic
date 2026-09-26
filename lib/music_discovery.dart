import 'music_data.dart';
import 'music_provider.dart';

/// Round-robin ranking keeps both catalogues visible, with stable de-duplication.
List<Song> mergeMusicResults(Iterable<List<Song>> sources, {int? limit}) {
  final lists = sources.toList();
  final ids = <String>{};
  final recordings = <String>{};
  final result = <Song>[];
  String normalize(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  for (var row = 0; lists.any((list) => row < list.length); row++) {
    for (final list in lists) {
      if (row >= list.length) continue;
      final song = list[row];
      final recording =
          '${song.kind}:${normalize(song.title)}:${normalize(song.artist)}';
      if (!ids.add(song.id)) continue;
      // Missing artist metadata is insufficient evidence of a duplicate.
      if (song.artist.trim().isNotEmpty && !recordings.add(recording)) continue;
      result.add(song);
      if (limit != null && result.length >= limit) return result;
    }
  }
  return result;
}

class MusicFeedResult {
  const MusicFeedResult(this.songs, {this.unavailable = const []});
  final List<Song> songs;
  final List<String> unavailable;
}

/// Discovery failure on one source never hides results from the other source.
class MusicDiscovery {
  MusicDiscovery(this.providers);
  final List<MusicProvider> providers;
  final _pending = <String, Future<List<Song>>>{};
  final _cache = <String, ({DateTime at, List<Song> songs})>{};

  Future<List<Song>> _cached(String key, Future<List<Song>> Function() fetch) {
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 3) {
      return Future.value(cached.songs);
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final songs = await fetch().timeout(const Duration(seconds: 30));
        if (_cache.length >= 80) _cache.remove(_cache.keys.first);
        _cache[key] = (at: DateTime.now(), songs: songs);
        return songs;
      } finally {
        _pending.remove(key);
      }
    });
  }

  void clearCache() => _cache.clear();

  Future<MusicFeedResult> browse({
    String query = '',
    bool videos = false,
    int page = 1,
    int limit = 20,
  }) async {
    final selected = providers
        .where(
          (p) => videos
              ? p.id == 'ytvideo'
              : p.id == 'jiosaavn' || p.id == 'ytmusic',
        )
        .toList();
    final failures = <String>[];
    final lists = await Future.wait(
      selected.map((provider) async {
        try {
          return await _cached(
            '${provider.id}:$query:$page:$limit',
            () => query.trim().isEmpty
                ? provider.loadFeatured(limit: limit, page: page)
                : provider.searchSongs(query.trim(), limit: limit, page: page),
          );
        } catch (_) {
          failures.add(provider.displayName);
          return <Song>[];
        }
      }),
    );
    return MusicFeedResult(mergeMusicResults(lists), unavailable: failures);
  }

  Future<List<Song>> radio(Song seed, {int limit = 25}) async {
    final lists = await Future.wait(
      providers.where((p) => p.id == 'jiosaavn' || p.id == 'ytmusic').map((
        provider,
      ) async {
        try {
          return await _cached(
            'radio:${provider.id}:${seed.id}:$limit',
            () async {
              var sourceId = seed.sourceId;
              if (seed.providerId != provider.id &&
                  !(seed.providerId == 'ytvideo' && provider.id == 'ytmusic')) {
                final matches = await provider.searchSongs(
                  '${seed.title} ${seed.artist}'.trim(),
                  limit: 1,
                );
                if (matches.isEmpty) return <Song>[];
                sourceId = matches.first.sourceId;
              }
              return provider.loadRadio(sourceId, limit: limit);
            },
          );
        } catch (_) {
          return <Song>[];
        }
      }),
    );
    return mergeMusicResults(lists, limit: limit + 1)
        .where(
          (s) =>
              s.id != seed.id &&
              !(s.title.toLowerCase() == seed.title.toLowerCase() &&
                  s.artist.toLowerCase() == seed.artist.toLowerCase()),
        )
        .take(limit)
        .toList();
  }
}
