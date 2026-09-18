import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'main.dart';
import 'music_controller.dart';
import 'music_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

bool get _webViewSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Bumped when a home screen widget asks for the search bar.
final _searchRequests = ValueNotifier<int>(0);

Color _muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

String _time(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _fileSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

String _fileName(String filePath) => filePath.split(RegExp(r'[\\/]')).last;

IconData _mediaIcon(SavedMedia item) => switch (item.kind) {
  'audio' => Icons.music_note_rounded,
  'video' => Icons.play_arrow_rounded,
  _ => Icons.link_rounded,
};

String _mediaSubtitle(MusicController music, SavedMedia item) {
  final type = switch (item.kind) {
    'audio' => 'Audio',
    'video' => 'Video',
    _ => 'Link',
  };
  return music.isDownloaded(item) ? '$type · Offline' : type;
}

void _push(BuildContext context, Widget screen) {
  Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
}

void _openSong(BuildContext context, Song song, {List<Song>? queue}) {
  final music = context.read<MusicController>();
  if (song.isVideo) {
    _push(
      context,
      VideoScreen(song: song.copyWith(url: music.playableUrl(song))),
    );
    return;
  }
  music.play(song, from: queue);
}

void _openPlayer(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const NowPlayingScreen(),
    ),
  );
}

Future<void> _sheet(
  BuildContext context,
  List<Widget> Function(BuildContext sheetContext) children, {
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ...children(sheetContext),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _nameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String? hint,
  String? initialValue,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      action: action,
      hint: hint,
      initialValue: initialValue,
    ),
  );
  final trimmed = result?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<MusicCategory?> _createCategory(BuildContext context) async {
  final music = context.read<MusicController>();
  final name = await _nameDialog(
    context,
    title: 'New category',
    action: 'Create',
    hint: 'e.g. Bollywood',
  );
  if (name == null) return null;
  return music.createCategory(name);
}

Future<MediaFolder?> _createFolder(BuildContext context) async {
  final music = context.read<MusicController>();
  final name = await _nameDialog(
    context,
    title: 'New folder',
    action: 'Create',
    hint: 'e.g. Workout clips',
  );
  if (name == null) return null;
  return music.createMediaFolder(name);
}

/// Native Android helpers for trimming and extracting audio.
const _mediaTools = MethodChannel('com.thenex.nexmusic/media_tools');

bool get _canTrim => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Opens the trim screen for an upload and applies the chosen range.
Future<bool> _trimUpload(BuildContext context, UploadItem item) async {
  final result = await Navigator.of(context)
      .push<({String path, Duration start, Duration end})>(
        MaterialPageRoute(
          builder: (_) => TrimScreen(
            source: item.original?.path ?? item.path,
            title: item.title,
            start: item.trimStart,
            end: item.trimEnd,
          ),
        ),
      );
  if (result == null) return false;
  final previousCopy = item.trimmed ? item.path : null;
  item.applyTrim(
    trimmedPath: result.path,
    trimmedSize: File(result.path).lengthSync(),
    start: result.start,
    end: result.end,
  );
  if (previousCopy != null) discardTemporaryCopy(previousCopy);
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Rounded choice used for categories, folders and "new" actions.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.onLongPress,
  });
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.surface : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: 36,
        child: Material(
          color: selected ? scheme.onSurface : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 4),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Required single choice (category or folder) with a trailing "new" pill.
class _ChoicePicker extends StatelessWidget {
  const _ChoicePicker({
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onChanged,
    required this.onCreate,
    required this.createLabel,
    this.onManage,
  });
  final String label, createLabel;
  final List<({String id, String name})> options;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final Future<String?> Function() onCreate;

  /// Opens a screen to rename or delete the options, when set.
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: _muted(context)),
            ),
          ),
          if (onManage != null)
            TextButton.icon(
              onPressed: onManage,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      SizedBox(height: onManage == null ? 10 : 2),
      Wrap(
        runSpacing: 8,
        children: [
          for (final option in options)
            _Pill(
              label: option.name,
              selected: option.id == selectedId,
              onTap: () => onChanged(option.id),
            ),
          _Pill(
            icon: Icons.add_rounded,
            label: createLabel,
            onTap: () async {
              final id = await onCreate();
              if (id != null) onChanged(id);
            },
          ),
        ],
      ),
    ],
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.icon, this.active = false, this.size = 44});
  final IconData icon;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active
            ? NexMusicApp.violet.withValues(alpha: 0.12)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: active ? NexMusicApp.violet : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, this.size = 36});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.surfaceContainer,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: _muted(context)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted(context), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
  });
  final IconData icon;
  final String title;
  final String? trailing;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing != null)
          Text(trailing!, style: TextStyle(color: _muted(context))),
        if (showChevron)
          Icon(Icons.chevron_right_rounded, color: _muted(context)),
      ],
    ),
    onTap: onTap,
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    this.hint,
    this.initialValue,
  });
  final String title, action;
  final String? hint, initialValue;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: NexMusicApp.violet),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign in
