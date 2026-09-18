import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/desede_engine.dart';

import 'music_data.dart';

typedef ProviderJsonFetcher = Future<Map<String, dynamic>> Function(Uri uri);
typedef ProviderJsonPoster =
    Future<Map<String, dynamic>> Function(
      Uri uri,
      Map<String, dynamic> body,
      Map<String, String> headers,
    );

/// A searchable music source whose final playback URL may be resolved lazily.
abstract class MusicProvider {
  String get id;
  String get displayName;

  Future<List<Song>> searchSongs(String query, {int limit = 20});
  Future<String> resolveStreamUrl(Song song);
}

/// JioSaavn source used by the provider bundle discovered in the reference APK.
///
/// Search results do not contain a directly playable URL. The service returns
/// an encrypted media address, so it is resolved only when playback/download
/// starts. No account credentials or API keys are stored by this class.
class JioSaavnProvider implements MusicProvider {
  JioSaavnProvider({ProviderJsonFetcher? fetchJson})
    : _fetchJson = fetchJson ?? _httpGetJson;

  static const _api = 'https://www.jiosaavn.com/api.php';
  final ProviderJsonFetcher _fetchJson;

  @override
  String get id => 'jiosaavn';

  @override
  String get displayName => 'JioSaavn';

  @override
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final data = await _fetchJson(
      _uri({
        '__call': 'search.getResults',
        'q': value,
        'p': '1',
        'n': '${limit.clamp(1, 50)}',
      }),
    );
    final raw = data['results'];
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((item) => _songFrom(Map<String, dynamic>.from(item)))
        .whereType<Song>()
        .toList(growable: false);
  }

  @override
  Future<String> resolveStreamUrl(Song song) async {
    if (song.providerId != id || song.sourceId.isEmpty) {
      throw const FormatException('This song does not belong to JioSaavn.');
    }
    final data = await _fetchJson(
      _uri({'__call': 'song.getDetails', 'pids': song.sourceId}),
    );
    Map<String, dynamic>? detail;
    final songs = data['songs'];
    if (songs is List && songs.isNotEmpty && songs.first is Map) {
      detail = Map<String, dynamic>.from(songs.first as Map);
    } else if (data[song.sourceId] is Map) {
      detail = Map<String, dynamic>.from(data[song.sourceId] as Map);
    }
    if (detail == null) throw const FormatException('Song was not found.');

    final more = _map(detail['more_info']);
    final encrypted = _string(
      more?['encrypted_media_url'] ?? detail['encrypted_media_url'],
    );
    if (encrypted.isEmpty) {
      throw const FormatException('No playable source is available.');
    }
    final decoded = decodeJioSaavnMediaUrl(encrypted);
    final hasHighQuality = _string(more?['320kbps']).toLowerCase() == 'true';
    return _withQuality(decoded, hasHighQuality ? '320' : '160');
  }

  Song? _songFrom(Map<String, dynamic> item) {
    final sourceId = _string(item['id']);
    final title = decodeHtmlText(item['title'] ?? item['name']);
    if (sourceId.isEmpty || title.isEmpty) return null;
    final more = _map(item['more_info']);
    final artists = _map(more?['artistMap'] ?? more?['artist_map']);
    final primary = artists?['primary_artists'];
    final artistNames = <String>[];
    if (primary is List) {
      for (final value in primary.whereType<Map>()) {
        final name = decodeHtmlText(value['name']);
        if (name.isNotEmpty) artistNames.add(name);
      }
    }
    if (artistNames.isEmpty) {
      final fallback = decodeHtmlText(more?['music'] ?? item['subtitle']);
      if (fallback.isNotEmpty) artistNames.add(fallback);
    }
    final durationSeconds = int.tryParse(_string(more?['duration'])) ?? 0;
    return Song(
      id: 'provider:$id:$sourceId',
      title: title,
      kind: 'audio',
      url: '',
      categoryId: 'provider:$id',
      providerId: id,
      sourceId: sourceId,
      artist: artistNames.join(', '),
      artworkUrl: _highResolutionArtwork(_string(item['image'])),
      durationMs: durationSeconds * 1000,
    );
  }

  static Uri _uri(Map<String, String> operation) => Uri.parse(_api).replace(
    queryParameters: {
      '_format': 'json',
      '_marker': '0',
      'ctx': 'web6dot0',
      'api_version': '4',
      ...operation,
    },
  );

  static Future<Map<String, dynamic>> _httpGetJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36',
        );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'JioSaavn returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('JioSaavn returned an invalid response.');
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}

