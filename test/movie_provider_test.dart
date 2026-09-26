import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_app/movie_provider.dart';

Map<String, dynamic> movie(String id, {int type = 1}) => {
  'subjectId': id,
  'subjectType': type,
  'title': 'Movie $id',
  'detailPath': 'movie-$id',
  'cover': {'url': 'https://example.com/poster.jpg'},
  'releaseDate': '2026-09-01',
  'imdbRatingValue': '8.1',
};

void main() {
  test(
    'movie home preserves recommendations, filters non-movies and duplicates',
    () async {
      final provider = MovieBoxProvider(
        fetch: (uri, body) async {
          expect(uri.path, '/web/movie');
          return {
            'code': 0,
            'data': {
              'operatingList': [
                {
                  'title': 'Trending',
                  'subjects': [movie('1'), movie('1'), movie('music', type: 3)],
                },
                {
                  'type': 'BANNER',
                  'banner': {
                    'items': [
                      {'subject': movie('2', type: 2)},
                    ],
                  },
                },
              ],
            },
          };
        },
      );
      final shelves = await provider.home(category: 'Movies');
      expect(shelves.map((s) => s.title), ['Trending', 'Featured today']);
      expect(shelves.first.movies, hasLength(1));
      expect(shelves.last.movies.single.isSeries, true);
    },
  );
  test('search trims text and never repeats the public first page', () async {
    var calls = 0;
    final provider = MovieBoxProvider(
      fetch: (uri, body) async {
        calls++;
        expect(body!['keyword'], 'Example');
        return {
          'code': 0,
          'data': {
            'items': [movie('1')],
            'pager': {'hasMore': true},
          },
        };
      },
    );
    expect((await provider.search(' Example ')).movies.single.year, '2026');
    expect((await provider.search('Example', page: 2)).movies, isEmpty);
    expect(calls, 1);
  });
  test(
    'public Nuxt search preserves large identifiers and shared references',
    () {
      final table = [
        {'pager': 1, 'items': 2},
        {'hasMore': 3},
        [4],
        false,
        {'subjectId': 5, 'subjectType': 6, 'title': 7, 'detailPath': 8},
        '9223372036854775806',
        1,
        'Test movie',
        'test-movie',
      ];
      final result = parseMovieSearchHtml(
        '<script id="__NUXT_DATA__">${jsonEncode(table)}</script>',
      );
      expect(result['data']['items'][0]['subjectId'], '9223372036854775806');
      expect(result['data']['items'][0]['subjectType'], 1);
      expect(
        () => parseMovieSearchHtml('<html>offline</html>'),
        throwsFormatException,
      );
    },
  );
  test(
    'server errors are surfaced and watch links remain on provider origin',
    () async {
      final provider = MovieBoxProvider(fetch: (_, _) async => {'code': 500});
      expect(provider.home(), throwsFormatException);
      final uri = provider.watchUri(
        const MovieTitle(id: 'a&b', title: 'Movie', detailPath: 'a?b'),
      );
      expect(uri.host, 'moviebox.ph');
      expect(uri.queryParameters['id'], 'a&b');
      expect(uri.pathSegments.last, 'a?b');
    },
  );
}