// ─────────────────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context
        .select<
          MusicController,
          ({bool loading, bool configured, String? notice})
        >(
          (music) => (
            loading: music.loading,
            configured: music.backendConfigured,
            notice: music.notice,
          ),
        );
    final music = context.read<MusicController>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/branding/nexmusic-logo.png',
                    width: 56,
                    height: 56,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'nexMusic',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload songs and videos into categories.\nEveryone signed in can listen.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: _muted(context),
                ),
              ),
              const Spacer(),
              // The snackbar host only exists after sign-in, so login errors
              // are shown inline here.
              if (state.notice != null) ...[
                Text(
                  state.notice!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton(
                onPressed: state.loading || !state.configured
                    ? null
                    : music.signInWithGoogle,
                child: state.loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GoogleLogo(),
                          SizedBox(width: 12),
                          Text('Continue with Google'),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();
  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CustomPaint(painter: _GoogleLogoPainter()),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.18;
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = stroke;
    paint.color = _red;
    canvas.drawArc(rect, -2.45, 1.35, false, paint);
    paint.color = _yellow;
    canvas.drawArc(rect, 2.35, 0.98, false, paint);
    paint.color = _green;
    canvas.drawArc(rect, 1.05, 1.35, false, paint);
    paint.color = _blue;
    canvas.drawArc(rect, -0.1, 1.18, false, paint);
    final barPaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(
      center,
      Offset(size.width - stroke * 0.35, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Home: one screen with category pills and every upload
// ─────────────────────────────────────────────────────────────────────────────

class MusicShell extends StatefulWidget {
  const MusicShell({super.key});
  @override
  State<MusicShell> createState() => _MusicShellState();
}

class _MusicShellState extends State<MusicShell> {
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  StreamSubscription<String>? _launchSubscription;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    final phone = context.read<MusicController>().phone;
    _launchSubscription = phone?.launchActions.listen(_runLaunchAction);
    phone?.takeLaunchAction().then((action) {
      if (action != null) _runLaunchAction(action);
    });
    _shareSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_openSharedItems, onError: (Object _) {});
    ReceiveSharingIntent.instance.getInitialMedia().then((items) {
      _openSharedItems(items);
      ReceiveSharingIntent.instance.reset();
    }, onError: (Object _) {});
  }

  void _openSharedItems(List<SharedMediaFile> items) {
    if (!mounted || items.isEmpty) return;
    final media = [
      for (final item in items)
        if (item.type == SharedMediaType.video ||
            item.type == SharedMediaType.file)
          item.path,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (media.isEmpty) {
        final youtube = youtubeLinkIn(items.first.path);
        if (youtube != null && _webViewSupported) {
          unawaited(_openConverterSearch(youtube));
        } else {
          _push(context, SharedImportScreen(source: items.first.path));
        }
        return;
      }
      _sheet(
        context,
        title: media.length == 1
            ? 'Add shared file'
            : 'Add ${media.length} shared files',
        (sheetContext) => [
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('Upload for everyone'),
            subtitle: const Text('Choose a category and share it'),
            onTap: () {
              Navigator.pop(sheetContext);
              _push(context, UploadScreen(initialPaths: media));
            },
          ),
          if (media.length == 1)
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Keep privately'),
              subtitle: const Text('Trim it or save the original for yourself'),
              onTap: () {
                Navigator.pop(sheetContext);
                _push(
                  context,
                  OwnedMediaEditorScreen(
                    source: media.first,
                    suggestedName: _fileName(media.first),
                  ),
                );
              },
            ),
        ],
      );
    });
  }

  /// Runs a home screen widget tap. A song to play may still be loading from
  /// the catalogue cache when the app has just started.
  void _runLaunchAction(String action, [int attempt = 0]) {
    if (!mounted) return;
    final music = context.read<MusicController>();
    if (action.startsWith('play:')) {
      final song = music.songById(action.substring('play:'.length));
      if (song != null) {
        _openSong(context, song, queue: music.songs);
      } else if (attempt < 10) {
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          () => _runLaunchAction(action, attempt + 1),
        );
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      switch (action) {
        case 'player':
          if (music.current != null) _openPlayer(context);
        case 'upload':
          _push(context, const UploadScreen());
        case 'search':
          _searchRequests.value++;
        case 'browser':
          if (_webViewSupported) {
            _push(context, const NexBrowserScreen(sharedLink: ''));
          }
        case 'downloads':
          _push(
            context,
            SongListScreen(
              title: 'Downloads',
              emptyText:
                  'Tap ⋮ on a song and choose Download to play it without internet.',
              select: (music) => music.downloadedSongs,
            ),
          );
      }
    });
  }

  /// Copies a shared YouTube link and opens the in-app browser on a
  /// "youtube to mp3" search, so the link can be pasted on the site chosen.
  Future<void> _openConverterSearch(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _push(context, const NexBrowserScreen(sharedLink: 'youtube to mp3'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('YouTube link copied. Paste it on the site you open.'),
      ),
    );
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _launchSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = context.select<MusicController, String?>(
      (music) => music.notice,
    );
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final music = context.read<MusicController>();
        final message = music.notice;
        if (message == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        music.clearNotice();
      });
    }
    return Scaffold(
      body: const SafeArea(bottom: false, child: _CatalogView()),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Upload',
        onPressed: () => _push(context, const UploadScreen()),
        child: const Icon(Icons.add_rounded),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _CatalogView extends StatefulWidget {
  const _CatalogView();

  @override
  State<_CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<_CatalogView> {
  final _search = TextEditingController();
  String? _categoryId;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searchRequests.addListener(_openSearch);
  }

  void _openSearch() {
    if (mounted) setState(() => _searching = true);
  }

  @override
  void dispose() {
    _searchRequests.removeListener(_openSearch);
    _search.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final category = await _createCategory(context);
    if (!mounted || category == null) return;
    setState(() => _categoryId = category.id);
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    // A category deleted elsewhere falls back to "All".
    final selected =
        _categoryId != null && music.categoryById(_categoryId!) != null
        ? _categoryId
        : null;
    final query = _search.text.trim().toLowerCase();
    final visible = music
        .songsIn(selected)
        .where(
          (song) =>
              query.isEmpty ||
              song.title.toLowerCase().contains(query) ||
              music.categoryName(song.categoryId).toLowerCase().contains(query),
        )
        .toList();

    return Column(
      children: [
        _searching ? _searchBar() : _header(music),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            children: [
              _Pill(
                label: 'All',
                selected: selected == null,
                onTap: () => setState(() => _categoryId = null),
              ),
              for (final category in music.categories)
                _Pill(
                  label: category.name,
                  selected: selected == category.id,
                  onTap: () => setState(() => _categoryId = category.id),
                  onLongPress: () => _categoryActions(context, category),
                ),
              _Pill(
                icon: Icons.add_rounded,
                label: 'Category',
                onTap: _newCategory,
              ),
              if (music.categories.isNotEmpty)
                _Pill(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () => _push(context, const CategoryManagerScreen()),
                ),
            ],
          ),
        ),
        if (music.uploads.isNotEmpty)
          InkWell(
            onTap: () => _push(context, const UploadScreen()),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music.uploading
                        ? 'Uploading ${music.uploadsFinished} of ${music.uploads.length}'
                        : 'Uploads finished · tap to review',
                    style: TextStyle(color: _muted(context), fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: music.uploadFraction,
                    minHeight: 3,
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: _list(music, visible, query)),
      ],
    );
  }

  Widget _header(MusicController music) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'nexMusic',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Search',
          onPressed: () => setState(() => _searching = true),
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Profile',
          onPressed: () => _push(context, const ProfileScreen()),
          icon: _Avatar(initials: music.profileInitials, size: 32),
        ),
      ],
    ),
  );

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search songs or categories',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close search',
          onPressed: () => setState(() {
            _searching = false;
            _search.clear();
          }),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _list(MusicController music, List<Song> visible, String query) {
    if (!music.catalogLoaded) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: music.refreshCatalog,
      child: visible.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                _EmptyState(
                  icon: query.isEmpty
                      ? Icons.library_music_outlined
                      : Icons.search_off_rounded,
                  title: query.isEmpty ? 'No songs here yet' : 'Nothing found',
                  subtitle: query.isEmpty
                      ? 'Tap + to upload the first one.'
                      : 'Try another word.',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              itemCount: visible.length,
              itemBuilder: (context, i) =>
                  SongTile(song: visible[i], queue: visible),
            ),
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.song, required this.queue});
  final Song song;
  final List<Song> queue;

  @override
  Widget build(BuildContext context) {
    final tile = context
        .select<
          MusicController,
          ({
            bool active,
            bool playing,
            String category,
            bool offline,
            double? download,
          })
        >(
          (music) => (
            active: music.current?.id == song.id,
            playing: music.playing,
            category: music.categoryName(song.categoryId),
            offline: music.isSongDownloaded(song),
            download: music.songDownloads[song.id],
          ),
        );
    final download = tile.download;
    final details = [
      tile.category,
      if (song.isVideo) 'Video',
      if (download != null)
        'Downloading ${(download * 100).round()}%'
      else if (tile.offline)
        'Offline',
    ];
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      leading: _Thumb(
        active: tile.active,
        icon: tile.active && tile.playing
            ? Icons.graphic_eq_rounded
            : song.isVideo
            ? Icons.play_arrow_rounded
            : Icons.music_note_rounded,
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: tile.active ? NexMusicApp.violet : null,
        ),
      ),
      subtitle: Text(
        details.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _muted(context), fontSize: 12),
      ),
      trailing: IconButton(
        tooltip: 'More',
        onPressed: () => _songActions(context, song),
        icon: Icon(Icons.more_vert_rounded, color: _muted(context)),
      ),
      onTap: () => _openSong(context, song, queue: queue),
    );
  }
}

Future<void> _songActions(BuildContext context, Song song) {
  final music = context.read<MusicController>();
  final liked = music.isLiked(song);
  final downloaded = music.isSongDownloaded(song);
  final downloading = music.songDownloads.containsKey(song.id);
  return _sheet(
    context,
    title: song.title,
    (sheetContext) => [
      ListTile(
        leading: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        title: Text(liked ? 'Remove from liked' : 'Like'),
        onTap: () {
          Navigator.pop(sheetContext);
          music.toggleLike(song);
        },
      ),
      if (!kIsWeb)
        ListTile(
          enabled: !downloading,
          leading: Icon(
            downloaded ? Icons.offline_pin_rounded : Icons.download_rounded,
          ),
          title: Text(
            downloading
                ? 'Downloading…'
                : downloaded
                ? 'Remove download'
                : 'Download',
          ),
          subtitle: downloaded || downloading
              ? null
              : const Text('Play it without internet'),
          onTap: () {
            Navigator.pop(sheetContext);
            if (downloaded) {
              music.removeSongDownload(song);
            } else {
              music.downloadSong(song);
            }
          },
        ),
      // Anyone signed in can edit or delete any upload.
      ListTile(
        leading: const Icon(Icons.edit_outlined),
        title: const Text('Edit or move'),
        subtitle: const Text('Change the title or category'),
        onTap: () {
          Navigator.pop(sheetContext);
          _push(context, SongEditorScreen(song: song));
        },
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline_rounded),
        title: const Text('Delete'),
        onTap: () async {
          Navigator.pop(sheetContext);
          final confirmed = await _confirm(
            context,
            title: 'Delete "${song.title}"?',
            body: 'It will be removed for everyone.',
            action: 'Delete',
          );
          if (confirmed) await music.deleteSong(song);
        },
      ),
    ],
  );
}

Future<void> _categoryActions(
  BuildContext context,
  MusicCategory category,
) async {
  final music = context.read<MusicController>();
  if (!music.ownsCategory(category)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Only the person who created a category can change it.'),
      ),
    );
    return;
  }
  await _sheet(
    context,
    title: category.name,
    (sheetContext) => [
      ListTile(
        leading: const Icon(Icons.edit_outlined),
        title: const Text('Rename'),
        onTap: () {
          Navigator.pop(sheetContext);
          _renameCategory(context, category);
        },
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline_rounded),
        title: const Text('Delete'),
        onTap: () {
          Navigator.pop(sheetContext);
          _deleteCategory(context, category);
        },
      ),
    ],
  );
}