/// Anonymous YouTube Music search and audio playback provider.
///
/// The web music client is used for discovery and the iOS player client for a
/// short-lived direct audio URL. URLs are deliberately resolved at play time
/// because YouTube signs them with an expiry timestamp.
class YouTubeMusicProvider implements MusicProvider {
  YouTubeMusicProvider({ProviderJsonPoster? postJson})
    : _postJson = postJson ?? _httpPostJson;

  static const _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const _webClientVersion = '1.20260222.01.00';
  static const _iosClientVersion = '20.10.4';
  static const _webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 Chrome/129.0.0.0 Safari/537.36';
  static const _iosUserAgent =
      'com.google.ios.youtube/20.10.4 '
      '(iPhone16,2; U; CPU iOS 18_3 like Mac OS X)';
  static const _trackSearchParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  final ProviderJsonPoster _postJson;

  @override
  String get id => 'ytmusic';

  @override
  String get displayName => 'YouTube Music';

  @override
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final data = await _postJson(
      Uri.parse(
        'https://music.youtube.com/youtubei/v1/search'
        '?alt=json&key=$_apiKey',
      ),
      {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': _webClientVersion,
            'hl': 'en',
            'gl': 'IN',
          },
          'user': <String, dynamic>{},
        },
        'query': value,
        'params': _trackSearchParams,
      },
      const {
        HttpHeaders.userAgentHeader: _webUserAgent,
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
      },
    );

    final renderers = <Map<String, dynamic>>[];
    _collectNamedMaps(data, 'musicResponsiveListItemRenderer', renderers);
    final seen = <String>{};
    final results = <Song>[];
    for (final renderer in renderers) {
      final song = _songFromRenderer(renderer);
      if (song != null && seen.add(song.sourceId)) results.add(song);
      if (results.length >= limit.clamp(1, 50)) break;
    }
    return results;
  }

  @override
  Future<String> resolveStreamUrl(Song song) async {
    if (song.providerId != id || song.sourceId.isEmpty) {
      throw const FormatException(
        'This song does not belong to YouTube Music.',
      );
    }
    final data = await _postJson(
      Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
      {
        'context': {
          'client': {
            'clientName': 'IOS',
            'clientVersion': _iosClientVersion,
            'deviceModel': 'iPhone16,2',
            'userAgent': _iosUserAgent,
            'hl': 'en',
            'gl': 'IN',
            'utcOffsetMinutes': 330,
          },
        },
        'videoId': song.sourceId,
        'playbackContext': {
          'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
        },
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      const {
        HttpHeaders.userAgentHeader: _iosUserAgent,
        'Origin': 'https://www.youtube.com',
        'X-YouTube-Client-Name': '5',
        'X-YouTube-Client-Version': _iosClientVersion,
      },
    );

    final status = _string(_at(data, ['playabilityStatus', 'status']));
    if (status != 'OK') {
      final reason = _string(_at(data, ['playabilityStatus', 'reason']));
      throw FormatException(
        reason.isEmpty ? 'This track is not playable.' : reason,
      );
    }
    final adaptive = _at(data, ['streamingData', 'adaptiveFormats']);
    if (adaptive is! List) {
      throw const FormatException('No audio stream is available.');
    }
    final audio =
        adaptive
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .where(
              (format) =>
                  _string(format['mimeType']).startsWith('audio/') &&
                  _string(format['url']).isNotEmpty,
            )
            .toList()
          ..sort(
            (a, b) => ((b['bitrate'] as num?)?.toInt() ?? 0).compareTo(
              (a['bitrate'] as num?)?.toInt() ?? 0,
            ),
          );
    if (audio.isEmpty) {
      throw const FormatException('No direct audio stream is available.');
    }
    return _string(audio.first['url']);
  }

  Song? _songFromRenderer(Map<String, dynamic> renderer) {
    final sourceId = _findFirstString(renderer, 'videoId');
    final columns = renderer['flexColumns'];
    if (sourceId == null || columns is! List || columns.isEmpty) return null;

    Map<String, dynamic>? columnRenderer(int index) {
      if (index >= columns.length || columns[index] is! Map) return null;
      final column = Map<String, dynamic>.from(columns[index] as Map);
      return _map(column['musicResponsiveListItemFlexColumnRenderer']);
    }

    final title = _text(columnRenderer(0)?['text']);
    if (title.isEmpty) return null;
    final subtitle = columnRenderer(1)?['text'];
    final runs = _map(subtitle)?['runs'];
    final artists = <String>[];
    final runTexts = <String>[];
    var durationMs = 0;
    if (runs is List) {
      for (final raw in runs.whereType<Map>()) {
        final run = Map<String, dynamic>.from(raw);
        final text = _string(run['text']);
        if (text.isEmpty) continue;
        runTexts.add(text);
        final browseId = _string(
          _at(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']),
        );
        if (browseId.startsWith('UC')) artists.add(text);
        final parsedDuration = _durationMs(text);
        if (parsedDuration != null) durationMs = parsedDuration;
      }
    }
    if (artists.isEmpty && runTexts.isNotEmpty) {
      final beforeAlbum = runTexts.takeWhile((text) => text != ' • ');
      artists.addAll(
        beforeAlbum.where(
          (text) => text != ' & ' && text != ', ' && text.trim().isNotEmpty,
        ),
      );
    }

    return Song(
      id: 'provider:$id:$sourceId',
      title: title,
      kind: 'audio',
      url: '',
      categoryId: 'provider:$id',
      providerId: id,
      sourceId: sourceId,
      artist: artists.toSet().join(', '),
      artworkUrl: _largestThumbnail(renderer),
      durationMs: durationMs,
    );
  }

  static Future<Map<String, dynamic>> _httpPostJson(
    Uri uri,
    Map<String, dynamic> body,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'YouTube Music returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map) {
        throw const FormatException(
          'YouTube Music returned an invalid response.',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}

/// Standard YouTube video search with a directly playable muxed MP4 stream.
class YouTubeVideoProvider implements MusicProvider {
  YouTubeVideoProvider({ProviderJsonPoster? postJson})
    : _postJson = postJson ?? YouTubeMusicProvider._httpPostJson;

  static const _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const _webClientVersion = '2.20260222.01.00';
  static const _androidClientVersion = '21.26.364';
  static const _webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 Chrome/129.0.0.0 Safari/537.36';
  static const _androidUserAgent =
      'com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip';

  final ProviderJsonPoster _postJson;

  @override
  String get id => 'ytvideo';

  @override
  String get displayName => 'YouTube Videos';

  @override
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final data = await _postJson(
      Uri.parse(
        'https://www.youtube.com/youtubei/v1/search'
        '?alt=json&key=$_apiKey',
      ),
      {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': _webClientVersion,
            'hl': 'en',
            'gl': 'IN',
          },
          'user': <String, dynamic>{},
        },
        'query': value,
        'params': 'EgIQAQ%3D%3D',
      },
      const {
        HttpHeaders.userAgentHeader: _webUserAgent,
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
      },
    );

    final renderers = <Map<String, dynamic>>[];
    _collectNamedMaps(data, 'videoRenderer', renderers);
    final seen = <String>{};
    final results = <Song>[];
    for (final renderer in renderers) {
      final sourceId = _string(renderer['videoId']);
      final title = _text(renderer['title']);
      if (sourceId.isEmpty || title.isEmpty || !seen.add(sourceId)) continue;
      final artist = _text(renderer['ownerText']).isNotEmpty
          ? _text(renderer['ownerText'])
          : _text(renderer['shortBylineText']);
      results.add(
        Song(
          id: 'provider:$id:$sourceId',
          title: title,
          kind: 'video',
          url: '',
          categoryId: 'provider:$id',
          providerId: id,
          sourceId: sourceId,
          artist: artist,
          artworkUrl: _largestThumbnail(renderer),
          durationMs: _durationMs(_text(renderer['lengthText'])) ?? 0,
        ),
      );
      if (results.length >= limit.clamp(1, 50)) break;
    }
    return results;
  }

  @override
  Future<String> resolveStreamUrl(Song song) async {
    if (song.providerId != id || song.sourceId.isEmpty) {
      throw const FormatException(
        'This video does not belong to YouTube Videos.',
      );
    }
    final data = await _postJson(
      Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
      {
        'context': {
          'client': {
            'clientName': 'ANDROID',
            'clientVersion': _androidClientVersion,
            'androidSdkVersion': 30,
            'userAgent': _androidUserAgent,
            'hl': 'en',
            'platform': 'MOBILE',
            'osName': 'Android',
            'osVersion': '11',
            'timeZone': 'Asia/Calcutta',
            'gl': 'IN',
            'utcOffsetMinutes': 330,
          },
        },
        'videoId': song.sourceId,
        'playbackContext': {
          'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
        },
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      const {
        HttpHeaders.userAgentHeader: _androidUserAgent,
        'Origin': 'https://www.youtube.com',
        'X-YouTube-Client-Name': '3',
        'X-YouTube-Client-Version': _androidClientVersion,
      },
    );

    final status = _string(_at(data, ['playabilityStatus', 'status']));
    if (status != 'OK') {
      final reason = _string(_at(data, ['playabilityStatus', 'reason']));
      throw FormatException(
        reason.isEmpty ? 'This video is not playable.' : reason,
      );
    }
    final formats = _at(data, ['streamingData', 'formats']);
    if (formats is! List) {
      throw const FormatException('No video stream is available.');
    }
    final muxed =
        formats
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .where(
              (format) =>
                  _string(format['mimeType']).startsWith('video/') &&
                  _string(format['mimeType']).contains('mp4a') &&
                  _string(format['url']).isNotEmpty,
            )
            .toList()
          ..sort(
            (a, b) => ((b['bitrate'] as num?)?.toInt() ?? 0).compareTo(
              (a['bitrate'] as num?)?.toInt() ?? 0,
            ),
          );
    if (muxed.isEmpty) {
      throw const FormatException(
        'No compatible video-with-audio stream is available.',
      );
    }
    return _string(muxed.first['url']);
  }
}

void _collectNamedMaps(
  Object? value,
  String key,
  List<Map<String, dynamic>> output,
) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final match = map[key];
    if (match is Map) output.add(Map<String, dynamic>.from(match));
    for (final child in map.values) {
      _collectNamedMaps(child, key, output);
    }
  } else if (value is List) {
    for (final child in value) {
      _collectNamedMaps(child, key, output);
    }
  }
}

