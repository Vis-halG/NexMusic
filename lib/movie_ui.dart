import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'movie_provider.dart';
import 'music_controller.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key, this.provider});
  final MovieBoxProvider? provider;
  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  late final _provider = widget.provider ?? MovieBoxProvider();
  final _search = TextEditingController();
  Timer? _debounce;
  String _category = 'Trending';
  List<MovieShelf> _shelves = [];
  List<MovieTitle> _results = [];
  bool _loading = true, _moreLoading = false, _hasMore = false;
  String? _error;
  int _request = 0, _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    _debounce?.cancel();
    final request = ++_request;
    final query = _search.text.trim();
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = !more;
      _moreLoading = more;
      _error = null;
    });
    try {
      if (query.isEmpty) {
        final shelves = await _provider.home(category: _category);
        if (!mounted || request != _request) return;
        setState(() {
          _shelves = shelves;
          _hasMore = false;
        });
      } else {
        final results = await _provider.search(query, page: page);
        if (!mounted || request != _request) return;
        final seen = <String>{};
        setState(() {
          _results = [
            if (more) ..._results,
            ...results.movies,
          ].where((movie) => seen.add(movie.id)).toList();
          _hasMore = results.hasMore && results.movies.isNotEmpty;
          _page = page;
        });
      }
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(
        () => _error =
            'MovieBox could not load. Check your connection and retry.',
      );
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _moreLoading = false;
        });
      }
    }
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _request++;
    setState(() {
      _loading = true;
      _moreLoading = false;
      _results = [];
    });
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _open(MovieTitle movie) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MovieDetailsScreen(movie: movie, provider: _provider),
    ),
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      key: const PageStorageKey('movies'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
          child: Row(
            children: [
              Icon(
                Icons.movie_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Movies',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Discover movies & series · MovieBox',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh movies',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: 'Search movies and TV shows',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear movie search',
                      onPressed: () {
                        _search.clear();
                        _onSearch('');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        if (_search.text.trim().isEmpty)
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: MovieBoxProvider.categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final category = MovieBoxProvider.categories.keys.elementAt(i);
                return ChoiceChip(
                  label: Text(category),
                  selected: _category == category,
                  onSelected: (_) {
                    setState(() => _category = category);
                    _load();
                  },
                );
              },
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _MovieMessage(message: _error!, retry: _load)
        else if (_search.text.trim().isNotEmpty) ...[
          if (_results.isEmpty)
            const _MovieMessage(
              message: 'No titles found. Try another movie or series name.',
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: 275,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: _results.length,
                itemBuilder: (_, i) => _MovieCard(
                  movie: _results[i],
                  onTap: () => _open(_results[i]),
                ),
              ),
            ),
          if (_moreLoading)
            const Center(child: CircularProgressIndicator())
          else if (_hasMore)
            Center(
              child: TextButton(
                onPressed: () => _load(more: true),
                child: const Text('Load more'),
              ),
            ),
        ] else ...[
          if (_shelves.isEmpty)
            _MovieMessage(
              message: 'No titles available right now.',
              retry: _load,
            ),
          for (final shelf in _shelves)
            _MovieShelfView(shelf: shelf, onOpen: _open),
        ],
      ],
    ),
  );
}