Future<void> _renameCategory(
  BuildContext context,
  MusicCategory category,
) async {
  final music = context.read<MusicController>();
  final name = await _nameDialog(
    context,
    title: 'Rename category',
    action: 'Save',
    initialValue: category.name,
  );
  if (name != null) await music.renameCategory(category, name);
}

Future<void> _deleteCategory(
  BuildContext context,
  MusicCategory category,
) async {
  final music = context.read<MusicController>();
  final count = music.songsIn(category.id).length;
  final songs = '$count song${count == 1 ? '' : 's'}';
  final confirmed = await _confirm(
    context,
    title: count == 0
        ? 'Delete "${category.name}"?'
        : 'Delete "${category.name}" and its $songs?',
    body: count == 0
        ? 'The category will be removed for everyone.'
        : 'The category and all $songs in it will be removed for everyone. This cannot be undone.',
    action: count == 0 ? 'Delete' : 'Delete all',
  );
  if (!confirmed || !context.mounted) return;
  if (count > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleting "${category.name}" and its $songs…')),
    );
  }
  await music.deleteCategory(category, withSongs: count > 0);
}

/// Every category with its song count. Categories this user created can be
/// renamed or deleted; the rest are read-only.
class CategoryManagerScreen extends StatelessWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<MusicController>().categories;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'New category',
            onPressed: () => _createCategory(context),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: categories.isEmpty
          ? const _EmptyState(
              icon: Icons.label_outline_rounded,
              title: 'No categories yet',
              subtitle: 'Tap + to create the first one.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              itemCount: categories.length,
              itemBuilder: (_, i) => _CategoryRow(category: categories[i]),
            ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});
  final MusicCategory category;

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicController>();
    final count = music.songsIn(category.id).length;
    final owner = music.ownsCategory(category);
    final songs = '$count song${count == 1 ? '' : 's'}';
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      title: Text(
        category.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        owner ? songs : '$songs · created by someone else',
        style: TextStyle(color: _muted(context), fontSize: 12),
      ),
      trailing: owner
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Rename',
                  onPressed: () => _renameCategory(context, category),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _deleteCategory(context, category),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: _muted(context),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload & edit
