import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nex_app/movie_provider.dart';
import 'package:nex_app/movie_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android loads MovieBox catalogues and native movie cards', (
    tester,
  ) async {
    final provider = MovieBoxProvider(baseUri: Uri.parse('https://movieboxhd.net'));
    for (final category in MovieBoxProvider.categories.keys) {
      final shelves = await provider.home(category: category);
      expect(shelves, isNotEmpty, reason: category);
      debugPrint('MOVIE_CHECK $category: ${shelves.length} shelves');
    }
    final results = await provider.search('Inception');
    expect(results.movies, isNotEmpty);
    expect(await provider.related(results.movies.first), isNotEmpty);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MoviesScreen(provider: provider))),
    );
    for (var attempt = 0; attempt < 45; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Featured today'), findsOneWidget);
  });
}