class _MovieMessage extends StatelessWidget {
  const _MovieMessage({required this.message, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        const Icon(Icons.movie_outlined, size: 40),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

class _MovieShelfView extends StatelessWidget {
  const _MovieShelfView({required this.shelf, required this.onOpen});
  final MovieShelf shelf;
  final ValueChanged<MovieTitle> onOpen;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Text(
          shelf.title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      SizedBox(
        height: 278,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: shelf.movies.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) => SizedBox(
            width: 148,
            child: _MovieCard(
              movie: shelf.movies[i],
              onTap: () => onOpen(shelf.movies[i]),
            ),
          ),
        ),
      ),
    ],
  );
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({required this.movie, required this.onTap});
  final MovieTitle movie;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.expand(
              child: movie.poster.isEmpty
                  ? const ColoredBox(
                      color: Color(0xFF282535),
                      child: Icon(Icons.movie_outlined, size: 36),
                    )
                  : Image.network(
                      movie.poster,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFF282535),
                        child: Icon(Icons.movie_outlined, size: 36),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          movie.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          [
            movie.year,
            if (movie.rating.isNotEmpty && movie.rating != '0')
              '★ ${movie.rating}',
            movie.isSeries ? 'Series' : 'Movie',
          ].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class MovieDetailsScreen extends StatefulWidget {
  const MovieDetailsScreen({
    super.key,
    required this.movie,
    required this.provider,
  });
  final MovieTitle movie;
  final MovieBoxProvider provider;
  @override
  State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  late Future<List<MovieTitle>> _related = widget.provider.related(
    widget.movie,
  );
  Future<void> _watch() async {
    final music = context.read<MusicController>();
    await music.pauseAudio();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MovieWatchScreen(
          title: widget.movie.title,
          uri: widget.provider.watchUri(widget.movie),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Scaffold(
      appBar: AppBar(title: const Text('Movie details')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SizedBox(
                    width: 190,
                    height: 285,
                    child: _MovieCard(movie: movie, onTap: _watch),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  movie.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(movie.genre.replaceAll(',', ' · ')),
                if (movie.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(movie.description),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _watch,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Watch on MovieBox'),
                  ),
                ),
              ],
            ),
          ),
          FutureBuilder<List<MovieTitle>>(
            future: _related,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _MovieMessage(
                  message: 'Related titles could not load.',
                  retry: () =>
                      setState(() => _related = widget.provider.related(movie)),
                );
              }
              final movies = snapshot.data ?? [];
              if (movies.isEmpty) return const SizedBox.shrink();
              return _MovieShelfView(
                shelf: MovieShelf('You may also like', movies),
                onOpen: (next) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MovieDetailsScreen(
                      movie: next,
                      provider: widget.provider,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class MovieWatchScreen extends StatefulWidget {
  const MovieWatchScreen({super.key, required this.title, required this.uri});
  final String title;
  final Uri uri;
  @override
  State<MovieWatchScreen> createState() => _MovieWatchScreenState();
}

class _MovieWatchScreenState extends State<MovieWatchScreen> {
  WebViewController? _web;
  int _progress = 0;
  bool _failed = false, _canGoBack = false;
  @override
  void initState() {
    super.initState();
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || !['https', 'http'].contains(uri.scheme)) {
              return NavigationDecision.prevent;
            }
            // Embedded video hosts can load in frames. Keep top-level ad
            // redirects from replacing the movie player with unrelated sites.
            final allowed =
                !request.isMainFrame ||
                uri.host == widget.uri.host ||
                uri.host == 'movieboxhd.net' ||
                uri.host == 'moviebox.ph' ||
                uri.host == 'aoneroom.com' ||
                uri.host.endsWith('.aoneroom.com');
            return allowed
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _failed = false;
                _progress = 0;
              });
            }
          },
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (_) async {
            final canGoBack = await _web!.canGoBack();
            if (mounted) setState(() => _canGoBack = canGoBack);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_canGoBack,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) await _web?.goBack();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Reload player',
            onPressed: () => _web?.reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Close player',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: _web == null
          ? const _MovieMessage(
              message: 'Movie playback is available on Android and iOS.',
            )
          : Column(
              children: [
                if (_progress < 100 && !_failed)
                  LinearProgressIndicator(value: _progress / 100),
                Expanded(
                  child: _failed
                      ? _MovieMessage(
                          message: 'The MovieBox player could not load.',
                          retry: () => _web!.reload(),
                        )
                      : WebViewWidget(controller: _web!),
                ),
              ],
            ),
    ),
  );
}
