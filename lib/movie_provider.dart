import 'dart:convert';
import 'dart:io';

typedef MovieFetcher =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, dynamic>? body);

/// Decodes just the public search payload in Nuxt's indexed serialization.
/// String IDs stay strings (several exceed JavaScript's integer precision).
Map<String, dynamic> parseMovieSearchHtml(String html, {bool search = true}) {
  final match = RegExp(
    r'''<script\b[^>]*id=["']__NUXT_DATA__["'][^>]*>(.*?)</script>''',
    dotAll: true,
  ).firstMatch(html);
  if (match == null) throw const FormatException('Search data is unavailable.');
  final table = jsonDecode(match.group(1)!);
  if (table is! List) throw const FormatException('Invalid search data.');
  final active = <int>{};
  final cache = <int, dynamic>{};
  dynamic read(dynamic index) {
    if (index is! int || index < 0 || index >= table.length) return null;
    if (cache.containsKey(index)) return cache[index];
    if (!active.add(index) || active.length > 60) {
      throw const FormatException('Invalid search references.');
    }
    final raw = table[index];
    dynamic value;
    if (raw is Map) {
      value = {
        for (final entry in raw.entries) '${entry.key}': read(entry.value),
      };
    } else if (raw is List) {
      value =
          raw.length == 2 &&
              [
                'Reactive',
                'ShallowReactive',
                'Ref',
                'ShallowRef',
              ].contains(raw.first)
          ? read(raw[1])
          : raw.map(read).toList();
    } else {
      value = raw;
    }
    active.remove(index);
    cache[index] = value;
    return value;
  }

  for (var i = 0; i < table.length; i++) {
    final raw = table[i];
    if (raw is Map &&
        (search
            ? raw.containsKey('pager') && raw.containsKey('items')
            : raw.containsKey('operatingList') ||
                  raw.containsKey('subjectList'))) {
      return {'code': 0, 'data': read(i)};
    }
  }
  throw const FormatException('Search results are unavailable.');
}

class MovieTitle {
  const MovieTitle({
    required this.id,
    required this.title,
    required this.detailPath,
    this.poster = '',
    this.description = '',
    this.year = '',
    this.genre = '',
    this.rating = '',
    this.isSeries = false,
  });
  final String id, title, detailPath, poster, description, year, genre, rating;
  final bool isSeries;

  static MovieTitle? fromJson(Map raw) {
    final id = raw['subjectId']?.toString() ?? '';
    final title = raw['title']?.toString() ?? '';
    final path = raw['detailPath']?.toString() ?? '';
    // Music/live/ad records use other subject types and are not movie cards.
    if (id.isEmpty ||
        title.isEmpty ||
        path.isEmpty ||
        ![1, 2].contains(int.tryParse('${raw['subjectType']}'))) {
      return null;
    }
    final date = raw['releaseDate']?.toString() ?? '';
    return MovieTitle(
      id: id,
      title: title,
      detailPath: path,
      poster: raw['cover'] is Map ? '${raw['cover']['url'] ?? ''}' : '',
      description: '${raw['description'] ?? ''}',
      year: date.length >= 4 ? date.substring(0, 4) : '',
      genre: '${raw['genre'] ?? ''}',
      rating: '${raw['imdbRatingValue'] ?? ''}',
      isSeries: '${raw['subjectType']}' == '2',
    );
  }
}

class MovieShelf {
  const MovieShelf(this.title, this.movies);
  final String title;
  final List<MovieTitle> movies;
}

class MovieSearchPage {
  const MovieSearchPage(this.movies, {required this.hasMore});
  final List<MovieTitle> movies;
  final bool hasMore;
}

/// Uses MovieBox's public website catalogue. Playback stays in its web player,
/// which owns access checks, stream selection, subtitles and episode selection.
class MovieBoxProvider {
  MovieBoxProvider({MovieFetcher? fetch, Uri? baseUri})
    : _fetch = fetch ?? _request,
      baseUri = baseUri ?? Uri.parse('https://moviebox.ph');
  final MovieFetcher _fetch;
  final Uri baseUri;
  static const categories = {
    'Trending': '/',
    'Movies': '/web/movie',
    'TV Shows': '/web/tv-series',
    'Anime': '/web/animated-series',
  };

