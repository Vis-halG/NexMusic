// ignore_for_file: avoid_print
import 'package:nex_app/movie_provider.dart';

Future<void> main() async {
  final provider = MovieBoxProvider();
  for (final category in MovieBoxProvider.categories.keys) {
    final shelves = await provider.home(category: category);
    if (shelves.isEmpty) throw StateError('$category returned no shelves');
    print(
      '$category: ${shelves.length} shelves, ${shelves.first.movies.length} featured titles',
    );
  }
  final search = await provider.search('Inception');
  if (!search.movies.any((m) => m.title.contains('Inception'))) {
    throw StateError('Movie search did not return the requested title');
  }
  print('Search: ${search.movies.length} titles');
  final related = await provider.related(search.movies.first);
  if (related.isEmpty) throw StateError('No related titles');
  print('Related: ${related.length} titles');
}