String? _findFirstString(Object? value, String key) {
  if (value is Map) {
    final direct = value[key];
    if (direct is String && direct.isNotEmpty) return direct;
    for (final child in value.values) {
      final found = _findFirstString(child, key);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final child in value) {
      final found = _findFirstString(child, key);
      if (found != null) return found;
    }
  }
  return null;
}

Object? _at(Map<String, dynamic> root, List<String> path) {
  Object? value = root;
  for (final key in path) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

String _text(Object? value) {
  if (value is! Map) return '';
  final simple = _string(value['simpleText']);
  if (simple.isNotEmpty) return simple;
  final runs = value['runs'];
  if (runs is! List) return '';
  return runs
      .whereType<Map>()
      .map((run) => _string(run['text']))
      .where((text) => text.isNotEmpty)
      .join();
}

int? _durationMs(String value) {
  if (!RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?$').hasMatch(value.trim())) {
    return null;
  }
  final parts = value.trim().split(':').map(int.parse).toList();
  final seconds = parts.length == 3
      ? parts[0] * 3600 + parts[1] * 60 + parts[2]
      : parts[0] * 60 + parts[1];
  return seconds * 1000;
}

String _largestThumbnail(Object? root) {
  String best = '';
  var bestWidth = -1;

  void visit(Object? value) {
    if (value is Map) {
      final thumbnails = value['thumbnails'];
      if (thumbnails is List) {
        for (final raw in thumbnails.whereType<Map>()) {
          final url = _string(raw['url']);
          final width = (raw['width'] as num?)?.toInt() ?? 0;
          if (url.isNotEmpty && width >= bestWidth) {
            best = url.startsWith('//') ? 'https:$url' : url;
            bestWidth = width;
          }
        }
      }
      for (final child in value.values) {
        visit(child);
      }
    } else if (value is List) {
      for (final child in value) {
        visit(child);
      }
    }
  }

  visit(root);
  return best;
}

/// Decodes the DES-ECB media address returned by JioSaavn.
String decodeJioSaavnMediaUrl(String encryptedUrl) {
  final encrypted = base64Decode(encryptedUrl.trim());
  if (encrypted.isEmpty || encrypted.length % 8 != 0) {
    throw const FormatException('Invalid encrypted media URL.');
  }

  // DES-EDE with K1=K2=K3 is mathematically equivalent to single DES. This
  // lets us use PointyCastle's maintained DESede primitive for the legacy URL
  // format without implementing cryptography in the app.
  final key = utf8.encode('38346591');
  final repeatedKey = Uint8List.fromList([...key, ...key, ...key]);
  final cipher = DESedeEngine()..init(false, KeyParameter(repeatedKey));
  final decrypted = Uint8List(encrypted.length);
  for (var offset = 0; offset < encrypted.length; offset += cipher.blockSize) {
    cipher.processBlock(encrypted, offset, decrypted, offset);
  }

  var length = decrypted.length;
  final padding = decrypted.last;
  if (padding > 0 && padding <= 8 && padding <= length) {
    final valid = decrypted
        .sublist(length - padding)
        .every((value) => value == padding);
    if (valid) length -= padding;
  }
  var url = utf8.decode(decrypted.sublist(0, length));
  url = url.replaceFirst(RegExp(r'\.mp4.*$'), '.mp4');
  url = url.replaceFirst(RegExp(r'\.m4a.*$'), '.m4a');
  return url.replaceFirst(RegExp(r'^http:'), 'https:');
}

String _withQuality(String url, String quality) =>
    url.replaceFirst(RegExp(r'_(?:96|160|320)\.'), '_$quality.');

String _highResolutionArtwork(String url) =>
    url.replaceFirst('50x50', '500x500').replaceFirst('150x150', '500x500');

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

String _string(Object? value) => value?.toString().trim() ?? '';

/// Decodes the small HTML entity subset used in JioSaavn metadata.
String decodeHtmlText(Object? value) {
  var text = _string(value);
  text = text.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (match) {
    final raw = match.group(1)!;
    final radix = raw.startsWith('x') || raw.startsWith('X') ? 16 : 10;
    final digits = radix == 16 ? raw.substring(1) : raw;
    final code = int.tryParse(digits, radix: radix);
    return code == null ? match.group(0)! : String.fromCharCode(code);
  });
  const entities = {
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': ' ',
  };
  for (final entry in entities.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text.trim();
}