  Uri _uri(String path, [Map<String, String>? query]) => baseUri
      .resolve('/wefeed-h5api-bff/$path')
      .replace(queryParameters: query);

  Future<List<MovieShelf>> home({String category = 'Trending'}) async {
    final data = _data(
      await _fetch(baseUri.resolve(categories[category] ?? '/'), null),
    );
    final shelves = <MovieShelf>[];
    final subjectList = data['subjectList'];
    final rows =
        data['operatingList'] ??
        (subjectList is Map
            ? [
                {'title': category, 'subjects': subjectList['items']},
              ]
            : null);
    if (rows is! List) {
      throw const FormatException('Movie catalogue is unavailable.');
    }
    for (final row in rows.whereType<Map>()) {
      var raw = row['subjects'];
      final banner = row['banner'];
      if ((raw is! List || raw.isEmpty) &&
          banner is Map &&
          banner['items'] is List) {
        raw = (banner['items'] as List)
            .whereType<Map>()
            .map((e) => e['subject'])
            .toList();
      }
      final movies = _titles(raw);
      if (movies.isNotEmpty) {
        shelves.add(
          MovieShelf(
            row['type'] == 'BANNER'
                ? 'Featured today'
                : '${row['title'] ?? 'Recommended'}',
            movies,
          ),
        );
      }
    }
    return shelves;
  }

  Future<MovieSearchPage> search(String query, {int page = 1}) async {
    // This public page exposes the initial results only; do not repeat them
    // as invented subsequent pages.
    if (query.trim().isEmpty || page > 1) {
      return const MovieSearchPage([], hasMore: false);
    }
    final data = _data(
      await _fetch(_uri('subject/search'), {
        'keyword': query.trim(),
        'page': page,
        'perPage': 24,
        'subjectType': 0,
      }),
    );

    return MovieSearchPage(_titles(data['items']), hasMore: false);
  }

  Future<List<MovieTitle>> related(MovieTitle movie) async => _titles(
    _data(
      await _fetch(
        _uri('subject/detail-rec', {
          'subjectId': movie.id,
          'page': '1',
          'perPage': '12',
        }),
        null,
      ),
    )['items'],
  );

  Uri watchUri(MovieTitle movie) => baseUri
      .resolve('/moviedetail/')
      .replace(
        pathSegments: ['moviedetail', movie.detailPath],
        queryParameters: {'id': movie.id, 'type': '/movie/detail'},
      );

  static List<MovieTitle> _titles(dynamic raw) {
    if (raw is! List) return [];
    final seen = <String>{};
    return raw
        .whereType<Map>()
        .map(MovieTitle.fromJson)
        .whereType<MovieTitle>()
        .where((movie) => seen.add(movie.id))
        .toList();
  }

  static Map _data(Map<String, dynamic> response) {
    if (response['code'] != 0 || response['data'] is! Map) {
      throw const FormatException('MovieBox could not load this catalogue.');
    }
    return response['data'] as Map;
  }

  static Future<Map<String, dynamic>> _request(
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      // Search is server-rendered on the public website. No native app tokens
      // or private account credentials are extracted or replayed.
      final target = body == null
          ? uri
          : uri
                .resolve('/web/searchResult')
                .replace(queryParameters: {'keyword': '${body['keyword']}'});
      final request = await client.getUrl(target);
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw HttpException('MovieBox HTTP ${response.statusCode}');
      }
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      if (body != null) return parseMovieSearchHtml(text);
      if (!uri.path.startsWith('/wefeed-')) {
        return parseMovieSearchHtml(text, search: false);
      }
      final json = jsonDecode(text);
      if (json is! Map) throw const FormatException('Invalid movie catalogue.');
      return Map<String, dynamic>.from(json);
    } finally {
      client.close(force: true);
    }
  }
}