// ─────────────────────────────────────────────────────────────────────────────

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, this.initialPaths = const []});
  final List<String> initialPaths;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  late final MusicController _music;
  final _title = TextEditingController();
  final List<UploadItem> _picked = [];
  final List<String> _rejected = [];
  String? _categoryId;
  bool _rights = false;

  @override
  void initState() {
    super.initState();
    _music = context.read<MusicController>();
    for (final filePath in widget.initialPaths) {
      final file = File(filePath);
      _add(
        filePath,
        _fileName(filePath),
        !kIsWeb && file.existsSync() ? file.lengthSync() : 0,
      );
    }
    if (_picked.length == 1) _title.text = _picked.first.title;
  }

  @override
  void dispose() {
    // Picked files that were never uploaded leave copies in the cache. Clear
    // them only when no upload batch still needs its files.
    if (_picked.isNotEmpty && _music.uploads.isEmpty) {
      for (final item in _picked) {
        _music.discardPicked(item);
      }
      try {
        unawaited(FilePicker.clearTemporaryFiles().catchError((Object _) {}));
      } catch (_) {}
    }
    _title.dispose();
    super.dispose();
  }

  /// Adds a picked file, or notes why it cannot be uploaded.
  void _add(String filePath, String name, int sizeBytes) {
    if (_picked.any((item) => item.path == filePath)) return;
    final reason = uploadKindFor(name) == null
        ? 'file type not supported'
        : sizeBytes >= maxUploadBytes
        ? 'larger than 100 MB'
        // A size of -1 means the phone did not report one.
        : sizeBytes == 0
        ? 'empty or unreadable'
        : null;
    if (reason != null) {
      _rejected.add('$name · $reason');
      return;
    }
    final title = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    _picked.add(
      UploadItem(
        path: filePath,
        name: name,
        sizeBytes: sizeBytes,
        title: title.length > 160 ? title.substring(0, 160) : title,
      ),
    );
  }

  static Future<int> _sizeOf(
    int? Function() known,
    Future<int> Function() read,
  ) async {
    try {
      return known() ?? await read();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _pickFiles() async {
    // Android: the native chooser returns content URIs and copies nothing, so
    // choosing hundreds of songs does not fill the phone (file_picker copied
    // every file up front and Android deleted some before they uploaded).
    final chosen = await _music.phone?.pickMedia();
    if (chosen != null) {
      if (!mounted || chosen.isEmpty) return;
      setState(() {
        _rejected.clear();
        for (final file in chosen) {
          _add(file.uri, file.name, file.size);
        }
        if (_picked.length == 1) _title.text = _picked.first.title;
      });
      return;
    }
    // Elsewhere, filter by media type, not extension: file_picker turns
    // extensions into exact MIME types (m4a → audio/mp4), and phones that
    // label a file differently (audio/x-m4a) grey it out. _add rejects the
    // rest.
    final files = await FilePicker.pickFiles(type: FileType.media);
    if (!mounted || files.isEmpty) return;
    final sizes = await Future.wait([
      for (final file in files) _sizeOf(file.lengthSync, file.length),
    ]);
    if (!mounted) return;
    setState(() {
      _rejected.clear();
      for (var i = 0; i < files.length; i++) {
        final filePath = files[i].path;
        if (filePath == null) {
          _rejected.add('${files[i].name} · could not be read');
        } else {
          _add(filePath, files[i].name, sizes[i]);
        }
      }
      if (_picked.length == 1) _title.text = _picked.first.title;
    });
  }

  void _remove(UploadItem item) => setState(() {
    _music.discardPicked(item);
    _picked.remove(item);
    if (_picked.length == 1) _title.text = _picked.first.title;
  });

  void _clear() => setState(() {
    for (final item in _picked) {
      _music.discardPicked(item);
    }
    _picked.clear();
    _rejected.clear();
    _title.clear();
  });

  Future<void> _trim(UploadItem item) async {
    if (_picked.length == 1) item.title = _title.text;
    final trimmed = await _trimUpload(context, item);
    if (trimmed && mounted) setState(() {});
  }

  void _undoTrim(UploadItem item) {
    final trimmedCopy = item.undoTrim();
    if (trimmedCopy != null) discardTemporaryCopy(trimmedCopy);
    setState(() {});
  }

  void _upload() {
    final categoryId = _categoryId;
    if (categoryId == null || _picked.isEmpty) return;
    if (_picked.length == 1) _picked.first.title = _title.text;
    final items = List.of(_picked);
    unawaited(_music.startUploads(items, categoryId: categoryId));
    // The batch is queued synchronously; keep the selection if it was refused.
    if (_music.uploads.isNotEmpty &&
        identical(_music.uploads.first, items.first)) {
      setState(() {
        _picked.clear();
        _rejected.clear();
        _rights = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    return music.uploads.isEmpty
        ? _pickerView(music)
        : _progressView(music);
  }

  Widget _pickerView(MusicController music) {
    final muted = _muted(context);
    final error = Theme.of(context).colorScheme.error;
    final count = _picked.length;
    final totalBytes = _picked.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final ready =
        count > 0 &&
        music.categories.any((category) => category.id == _categoryId) &&
        _rights &&
        (count > 1 || _title.text.trim().isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _FileBox(
            title: count == 0
                ? 'Choose songs or videos'
                : '$count file${count == 1 ? '' : 's'} · ${_fileSize(totalBytes)}',
            detail: count == 0
                ? 'Pick one or many · up to 100 MB each'
                : 'Tap to add more',
            onTap: _pickFiles,
            onClear: count == 0 ? null : _clear,
          ),
          for (final reason in _rejected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(reason, style: TextStyle(color: error, fontSize: 12)),
            ),
          if (count == 1) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              maxLength: 160,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Title',
                counterText: '',
              ),
            ),
            if (_canTrim && uploadKindFor(_picked.first.name) == 'audio') ...[
              const SizedBox(height: 12),
              _TrimRow(
                item: _picked.first,
                onTrim: () => _trim(_picked.first),
                onUndo: () => _undoTrim(_picked.first),
              ),
            ],
          ] else if (count > 1) ...[
            const SizedBox(height: 8),
            for (final item in _picked.take(50))
              _PickedRow(
                item: item,
                onRemove: () => _remove(item),
                onTrim: _canTrim && uploadKindFor(item.name) == 'audio'
                    ? () => _trim(item)
                    : null,
              ),
            if (count > 50)
              Text(
                '+ ${count - 50} more',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            const SizedBox(height: 4),
            Text(
              'Titles come from the file names. You can edit them after uploading.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          _ChoicePicker(
            label: 'Category',
            options: [
              for (final category in music.categories)
                (id: category.id, name: category.name),
            ],
            selectedId: _categoryId,
            onChanged: (id) => setState(() => _categoryId = id),
            onCreate: () async => (await _createCategory(context))?.id,
            createLabel: 'New category',
            onManage: () => _push(context, const CategoryManagerScreen()),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _rights,
            onChanged: (value) => setState(() => _rights = value ?? false),
            title: const Text(
              'I have the right to share this publicly',
              style: TextStyle(fontSize: 14),
            ),
          ),
          if (!music.uploadsConfigured)
            Text(
              'Uploads are not set up yet (Cloudinary).',
              style: TextStyle(color: error, fontSize: 12),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: ready ? _upload : null,
            child: Text(count > 1 ? 'Upload $count files' : 'Upload'),
          ),
          const SizedBox(height: 12),
          Text(
            'Everyone signed in to nexMusic can play your uploads.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _progressView(MusicController music) {
    final uploads = music.uploads;
    final uploading = music.uploading;
    final failed = music.uploadsFailed;
    int count(UploadStatus status) =>
        uploads.where((item) => item.status == status).length;
    final summary = [
      '${count(UploadStatus.done)} uploaded',
      if (count(UploadStatus.skipped) > 0)
        '${count(UploadStatus.skipped)} already in nexMusic',
      if (failed > 0) '$failed failed',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(uploading ? 'Uploading' : 'Upload finished')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${music.uploadsFinished} of ${uploads.length} done',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: music.uploadFraction,
                  minHeight: 4,
                ),
                const SizedBox(height: 8),
                Text(
                  uploading
                      ? 'Keep nexMusic open until the uploads finish.'
                      : summary,
                  style: TextStyle(color: _muted(context), fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: uploads.length,
              itemBuilder: (_, i) => _UploadRow(item: uploads[i]),
            ),
          ),
        ],
      ),
      // In the bottom bar, snackbars float above the buttons instead of
      // covering them.
      bottomNavigationBar: uploading
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    if (failed > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: music.retryFailedUploads,
                          child: Text('Retry failed ($failed)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          music.clearUploads();
                          Navigator.pop(context);
                        },
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _FileBox extends StatelessWidget {
  const _FileBox({
    required this.title,
    required this.detail,
    required this.onTap,
    this.onClear,
  });
  final String title, detail;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Icon(
                onClear == null
                    ? Icons.upload_file_rounded
                    : Icons.library_music_outlined,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear selection',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickedRow extends StatelessWidget {
  const _PickedRow({required this.item, required this.onRemove, this.onTrim});
  final UploadItem item;
  final VoidCallback onRemove;
  final VoidCallback? onTrim;

  @override
  Widget build(BuildContext context) {
    final start = item.trimStart, end = item.trimEnd;
    return Row(
      children: [
        Expanded(
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text(
          start != null && end != null
              ? '${_time(start)}–${_time(end)}'
              : _fileSize(item.sizeBytes),
          style: TextStyle(
            color: item.trimmed ? NexMusicApp.violet : _muted(context),
            fontSize: 12,
          ),
        ),
        if (onTrim != null)
          IconButton(
            tooltip: item.trimmed ? 'Trim again' : 'Trim',
            visualDensity: VisualDensity.compact,
            onPressed: onTrim,
            icon: Icon(
              Icons.content_cut_rounded,
              size: 18,
              color: item.trimmed ? NexMusicApp.violet : null,
            ),
          ),
        IconButton(
          tooltip: 'Remove',
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    );
  }
}

class _TrimRow extends StatelessWidget {
  const _TrimRow({
    required this.item,
    required this.onTrim,
    required this.onUndo,
  });
  final UploadItem item;
  final VoidCallback onTrim, onUndo;

  @override
  Widget build(BuildContext context) {
    final start = item.trimStart, end = item.trimEnd;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTrim,
            icon: const Icon(Icons.content_cut_rounded, size: 18),
            label: Text(
              start == null || end == null
                  ? 'Trim audio'
                  : 'Trimmed ${_time(start)} – ${_time(end)}',
            ),
          ),
        ),
        if (item.trimmed) ...[
          const SizedBox(width: 8),
          TextButton(onPressed: onUndo, child: const Text('Undo')),
        ],
      ],
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.item});
  final UploadItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Widget icon, String status) = switch (item.status) {
      UploadStatus.queued => (
        Icon(Icons.schedule_rounded, color: scheme.onSurfaceVariant),
        'Waiting',
      ),
      UploadStatus.uploading => (
        SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: item.progress,
          ),
        ),
        '${(item.progress * 100).round()}%',
      ),
      UploadStatus.done => (
        const Icon(Icons.check_circle_rounded, color: NexMusicApp.violet),
        'Uploaded',
      ),
      UploadStatus.skipped => (
        Icon(Icons.remove_circle_outline_rounded, color: scheme.onSurfaceVariant),
        'Already in nexMusic',
      ),
      UploadStatus.failed => (
        Icon(Icons.error_outline_rounded, color: scheme.error),
        'Failed · ${item.error ?? 'unknown error'}',
      ),
    };
    return ListTile(
      dense: true,
      leading: SizedBox(width: 28, child: Center(child: icon)),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$status · ${_fileSize(item.sizeBytes)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: item.status == UploadStatus.failed
              ? scheme.error
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Picks the part of a song to keep: play it and tap "Start here" and
/// "End here", or drag the handles.
class TrimScreen extends StatefulWidget {
  const TrimScreen({
    super.key,
    required this.source,
    required this.title,
    this.start,
    this.end,
  });
  final String source, title;
  final Duration? start, end;

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  static const _minimum = Duration(seconds: 1);
  final _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  Duration _duration = Duration.zero, _position = Duration.zero;
  late Duration _start = widget.start ?? Duration.zero;
  Duration? _end;
  bool _playing = false, _saving = false;
  String? _error;

  Duration get _selectionEnd => _end ?? _duration;

  @override
  void initState() {
    super.initState();
    context.read<MusicController>().pauseAudio();
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) return;
      // The preview stops at the end of the selection.
      if (_player.playing && position >= _selectionEnd) _player.pause();
      setState(() => _position = position);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(
        () => _playing =
            state.playing &&
            state.processingState != ProcessingState.completed,
      );
    });
    _load();
  }

  Future<void> _load() async {
    try {
      // Files from the native chooser are content URIs, not paths.
      final length = widget.source.startsWith('content://')
          ? await _player.setUrl(widget.source)
          : await _player.setFilePath(widget.source);
      if (!mounted) return;
      if (length == null || length <= _minimum) {
        throw StateError('Unknown length');
      }
      final end = widget.end;
      setState(() {
        _duration = length;
        _end = end != null && end <= length ? end : length;
        if (_start + _minimum > _selectionEnd) _start = Duration.zero;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'This file could not be opened for trimming.');
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_position < _start || _position >= _selectionEnd) {
      await _player.seek(_start);
    }
    unawaited(_player.play());
  }

  void _setStart() {
    final latest = _selectionEnd - _minimum;
    setState(() => _start = _position > latest ? latest : _position);
  }

  void _setEnd() {
    final earliest = _start + _minimum;
    final value = _position < earliest ? earliest : _position;
    setState(() => _end = value > _duration ? _duration : value);
  }

  Future<void> _save() async {
    final end = _end;
    if (end == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await _player.pause();
    try {
      final path = await _mediaTools.invokeMethod<String>(
        'extractAndTrimAudio',
        {
          'source': widget.source,
          'startMs': _start.inMilliseconds,
          'endMs': end.inMilliseconds,
        },
      );
      if (path == null) throw StateError('No trimmed file');
      if (!mounted) {
        discardTemporaryCopy(path);
        return;
      }
      Navigator.pop(context, (path: path, start: _start, end: end));
    } catch (error) {
      // The native reason ends up in logcat for debugging.
      debugPrint('Trim failed: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'This phone could not trim this audio. Upload it without trimming instead.';
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = _muted(context);
    final ready = _end != null;
    final end = _selectionEnd;
    final small = TextStyle(color: muted, fontSize: 12);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trim'),
        actions: [
          if (ready)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _start = Duration.zero;
                      _end = _duration;
                    }),
              child: const Text('Reset'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _error ??
                (ready
                    ? 'Keeping ${_time(_start)} – ${_time(end)} · ${_time(end - _start)} long'
                    : 'Loading…'),
            style: TextStyle(
              color: _error == null
                  ? muted
                  : Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
          ),
          if (ready) ...[
            const SizedBox(height: 28),
            RangeSlider(
              values: RangeValues(
                _start.inMilliseconds.toDouble(),
                end.inMilliseconds.toDouble(),
              ),
              max: math.max(1, _duration.inMilliseconds).toDouble(),
              onChanged: _saving
                  ? null
                  : (values) {
                      if (values.end - values.start <
                          _minimum.inMilliseconds) {
                        return;
                      }
                      setState(() {
                        _start = Duration(milliseconds: values.start.round());
                        _end = Duration(milliseconds: values.end.round());
                      });
                    },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(_time(_start), style: small),
                  const Spacer(),
                  Text('Now ${_time(_position)}', style: small),
                  const Spacer(),
                  Text(_time(end), style: small),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: SizedBox.square(
                dimension: 72,
                child: IconButton.filled(
                  tooltip: _playing ? 'Pause' : 'Play selection',
                  iconSize: 36,
                  style: IconButton.styleFrom(
                    backgroundColor: NexMusicApp.violet,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _saving ? null : _togglePlay,
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _setStart,
                    child: const Text('Start here'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _setEnd,
                    child: const Text('End here'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Play the song and tap Start here and End here, or drag the handles.',
              textAlign: TextAlign.center,
              style: small,
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: ready && !_saving ? _save : null,
            child: Text(_saving ? 'Trimming…' : 'Use this part'),
          ),
        ),
      ),
    );
  }
}

class SongEditorScreen extends StatefulWidget {
  const SongEditorScreen({super.key, required this.song});
  final Song song;

  @override
  State<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends State<SongEditorScreen> {
  late final _title = TextEditingController(text: widget.song.title);
  late String _categoryId = widget.song.categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final music = context.read<MusicController>();
    setState(() => _saving = true);
    final saved = await music.updateSong(
      widget.song,
      title: _title.text,
      categoryId: _categoryId,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.select<MusicController, List<MusicCategory>>(
      (music) => music.categories,
    );
    final valid =
        _title.text.trim().isNotEmpty &&
        categories.any((category) => category.id == _categoryId);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit song')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _title,
            maxLength: 160,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Title',
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),
          _ChoicePicker(
            label: 'Category',
            options: [
              for (final category in categories)
                (id: category.id, name: category.name),
            ],
            selectedId: _categoryId,
            onChanged: (id) => setState(() => _categoryId = id),
            onCreate: () async => (await _createCategory(context))?.id,
            createLabel: 'New category',
            onManage: () => _push(context, const CategoryManagerScreen()),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: valid && !_saving ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Players
// ─────────────────────────────────────────────────────────────────────────────

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context
        .select<
          MusicController,
          ({
            Song? song,
            bool playing,
            bool loading,
            Duration duration,
            String category,
          })
        >(
          (music) => (
            song: music.current,
            playing: music.playing,
            loading: music.loading,
            duration: music.duration,
            category: music.current == null || music.current!.isPrivate
                ? 'Private library'
                : music.categoryName(music.current!.categoryId),
          ),
        );
    final song = state.song;
    if (song == null) return const SizedBox.shrink();
    final music = context.read<MusicController>();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<Duration>(
              valueListenable: music.positionListenable,
              builder: (_, position, _) {
                final total = state.duration.inMilliseconds;
                final value = total <= 0
                    ? 0.0
                    : (position.inMilliseconds / total).clamp(0.0, 1.0);
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 2,
                  backgroundColor: scheme.outlineVariant,
                );
              },
            ),
            InkWell(
              onTap: () => _openPlayer(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            state.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: state.playing ? 'Pause' : 'Play',
                      onPressed: music.togglePlay,
                      icon: state.loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              state.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: music.next,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context
        .select<
          MusicController,
          ({
            Song? song,
            bool playing,
            bool loading,
            bool shuffle,
            bool repeat,
            bool liked,
            Duration duration,
            String category,
          })
        >((music) {
          final song = music.current;
          return (
            song: song,
            playing: music.playing,
            loading: music.loading,
            shuffle: music.shuffle,
            repeat: music.repeat,
            liked: song != null && music.isLiked(song),
            duration: music.duration,
            category: song == null || song.isPrivate
                ? 'Private library'
                : music.categoryName(song.categoryId),
          );
        });
    final music = context.read<MusicController>();
    final song = state.song;
    final muted = _muted(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        centerTitle: true,
        title: Text(
          'Now playing',
          style: TextStyle(fontSize: 14, color: muted),
        ),
      ),
      body: song == null
          ? const _EmptyState(
              icon: Icons.music_off_rounded,
              title: 'Nothing playing',
              subtitle: 'Pick a song to start listening.',
            )
          : SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final art = math
                      .min(
                        constraints.maxWidth - 48,
                        constraints.maxHeight * 0.4,
                      )
                      .clamp(96.0, 340.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 32),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Thumb(icon: Icons.music_note_rounded, size: art),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      state.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              if (!song.isPrivate)
                                IconButton(
                                  tooltip: state.liked ? 'Unlike' : 'Like',
                                  onPressed: () => music.toggleLike(song),
                                  icon: Icon(
                                    state.liked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: state.liked
                                        ? NexMusicApp.violet
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<Duration>(
                            valueListenable: music.positionListenable,
                            builder: (context, position, _) {
                              final max = math
                                  .max(1, state.duration.inMilliseconds)
                                  .toDouble();
                              final value = position.inMilliseconds
                                  .clamp(0, max.toInt())
                                  .toDouble();
                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      overlayShape:
                                          SliderComponentShape.noOverlay,
                                    ),
                                    child: Slider(
                                      value: value,
                                      max: max,
                                      onChanged: (next) => music.seek(
                                        Duration(milliseconds: next.round()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        _time(position),
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _time(state.duration),
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                tooltip: 'Shuffle',
                                onPressed: music.toggleShuffle,
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: state.shuffle
                                      ? NexMusicApp.violet
                                      : muted,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Previous',
                                iconSize: 32,
                                onPressed: music.previous,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                              SizedBox.square(
                                dimension: 64,
                                child: IconButton.filled(
                                  tooltip: state.playing ? 'Pause' : 'Play',
                                  iconSize: 32,
                                  style: IconButton.styleFrom(
                                    backgroundColor: NexMusicApp.violet,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: music.togglePlay,
                                  icon: state.loading
                                      ? const SizedBox.square(
                                          dimension: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          state.playing
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next',
                                iconSize: 32,
                                onPressed: music.next,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                              IconButton(
                                tooltip: 'Repeat',
                                onPressed: music.toggleRepeat,
                                icon: Icon(
                                  state.repeat
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                  color: state.repeat
                                      ? NexMusicApp.violet
                                      : muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.song});
  final Song song;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _video;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    context.read<MusicController>().pauseAudio();
    final url = widget.song.url;
    _video = url.startsWith('file:')
        ? VideoPlayerController.file(File.fromUri(Uri.parse(url)))
        : VideoPlayerController.networkUrl(Uri.parse(url));
    _video.addListener(_refresh);
    // Streaming formats are not bundled with the app, see isStreamingLink.
    _failed = isStreamingLink(url);
    if (!_failed) _start();
  }

  Future<void> _start() async {
    try {
      await _video.initialize();
      await _video.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toggle() => _video.value.isPlaying ? _video.pause() : _video.play();

  @override
  void dispose() {
    _video.removeListener(_refresh);
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _video.value;
    final failed = _failed || value.hasError;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: failed
                    ? const Text(
                        'This video could not be played.',
                        style: TextStyle(color: Colors.white70),
                      )
                    : !value.isInitialized
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : GestureDetector(
                        onTap: _toggle,
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_video),
                              if (!value.isPlaying)
                                const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 64,
                                  color: Colors.white70,
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (value.isInitialized && !failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      color: Colors.white,
                      onPressed: _toggle,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        _video,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        colors: const VideoProgressColors(
                          playedColor: NexMusicApp.violet,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_time(value.position)} / ${_time(value.duration)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile & lists
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                _Avatar(initials: music.profileInitials, size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music.profileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (music.profileEmail.isNotEmpty)
                        Text(
                          music.profileEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted(context), fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _NavRow(
            icon: Icons.cloud_upload_outlined,
            title: 'My uploads',
            trailing: '${music.myUploads.length}',
            onTap: () => _push(
              context,
              SongListScreen(
                title: 'My uploads',
                emptyText: 'Songs and videos you upload show up here.',
                select: (music) => music.myUploads,
              ),
            ),
          ),
          _NavRow(
            icon: Icons.favorite_border_rounded,
            title: 'Liked',
            trailing: '${music.likedSongs.length}',
            onTap: () => _push(
              context,
              SongListScreen(
                title: 'Liked',
                emptyText: 'Tap ⋮ on any song and choose Like.',
                select: (music) => music.likedSongs,
              ),
            ),
          ),
          _NavRow(
            icon: Icons.history_rounded,
            title: 'Recently played',
            onTap: () => _push(
              context,
              SongListScreen(
                title: 'Recently played',
                emptyText: 'Songs you play show up here.',
                select: (music) => music.recentSongs,
              ),
            ),
          ),
          if (!kIsWeb)
            _NavRow(
              icon: Icons.download_done_rounded,
              title: 'Downloads',
              trailing: '${music.downloadedSongs.length}',
              onTap: () => _push(
                context,
                SongListScreen(
                  title: 'Downloads',
                  emptyText:
                      'Tap ⋮ on a song and choose Download to play it without internet.',
                  select: (music) => music.downloadedSongs,
                ),
              ),
            ),
          const Divider(),
          _NavRow(
            icon: Icons.lock_outline_rounded,
            title: 'Private library',
            trailing: '${music.savedMedia.length}',
            onTap: () => _push(context, const PrivateLibraryScreen()),
          ),
          if (_webViewSupported)
            _NavRow(
              icon: Icons.language_rounded,
              title: 'Browser',
              onTap: () =>
                  _push(context, const NexBrowserScreen(sharedLink: '')),
            ),
          const Divider(),
          if (music.phone != null)
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Activity notifications'),
              subtitle: const Text('When someone uploads, edits or deletes'),
              value: music.pushEnabled,
              onChanged: music.setPushEnabled,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            value: music.darkMode,
            onChanged: music.setDarkMode,
          ),
          _NavRow(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            showChevron: false,
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              music.signOut();
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'nexMusic 0.2.0',
              style: TextStyle(color: _muted(context), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class SongListScreen extends StatelessWidget {
  const SongListScreen({
    super.key,
    required this.title,
    required this.emptyText,
    required this.select,
  });
  final String title, emptyText;
  final List<Song> Function(MusicController music) select;

  @override
  Widget build(BuildContext context) {
    final songs = context.select<MusicController, List<Song>>(select);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: songs.isEmpty
          ? _EmptyState(
              icon: Icons.music_note_outlined,
              title: 'Nothing here yet',
              subtitle: emptyText,
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: songs.length,
              itemBuilder: (_, i) => SongTile(song: songs[i], queue: songs),
            ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private library
// ─────────────────────────────────────────────────────────────────────────────

class PrivateLibraryScreen extends StatefulWidget {
  const PrivateLibraryScreen({super.key});

  @override
  State<PrivateLibraryScreen> createState() => _PrivateLibraryScreenState();
}

class _PrivateLibraryScreenState extends State<PrivateLibraryScreen> {
  String? _folderId;

  Future<void> _newFolder() async {
    final folder = await _createFolder(context);
    if (!mounted || folder == null) return;
    setState(() => _folderId = folder.id);
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final folders = music.mediaFolders;
    final selected = folders.any((folder) => folder.id == _folderId)
        ? _folderId
        : null;
    final items = selected == null
        ? music.savedMedia
        : music.savedMedia.where((item) => item.folderId == selected).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private library'),
        actions: [
          IconButton(
            tooltip: 'Add',
            onPressed: () => _showImportMenu(context),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              children: [
                _Pill(
                  label: 'All',
                  selected: selected == null,
                  onTap: () => setState(() => _folderId = null),
                ),
                for (final folder in folders)
                  _Pill(
                    label: folder.name,
                    selected: selected == folder.id,
                    onTap: () => setState(() => _folderId = folder.id),
                    onLongPress: () => _folderActions(context, folder),
                  ),
                _Pill(
                  icon: Icons.add_rounded,
                  label: 'Folder',
                  onTap: _newFolder,
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const _EmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'Nothing saved yet',
                    subtitle:
                        'Save links or keep your own files here. Only you can see them.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _PrivateTile(item: items[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _PrivateTile extends StatelessWidget {
  const _PrivateTile({required this.item});
  final SavedMedia item;

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicController>();
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      leading: _Thumb(icon: _mediaIcon(item)),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        _mediaSubtitle(music, item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _muted(context), fontSize: 12),
      ),
      trailing: IconButton(
        tooltip: 'More',
        onPressed: () => _privateActions(context, item),
        icon: Icon(Icons.more_vert_rounded, color: _muted(context)),
      ),
      onTap: () => _openPrivate(context, item),
    );
  }
}

Future<void> _openPrivate(BuildContext context, SavedMedia item) async {
  if (item.kind == 'link') {
    final url = item.sourceUrl;
    if (url == null) return;
    if (_webViewSupported) {
      _push(context, NexBrowserScreen(sharedLink: url));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied.')));
    return;
  }
  final song = await context.read<MusicController>().privateSong(item);
  if (song == null || !context.mounted) return;
  _openSong(context, song, queue: [song]);
}

Future<void> _privateActions(BuildContext context, SavedMedia item) {
  final music = context.read<MusicController>();
  final downloaded = music.isDownloaded(item);
  return _sheet(
    context,
    title: item.title,
    (sheetContext) => [
      ListTile(
        leading: const Icon(Icons.edit_outlined),
        title: const Text('Edit or move'),
        onTap: () {
          Navigator.pop(sheetContext);
          _push(context, SavedMediaEditorScreen(item: item));
        },
      ),
      if (item.storagePath != null && !downloaded && !kIsWeb)
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: const Text('Download offline'),
          onTap: () {
            Navigator.pop(sheetContext);
            music.downloadMedia(item);
          },
        ),
      if (downloaded)
        ListTile(
          leading: const Icon(Icons.offline_pin_outlined),
          title: const Text('Remove offline copy'),
          onTap: () {
            Navigator.pop(sheetContext);
            music.removeDownload(item);
          },
        ),
      ListTile(
        leading: const Icon(Icons.delete_outline_rounded),
        title: const Text('Delete'),
        onTap: () async {
          Navigator.pop(sheetContext);
          final confirmed = await _confirm(
            context,
            title: 'Delete "${item.title}"?',
            body: item.storagePath == null
                ? 'This saved link will be removed.'
                : 'The cloud file and any offline copy will be removed.',
            action: 'Delete',
          );
          if (confirmed) await music.deleteMedia(item);
        },
      ),
    ],
  );
}

Future<void> _folderActions(BuildContext context, MediaFolder folder) {
  final music = context.read<MusicController>();
  final count = music.savedMedia
      .where((item) => item.folderId == folder.id)
      .length;
  final lastFolder = music.mediaFolders.length <= 1;
  return _sheet(
    context,
    title: folder.name,
    (sheetContext) => [
      ListTile(
        leading: const Icon(Icons.drive_file_rename_outline_rounded),
        title: const Text('Rename'),
        onTap: () async {
          Navigator.pop(sheetContext);
          final name = await _nameDialog(
            context,
            title: 'Rename folder',
            action: 'Save',
            initialValue: folder.name,
          );
          if (name != null) await music.updateMediaFolder(folder, name);
        },
      ),
      ListTile(
        enabled: count == 0 && !lastFolder,
        leading: const Icon(Icons.delete_outline_rounded),
        title: const Text('Delete'),
        subtitle: Text(
          count > 0
              ? 'Move its $count item(s) first'
              : lastFolder
              ? 'Keep at least one folder'
              : 'Folder is empty',
        ),
        onTap: () async {
          Navigator.pop(sheetContext);
          final confirmed = await _confirm(
            context,
            title: 'Delete "${folder.name}"?',
            body: 'This folder will be removed.',
            action: 'Delete',
          );
          if (confirmed) await music.deleteMediaFolder(folder);
        },
      ),
    ],
  );
}

void _showImportMenu(BuildContext context) {
  _sheet(
    context,
    title: 'Add to private library',
    (sheetContext) => [
      ListTile(
        leading: const Icon(Icons.link_rounded),
        title: const Text('Save a link'),
        subtitle: const Text('YouTube or any web page'),
        onTap: () {
          Navigator.pop(sheetContext);
          _push(context, const SharedImportScreen(source: ''));
        },
      ),
      ListTile(
        leading: const Icon(Icons.content_cut_rounded),
        title: const Text('Keep my own file'),
        subtitle: const Text('Trim audio or save the original privately'),
        onTap: () async {
          Navigator.pop(sheetContext);
          // Media types instead of extensions, as in UploadScreen._pickFiles.
          final file = await FilePicker.pickFile(type: FileType.media);
          final source = file?.path;
          if (!context.mounted || file == null || source == null) return;
          if (uploadKindFor(file.name) == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Choose an audio or video file.')),
            );
            return;
          }
          _push(
            context,
            OwnedMediaEditorScreen(source: source, suggestedName: file.name),
          );
        },
      ),
    ],
  );
}

class SharedImportScreen extends StatefulWidget {
  const SharedImportScreen({super.key, required this.source});
  final String source;

  @override
  State<SharedImportScreen> createState() => _SharedImportScreenState();
}

class _SharedImportScreenState extends State<SharedImportScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  String? _folderId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final incoming = widget.source.trim();
    final url =
        RegExp(r'https?://\S+')
            .firstMatch(incoming)
            ?.group(0)
            ?.replaceAll(RegExp(r'[),.]+$'), '') ??
        incoming;
    _urlController = TextEditingController(text: url);
    _titleController = TextEditingController(
      text: incoming.isEmpty ? '' : 'Shared video',
    );
    if (incoming.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInBrowser());
    }
  }

  Future<void> _openInBrowser() async {
    final value = _urlController.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid web link first.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    if (_webViewSupported) {
      _push(context, NexBrowserScreen(sharedLink: value));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied. The browser is available on mobile.'),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveLink() async {
    final folderId = _folderId;
    if (_urlController.text.trim().isEmpty || folderId == null) return;
    setState(() => _saving = true);
    final saved = await context.read<MusicController>().saveSharedLink(
      url: _urlController.text.trim(),
      title: _titleController.text.trim(),
      folderId: folderId,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.select<MusicController, List<MediaFolder>>(
      (music) => music.mediaFolders,
    );
    final folderValid = folders.any((folder) => folder.id == _folderId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save link'),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Link'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 20),
          _ChoicePicker(
            label: 'Folder',
            options: [
              for (final folder in folders) (id: folder.id, name: folder.name),
            ],
            selectedId: _folderId,
            onChanged: (id) => setState(() => _folderId = id),
            onCreate: () async => (await _createFolder(context))?.id,
            createLabel: 'New folder',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || !folderValid ? null : _saveLink,
            child: Text(_saving ? 'Saving…' : 'Save link'),
          ),
        ],
      ),
    );
  }
}

class SavedMediaEditorScreen extends StatefulWidget {
  const SavedMediaEditorScreen({super.key, required this.item});
  final SavedMedia item;

  @override
  State<SavedMediaEditorScreen> createState() => _SavedMediaEditorScreenState();
}

class _SavedMediaEditorScreenState extends State<SavedMediaEditorScreen> {
  late final _titleController = TextEditingController(text: widget.item.title);
  late final _urlController = TextEditingController(
    text: widget.item.sourceUrl ?? '',
  );
  late String _folderId = widget.item.folderId;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final music = context.read<MusicController>();
    setState(() => _saving = true);
    final saved = await music.updateMedia(
      widget.item,
      title: _titleController.text,
      folderId: _folderId,
      sourceUrl: widget.item.kind == 'link' ? _urlController.text : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.select<MusicController, List<MediaFolder>>(
      (music) => music.mediaFolders,
    );
    final isLink = widget.item.kind == 'link';
    final folderValid = folders.any((folder) => folder.id == _folderId);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          if (isLink) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link'),
            ),
          ],
          const SizedBox(height: 20),
          _ChoicePicker(
            label: 'Folder',
            options: [
              for (final folder in folders) (id: folder.id, name: folder.name),
            ],
            selectedId: _folderId,
            onChanged: (id) => setState(() => _folderId = id),
            onCreate: () async => (await _createFolder(context))?.id,
            createLabel: 'New folder',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || !folderValid ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class OwnedMediaEditorScreen extends StatefulWidget {
  const OwnedMediaEditorScreen({
    super.key,
    required this.source,
    required this.suggestedName,
  });
  final String source, suggestedName;

  @override
  State<OwnedMediaEditorScreen> createState() => _OwnedMediaEditorScreenState();
}

class _OwnedMediaEditorScreenState extends State<OwnedMediaEditorScreen> {
  static const _mediaChannel = _mediaTools;
  final _preview = AudioPlayer();
  late final TextEditingController _titleController;
  StreamSubscription<Duration>? _positionSub;
  double _durationSeconds = 180, _startSeconds = 0, _endSeconds = 30;
  String? _folderId, _error;
  bool _permitted = false, _processing = false, _previewing = false;

  @override
  void initState() {
    super.initState();
    final baseName = widget.suggestedName.replaceAll(RegExp(r'\.[^.]+$'), '');
    _titleController = TextEditingController(text: baseName);
    _positionSub = _preview.positionStream.listen((position) {
      if (position.inMilliseconds >= _endSeconds * 1000 && _preview.playing) {
        _preview.pause();
        if (mounted) setState(() => _previewing = false);
      }
    });
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final foundDuration = await _preview.setUrl(widget.source);
      if (!mounted || foundDuration == null) return;
      setState(() {
        _durationSeconds = math.max(1, foundDuration.inMilliseconds / 1000);
        _endSeconds = math.min(_durationSeconds, 30);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Preview unavailable; extraction may still work on Android.',
        );
      }
    }
  }

  Future<void> _togglePreview() async {
    if (_preview.playing) {
      await _preview.pause();
      if (!mounted) return;
      setState(() => _previewing = false);
      return;
    }
    await _preview.seek(Duration(milliseconds: (_startSeconds * 1000).round()));
    if (!mounted) return;
    _preview.play();
    setState(() => _previewing = true);
  }

  Future<void> _processAndSave() async {
    final folderId = _folderId;
    if (!_permitted || folderId == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await _preview.pause();
      final exportPath = await _mediaChannel
          .invokeMethod<String>('extractAndTrimAudio', {
            'source': widget.source,
            'startMs': (_startSeconds * 1000).round(),
            'endMs': (_endSeconds * 1000).round(),
          });
      if (exportPath == null) throw StateError('No export was created.');
      if (!mounted) return;
      final uploaded = await context.read<MusicController>().uploadOwnedAudio(
        filePath: exportPath,
        title: _titleController.text.trim().isEmpty
            ? 'Imported audio'
            : _titleController.text.trim(),
        folderId: folderId,
      );
      if (mounted && uploaded) Navigator.pop(context);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _uploadOriginal() async {
    final folderId = _folderId;
    if (!_permitted || folderId == null) return;
    final ext = widget.suggestedName.split('.').last.toLowerCase();
    final isVideo = const {'mp4', 'mov'}.contains(ext);
    final contentType = switch (ext) {
      'mov' => 'video/quicktime',
      'mp4' => 'video/mp4',
      'mp3' => 'audio/mpeg',
      'aac' => 'audio/aac',
      _ => 'audio/mp4',
    };
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await _preview.pause();
      if (!mounted) return;
      final uploaded = await context.read<MusicController>().uploadOwnedMedia(
        filePath: widget.source,
        title: _titleController.text.trim().isEmpty
            ? 'Imported media'
            : _titleController.text.trim(),
        folderId: folderId,
        kind: isVideo ? 'video' : 'audio',
        contentType: contentType,
      );
      if (mounted && uploaded) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _preview.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.select<MusicController, List<MediaFolder>>(
      (music) => music.mediaFolders,
    );
    final canSave =
        _permitted &&
        !_processing &&
        folders.any((folder) => folder.id == _folderId);
    String at(double seconds) =>
        _time(Duration(milliseconds: (seconds * 1000).round()));
    return Scaffold(
      appBar: AppBar(title: const Text('Keep privately')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Trim', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${at(_startSeconds)} – ${at(_endSeconds)}',
                style: TextStyle(color: _muted(context), fontSize: 13),
              ),
            ],
          ),
          RangeSlider(
            values: RangeValues(_startSeconds, _endSeconds),
            min: 0,
            max: _durationSeconds,
            divisions: math.max(1, _durationSeconds.round()),
            labels: RangeLabels(at(_startSeconds), at(_endSeconds)),
            onChanged: (values) => setState(() {
              _startSeconds = values.start;
              _endSeconds = values.end;
            }),
          ),
          OutlinedButton.icon(
            onPressed: _togglePreview,
            icon: Icon(
              _previewing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(_previewing ? 'Pause' : 'Preview selection'),
          ),
          const SizedBox(height: 24),
          _ChoicePicker(
            label: 'Folder',
            options: [
              for (final folder in folders) (id: folder.id, name: folder.name),
            ],
            selectedId: _folderId,
            onChanged: (id) => setState(() => _folderId = id),
            onCreate: () async => (await _createFolder(context))?.id,
            createLabel: 'New folder',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _permitted,
            onChanged: (value) => setState(() => _permitted = value ?? false),
            title: const Text(
              'I own this media or have permission to process it',
              style: TextStyle(fontSize: 14),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: canSave ? _processAndSave : null,
            child: Text(_processing ? 'Processing…' : 'Trim & save audio'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: canSave ? _uploadOriginal : null,
            child: const Text('Save original file'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Browser
// ─────────────────────────────────────────────────────────────────────────────

class NexBrowserScreen extends StatefulWidget {
  const NexBrowserScreen({super.key, required this.sharedLink});
  final String sharedLink;

  @override
  State<NexBrowserScreen> createState() => _NexBrowserScreenState();
}

class _NexBrowserScreenState extends State<NexBrowserScreen> {
  late final WebViewController _browser;
  late final MusicController _music;
  final _addressController = TextEditingController();
  late final TextEditingController _firstPillController;
  late final TextEditingController _secondPillController;
  var _progress = 0;
  bool _downloading = false;
  String? _currentPage, _userAgent;

  /// Main-frame URLs requested without a page starting. The Android WebView
  /// hands a file download back as a repeat request for the same URL.
  final Map<String, int> _unstarted = {};

  @override
  void initState() {
    super.initState();
    _music = context.read<MusicController>();
    _firstPillController = TextEditingController(
      text: _music.browserPillOne ?? widget.sharedLink,
    );
    _secondPillController = TextEditingController(
      text: _music.browserPillTwo ?? '',
    );
    _firstPillController.addListener(_saveFirstPill);
    _secondPillController.addListener(_saveSecondPill);
    _browser = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted && !_downloading) setState(() => _progress = value);
          },
          onPageStarted: (url) {
            _currentPage = url;
            _unstarted.remove(url);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null && !url.startsWith('data:')) {
              _addressController.text = url;
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                (uri.scheme != 'https' && uri.scheme != 'http')) {
              if (request.isMainFrame &&
                  (uri?.scheme == 'blob' || uri?.scheme == 'data')) {
                _snack(
                  'This site builds its download inside the page, which nexMusic cannot capture. Try another site.',
                );
              }
              return NavigationDecision.prevent;
            }
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final attempts = _unstarted[request.url] =
                (_unstarted[request.url] ?? 0) + 1;
            if (attempts > 3) {
              // The link keeps bouncing between page and download; stop it.
              _snack('This link could not be opened or downloaded.');
              return NavigationDecision.prevent;
            }
            if (attempts > 1 || uploadKindFor(uri.path) != null) {
              unawaited(_saveDownload(uri));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    final incoming = widget.sharedLink.trim();
    if (incoming.isEmpty) {
      _browser.loadHtmlString(_startPage);
      WidgetsBinding.instance.addPostFrameCallback((_) => _showQuickPanel());
    } else {
      unawaited(_go(incoming));
    }
  }

  static const _startPage = '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center;
      font-family:Roboto,Arial,sans-serif; color:#0a0a0a; background:#fff; }
    main { text-align:center; padding:32px; }
    h1 { margin:0 0 8px; font-size:20px; font-weight:600; }
    p { margin:0; color:#71717a; line-height:1.5; font-size:14px; }
  </style>
</head>
<body><main><h1>Browser</h1>
<p>Search, paste a link, or open YouTube.</p></main></body>
</html>
''';

  Uri _destination(String input) {
    final text = input.trim();
    final parsed = Uri.tryParse(text);
    if (parsed != null &&
        (parsed.scheme == 'https' || parsed.scheme == 'http')) {
      return parsed;
    }
    return Uri.https('www.google.com', '/search', {'q': text});
  }

  Future<void> _go(String input) async {
    if (input.trim().isEmpty) return;
    final destination = _destination(input);
    _addressController.text = destination.toString();
    if (uploadKindFor(destination.path) != null) {
      await _saveDownload(destination);
      return;
    }
    await _browser.loadRequest(destination);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _readUserAgent() async {
    try {
      final value = await _browser.runJavaScriptReturningResult(
        'navigator.userAgent',
      );
      return '$value'.replaceAll(RegExp(r'^"|"$'), '');
    } catch (_) {
      return null;
    }
  }

  /// Downloads a song or video a page links to and opens the upload screen
  /// with it. Links that turn out to be ordinary pages open in the browser.
  Future<void> _saveDownload(Uri url) async {
    if (_downloading) {
      _snack('A download is already running.');
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 1;
    });
    _snack('Downloading for nexMusic…');
    _userAgent ??= await _readUserAgent();
    final result = await downloadBrowserMedia(
      url,
      referer: _currentPage,
      userAgent: _userAgent,
      onProgress: (fraction) {
        final percent = (fraction * 100).round().clamp(1, 99);
        if (mounted && percent != _progress) {
          setState(() => _progress = percent);
        }
      },
    );
    if (!mounted) {
      final orphan = result.path;
      if (orphan != null) discardTemporaryCopy(orphan);
      return;
    }
    setState(() {
      _downloading = false;
      _progress = 0;
    });
    if (result.isWebPage) {
      await _browser.loadRequest(url);
      return;
    }
    final filePath = result.path;
    if (filePath == null) {
      _snack(result.error ?? 'Download failed.');
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => UploadScreen(initialPaths: [filePath])),
    );
    // A running upload still needs the file; otherwise drop the cached copy.
    if (!_music.uploads.any(
      (item) => item.path == filePath || item.original?.path == filePath,
    )) {
      discardTemporaryCopy(filePath);
    }
  }

  Future<void> _searchYouTube(String input) {
    final query = input.trim().isEmpty ? 'music' : input.trim();
    return _go(
      'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}',
    );
  }

  void _saveFirstPill() =>
      _music.setBrowserPillText(1, _firstPillController.text);
  void _saveSecondPill() =>
      _music.setBrowserPillText(2, _secondPillController.text);

  void _runPill(BuildContext sheetContext, TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(sheetContext);
    _go(value);
  }

  void _showQuickPanel() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Shortcuts',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Save searches or links you open often.',
                style: TextStyle(color: _muted(sheetContext), fontSize: 13),
              ),
              const SizedBox(height: 16),
              for (final controller in [
                _firstPillController,
                _secondPillController,
              ]) ...[
                TextField(
                  controller: controller,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _runPill(sheetContext, controller),
                  decoration: InputDecoration(
                    hintText: 'Search or link',
                    suffixIcon: IconButton(
                      tooltip: 'Run',
                      onPressed: () => _runPill(sheetContext, controller),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _firstPillController.removeListener(_saveFirstPill);
    _secondPillController.removeListener(_saveSecondPill);
    _firstPillController.dispose();
    _secondPillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _addressController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: _go,
          decoration: const InputDecoration(
            hintText: 'Search or enter address',
            isDense: true,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Go',
            onPressed: () => _go(_addressController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _browser),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () async {
                  if (await _browser.canGoBack()) _browser.goBack();
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                tooltip: 'Forward',
                onPressed: () async {
                  if (await _browser.canGoForward()) _browser.goForward();
                },
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              IconButton(
                tooltip: 'Home',
                onPressed: () {
                  _addressController.clear();
                  _browser.loadHtmlString(_startPage);
                },
                icon: const Icon(Icons.home_outlined),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Search YouTube',
                onPressed: () => _searchYouTube(_addressController.text),
                icon: const Icon(Icons.smart_display_rounded),
              ),
              IconButton(
                tooltip: 'Shortcuts',
                onPressed: _showQuickPanel,
                icon: const Icon(Icons.bolt_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
