import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'main.dart';
import 'music_controller.dart';
import 'music_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Navigation helpers
// ─────────────────────────────────────────────────────────────────────────────

void _openPlayer(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const NowPlayingScreen(),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 380),
    ),
  );
}

void _openCollection(BuildContext context, MusicCollection collection) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CollectionScreen(collection: collection),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility functions
// ─────────────────────────────────────────────────────────────────────────────

String _time(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Time-aware greeting (fixes hardcoded "Good evening" bug).
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

IconData _mediaIcon(SavedMedia item) => switch (item.kind) {
  'audio' => Icons.audio_file_rounded,
  'video' => Icons.video_file_rounded,
  _ => Icons.link_rounded,
};

String _mediaSubtitle(MusicController music, SavedMedia item) {
  if (item.kind == 'link') return 'Saved video link';
  final type = item.kind == 'video'
      ? 'Private cloud video'
      : 'Private cloud audio';
  return music.isDownloaded(item) ? '$type · Available offline' : type;
}

Future<void> _handleMediaAction(
  BuildContext context,
  SavedMedia item,
  String action,
) async {
  final music = context.read<MusicController>();
  if (action == 'download') {
    await music.downloadMedia(item);
  } else if (action == 'removeDownload') {
    await music.removeDownload(item);
  } else if (action == 'edit') {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SavedMediaEditorScreen(item: item)),
    );
  } else if (action == 'delete') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text(
          item.storagePath == null
              ? 'This saved link will be permanently removed.'
              : 'Cloud file, metadata and its offline copy will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await music.deleteMedia(item);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aurora decoration helper
// ─────────────────────────────────────────────────────────────────────────────

class _AuroraBlob extends StatelessWidget {
  const _AuroraBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: 0.35), Colors.transparent],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WELCOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    return Scaffold(
      body: Stack(
        children: [
          // Deep space gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0612),
                  Color(0xFF160A1E),
                  Color(0xFF040408),
                ],
              ),
            ),
          ),
          // Aurora blobs
          const Positioned(
            top: -80,
            right: -60,
            child: _AuroraBlob(color: NexMusicApp.violet, size: 300),
          ),
          const Positioned(
            top: 80,
            left: -80,
            child: _AuroraBlob(color: NexMusicApp.flamingo, size: 250),
          ),
          const Positioned(
            bottom: 80,
            right: -40,
            child: _AuroraBlob(color: NexMusicApp.violet, size: 200),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(26, 24, 26, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Brand(light: true),
                          const Spacer(),
                          Center(
                            child: SizedBox(
                              width: 310,
                              height: 310,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 275,
                                    height: 275,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [
                                          NexMusicApp.flamingo,
                                          NexMusicApp.violet,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: NexMusicApp.violet.withValues(
                                            alpha: 0.55,
                                          ),
                                          blurRadius: 90,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const _VinylDisc(),
                                  const Positioned(
                                    right: 8,
                                    top: 30,
                                    child: _FloatingNote(
                                      icon: Icons.music_note_rounded,
                                    ),
                                  ),
                                  const Positioned(
                                    left: 14,
                                    bottom: 30,
                                    child: _FloatingNote(
                                      icon: Icons.graphic_eq_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'Your sound.\nYour moment.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              height: 1.07,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Millions of moods, one beautiful place.\nDiscover what sounds like you.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              height: 1.55,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 34),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: music.loading
                                  ? null
                                  : music.googlePreviewLogin,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF17131F),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: music.loading
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const _GoogleLogo(),
                              label: const Text('Continue with Google'),
                            ),
                          ),
                          if (music.notice != null) ...[
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                music.notice!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: music.guestLogin,
                              child: Text(
                                'Explore preview →',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VinylDisc extends StatelessWidget {
  const _VinylDisc();
  @override
  Widget build(BuildContext context) => Container(
    width: 230,
    height: 230,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        colors: [
          Color(0xFFFF73AE),
          Color(0xFFFF4F9A),
          Color(0xFF2A173A),
          Color(0xFF0C0C10),
        ],
        stops: [0, 0.13, 0.15, 1],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: CustomPaint(painter: _GroovePainter()),
  );
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke;
    for (double r = 54; r < size.width / 2; r += 9) {
      canvas.drawCircle(size.center(Offset.zero), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FloatingNote extends StatelessWidget {
  const _FloatingNote({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 25),
      ),
    ),
  );
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();
  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 24,
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
// APP SHELL + NAVIGATION
// ─────────────────────────────────────────────────────────────────────────────

class MusicShell extends StatefulWidget {
  const MusicShell({super.key});
  @override
  State<MusicShell> createState() => _MusicShellState();
}

class _MusicShellState extends State<MusicShell> {
  int index = 0;
  static const _pages = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    ProfileScreen(),
  ];
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _openSharedItems,
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((items) {
      _openSharedItems(items);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _openSharedItems(List<SharedMediaFile> items) {
    if (!mounted || items.isEmpty) return;
    final item = items.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SharedImportScreen(
            source: item.path,
            isLocalMedia:
                item.type == SharedMediaType.video ||
                item.type == SharedMediaType.file,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shellState = context
        .select<MusicController, ({String? notice, Track? current})>(
          (music) => (notice: music.notice, current: music.current),
        );
    final music = context.read<MusicController>();
    if (shellState.notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || shellState.notice == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(shellState.notice!),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
        music.clearNotice();
      });
    }
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _pages[index]),
            if (shellState.current != null) const MiniPlayer(),
          ],
        ),
      ),
      bottomNavigationBar: _MusicBottomNav(
        currentIndex: index,
        onChanged: (value) => setState(() => index = value),
        items: const [
          _MusicNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Home',
          ),
          _MusicNavItem(
            icon: Icons.search_outlined,
            activeIcon: Icons.search_rounded,
            label: 'Discover',
          ),
          _MusicNavItem(
            icon: Icons.library_music_outlined,
            activeIcon: Icons.library_music_rounded,
            label: 'Library',
          ),
          _MusicNavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'You',
          ),
        ],
      ),
    );
  }
}

class _MusicNavItem {
  const _MusicNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon, activeIcon;
  final String label;
}

class _MusicBottomNav extends StatelessWidget {
  const _MusicBottomNav({
    required this.currentIndex,
    required this.onChanged,
    required this.items,
  });
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<_MusicNavItem> items;

  static const _barHeight = 66.0;
  static const _motion = Duration(milliseconds: 260);
  static const _curve = Curves.easeOutCubic;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
        child: Container(
          height: _barHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(33),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.5 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 5.0;
              final count = items.length;
              final available = constraints.maxWidth - gap * (count - 1);
              final inactiveWidth = math.min(48.0, available / count);
              final activeWidth = available - inactiveWidth * (count - 1);
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: _motion,
                    curve: _curve,
                    left: currentIndex * (inactiveWidth + gap),
                    top: 0,
                    bottom: 0,
                    width: activeWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9D6FFF), Color(0xFF6D28D9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < count; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        _MusicDestination(
                          item: items[i],
                          selected: i == currentIndex,
                          width: i == currentIndex
                              ? activeWidth
                              : inactiveWidth,
                          onTap: () => onChanged(i),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MusicDestination extends StatefulWidget {
  const _MusicDestination({
    required this.item,
    required this.selected,
    required this.width,
    required this.onTap,
  });
  final _MusicNavItem item;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  State<_MusicDestination> createState() => _MusicDestinationState();
}

class _MusicDestinationState extends State<_MusicDestination> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showLabel = widget.selected && widget.width >= 90;
    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onTap: () {
          if (!widget.selected) HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: _MusicBottomNav._curve,
          width: widget.width,
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: _pressed ? 0.82 : 1,
                duration: const Duration(milliseconds: 150),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    widget.selected ? widget.item.activeIcon : widget.item.icon,
                    key: ValueKey(widget.selected),
                    size: 22,
                    color: widget.selected
                        ? Colors.white
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: 7),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final homeState = context
        .select<
          MusicController,
          ({
            String name,
            String initials,
            Track? current,
            bool playing,
            int liked,
            int downloaded,
            List<Track> recent,
          })
        >(
          (music) => (
            name: music.profileName,
            initials: music.profileInitials,
            current: music.current,
            playing: music.playing,
            liked: music.liked.length,
            downloaded: music.offlinePaths.length,
            recent: music.recentTracks,
          ),
        );
    final firstName = homeState.name.split(RegExp(r'\s+')).first;

    return CustomScrollView(
      key: const PageStorageKey('home'),
      slivers: [
        // Aurora hero header
        SliverToBoxAdapter(
          child: _HomeHero(
            greeting: _greeting(),
            firstName: firstName,
            initials: homeState.initials,
            playing: homeState.playing,
            current: homeState.current,
          ),
        ),
        // Quick action pills
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        SliverToBoxAdapter(
          child: _HomeQuickActions(
            liked: homeState.liked,
            downloaded: homeState.downloaded,
          ),
        ),
        // Your Mixes — horizontal collection carousel
        const SliverToBoxAdapter(child: _SectionTitle(title: 'Your Mixes')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 218,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: collections.length,
              itemBuilder: (_, i) =>
                  _CollectionCard(collection: collections[i]),
            ),
          ),
        ),
        // Mood Stations — horizontal gradient cards
        const SliverToBoxAdapter(child: _SectionTitle(title: 'Mood Stations')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 112,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: moodStations.length,
              itemBuilder: (_, i) => _MoodCard(station: moodStations[i]),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
        // Pick up again — recent history
        if (homeState.recent.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: _SectionTitle(title: 'Pick Up Again', compact: true),
          ),
          SliverList.builder(
            itemCount: math.min(4, homeState.recent.length),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SongTile(
                track: homeState.recent[i],
                queue: homeState.recent,
              ),
            ),
          ),
        ],
        // Trending Now
        const SliverToBoxAdapter(
          child: _SectionTitle(title: 'Trending Now', compact: true),
        ),
        SliverList.builder(
          itemCount: math.min(5, tracks.length),
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SongTile(track: tracks[i], number: i + 1, queue: tracks),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.greeting,
    required this.firstName,
    required this.initials,
    required this.playing,
    required this.current,
  });
  final String greeting, firstName, initials;
  final bool playing;
  final Track? current;

  @override
  Widget build(BuildContext context) {
    final focus =
        current ?? (tracks.isNotEmpty ? tracks[1 % tracks.length] : null);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: NexMusicApp.violet,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _Brand(light: true)),
              CircleAvatar(
                backgroundColor: Colors.white24,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting, $firstName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Find your next favourite sound.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: NexMusicApp.violet,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: focus == null
                          ? null
                          : () {
                              if (playing && current != null) {
                                _openPlayer(context);
                              } else {
                                context.read<MusicController>().play(
                                  focus,
                                  from: tracks,
                                );
                              }
                            },
                      icon: Icon(
                        playing
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        playing ? 'Now playing' : 'Start smart mix',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (focus != null) ...[
                const SizedBox(width: 12),
                Artwork(
                  colors: focus.colors,
                  seed: focus.id,
                  size: 64,
                  radius: 16,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.liked, required this.downloaded});
  final int liked, downloaded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          _QuickPill(
            icon: Icons.auto_awesome_rounded,
            label: 'Smart Mix',
            gradient: const LinearGradient(
              colors: [Color(0xFF9D6FFF), Color(0xFF6D28D9)],
            ),
            onTap: () {
              final shuffled = List<Track>.of(tracks)..shuffle();
              if (shuffled.isEmpty) return;
              context.read<MusicController>().play(
                shuffled.first,
                from: shuffled,
              );
            },
          ),
          const SizedBox(width: 10),
          _QuickPill(
            icon: Icons.favorite_rounded,
            label: '$liked Liked',
            gradient: const LinearGradient(
              colors: [Color(0xFFB02D62), Color(0xFFFF91B9)],
            ),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => LikedSongsScreen(
                  songs: context.read<MusicController>().likedTracks,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _QuickPill(
            icon: Icons.ios_share_rounded,
            label: 'Import',
            gradient: const LinearGradient(
              colors: [Color(0xFF096A76), Color(0xFF36D1C4)],
            ),
            onTap: () => _showImportMenu(context),
          ),
          const SizedBox(width: 10),
          _QuickPill(
            icon: Icons.offline_pin_rounded,
            label: '$downloaded Offline',
            gradient: const LinearGradient(
              colors: [Color(0xFF1B4FBF), Color(0xFF4A9DFF)],
            ),
            onTap: () => _simpleSheet(
              context,
              'Offline library',
              '$downloaded imported items are available offline on this device.',
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection});
  final MusicCollection collection;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _openCollection(context, collection),
    child: Container(
      width: 155,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Artwork(
            colors: collection.colors,
            seed: collection.id,
            size: 155,
            radius: 20,
          ),
          const SizedBox(height: 10),
          Text(
            collection.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            collection.subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.station});
  final MoodStation station;

  @override
  Widget build(BuildContext context) {
    final stTracks = stationTracks(station);
    return GestureDetector(
      onTap: () {
        if (stTracks.isEmpty) return;
        context.read<MusicController>().play(stTracks.first, from: stTracks);
      },
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: station.colors,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: station.colors.first.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(station.icon, color: Colors.white, size: 20),
            ),
            const Spacer(),
            Text(
              station.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              station.subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH SCREEN  (genre cards now filter tracks and navigate to genre screen)
// ─────────────────────────────────────────────────────────────────────────────

/// Deterministic genre → track ID mapping for filtering.
const _genreTrackIds = <String, List<String>>{
  'Indie': ['khwaab', 'slow', 'baarish'],
  'Bollywood': ['baarish', 'safar', 'khwaab'],
  'Chill': ['slow', 'khwaab', 'baarish'],
  'Pop': ['midnight', 'higher', 'city'],
  'Focus': ['orbit', 'slow', 'city'],
  'Workout': ['higher', 'safar', 'midnight'],
  'Party': ['higher', 'city', 'orbit'],
  'Podcasts': ['midnight', 'orbit'],
};

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = tracks
        .where(
          (t) => '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();

    return CustomScrollView(
      key: const PageStorageKey('search'),
      slivers: [
        SliverAppBar(
          title: const Text('Discover'),
          floating: true,
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          sliver: SliverToBoxAdapter(
            child: TextField(
              controller: _controller,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search music',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 48,
                ),
                suffixIconConstraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 48,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        iconSize: 20,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : const Icon(Icons.mic_none_rounded, size: 20),
              ),
            ),
          ),
        ),
        if (_query.isEmpty) ...[
          const SliverToBoxAdapter(
            child: _SectionTitle(title: 'Browse all', compact: true),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 26),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _genres.length,
              itemBuilder: (_, i) => _GenreCard(data: _genres[i]),
            ),
          ),
          const SliverToBoxAdapter(
            child: _SectionTitle(title: 'Popular right now', compact: true),
          ),
          SliverList.builder(
            itemCount: math.min(4, tracks.length),
            itemBuilder: (context, i) {
              final idx = i + 1 < tracks.length ? i + 1 : i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SongTile(track: tracks[idx], queue: tracks),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ] else ...[
          SliverToBoxAdapter(
            child: _SectionTitle(
              title:
                  '${results.length} result${results.length == 1 ? '' : 's'}',
              compact: true,
            ),
          ),
          if (results.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Nothing found',
                subtitle: 'Try another artist, song or album name.',
              ),
            )
          else
            SliverList.builder(
              itemCount: results.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SongTile(track: results[i], queue: results),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ],
    );
  }
}

const _genres = [
  ('Indie', Color(0xFFB94A60), Icons.auto_awesome_rounded),
  ('Bollywood', Color(0xFFE37B35), Icons.local_fire_department_rounded),
  ('Chill', Color(0xFF2A7C77), Icons.spa_rounded),
  ('Pop', Color(0xFF7457D9), Icons.star_rounded),
  ('Focus', Color(0xFF315C9E), Icons.psychology_rounded),
  ('Workout', Color(0xFF42793D), Icons.fitness_center_rounded),
  ('Party', Color(0xFFC13F91), Icons.celebration_rounded),
  ('Podcasts', Color(0xFF93633E), Icons.podcasts_rounded),
];

class _GenreCard extends StatelessWidget {
  const _GenreCard({required this.data});
  final (String, Color, IconData) data;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      final genreName = data.$1;
      final ids = _genreTrackIds[genreName] ?? [];
      // Build genre tracks list; fall back to all tracks if IDs don't match yet
      final genreTracks = ids.isEmpty
          ? tracks
          : ids
                .map(
                  (id) => tracks.cast<Track?>().firstWhere(
                    (t) => t?.id == id,
                    orElse: () => null,
                  ),
                )
                .whereType<Track>()
                .toList();
      final display = genreTracks.isEmpty ? tracks : genreTracks;
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => GenreTracksScreen(
            genre: genreName,
            color: data.$2,
            icon: data.$3,
            genreTracks: display,
          ),
        ),
      );
    },
    borderRadius: BorderRadius.circular(19),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: data.$2,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: -6,
            right: -6,
            child: Transform.rotate(
              angle: -0.18,
              child: Icon(
                data.$3,
                size: 56,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          Text(
            data.$1,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Dedicated screen showing tracks filtered by genre.
class GenreTracksScreen extends StatelessWidget {
  const GenreTracksScreen({
    super.key,
    required this.genre,
    required this.color,
    required this.icon,
    required this.genreTracks,
  });
  final String genre;
  final Color color;
  final IconData icon;
  final List<Track> genreTracks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withValues(alpha: 0.55)],
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: Colors.white.withValues(alpha: 0.28),
                    size: 100,
                  ),
                ),
              ),
              title: Text(
                genre,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    '${genreTracks.length} tracks',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      final shuffled = List<Track>.of(genreTracks)..shuffle();
                      if (shuffled.isEmpty) return;
                      context.read<MusicController>().play(
                        shuffled.first,
                        from: shuffled,
                      );
                    },
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Shuffle'),
                    style: FilledButton.styleFrom(backgroundColor: color),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: genreTracks.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SongTile(
                track: genreTracks[i],
                number: i + 1,
                queue: genreTracks,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIBRARY SCREEN  (filter chips now actually filter content)
// ─────────────────────────────────────────────────────────────────────────────

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _filter = 0; // 0=All  1=Playlists  2=Songs  3=Downloaded

  static const _filterLabels = ['All', 'Playlists', 'Songs', 'Downloaded'];

  @override
  Widget build(BuildContext context) {
    final libraryState = context
        .select<
          MusicController,
          ({
            bool configured,
            List<SavedMedia> saved,
            int likedCount,
            List<Track> likedTracks,
            int offlineRevision,
          })
        >(
          (music) => (
            configured: music.backendConfigured,
            saved: music.savedMedia,
            likedCount: music.liked.length,
            likedTracks: music.likedTracks,
            offlineRevision: Object.hashAllUnordered(music.offlinePaths.keys),
          ),
        );
    final music = context.read<MusicController>();

    final visibleImports = _filter == 3
        ? libraryState.saved.where(music.isDownloaded).toList()
        : libraryState.saved;

    final showLiked = _filter == 0 || _filter == 2;
    final showPlaylists = _filter == 0 || _filter == 1;
    final showImports = _filter == 0 || _filter == 3;

    return CustomScrollView(
      key: const PageStorageKey('library'),
      slivers: [
        SliverAppBar(
          title: const Text('Your Library'),
          floating: true,
          actions: [
            IconButton(
              onPressed: () => _showImportMenu(context),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        // Filter chips
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _filterLabels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_filterLabels[i]),
                selected: _filter == i,
                onSelected: (_) => setState(() => _filter = i),
                selectedColor: NexMusicApp.violet.withValues(alpha: 0.16),
                checkmarkColor: NexMusicApp.violet,
                labelStyle: TextStyle(
                  color: _filter == i ? NexMusicApp.violet : null,
                  fontWeight: _filter == i ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        // Import banner
        if (showImports)
          SliverToBoxAdapter(
            child: _ImportBanner(
              configured: libraryState.configured,
              onTap: () => _showImportMenu(context),
            ),
          ),
        // Liked songs
        if (showLiked)
          SliverToBoxAdapter(
            child: _LibraryTile(
              icon: Icons.favorite_rounded,
              colors: const [Color(0xFF7050ED), Color(0xFFFF76B3)],
              title: 'Liked Songs',
              subtitle: '${libraryState.likedCount} songs',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      LikedSongsScreen(songs: libraryState.likedTracks),
                ),
              ),
            ),
          ),
        // Playlists
        if (showPlaylists) ...[
          const SliverToBoxAdapter(
            child: _SectionTitle(title: 'Playlists', compact: true),
          ),
          SliverList.builder(
            itemCount: collections.length,
            itemBuilder: (context, i) {
              final item = collections[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 5,
                ),
                leading: Artwork(
                  colors: item.colors,
                  seed: item.id,
                  size: 60,
                  radius: 15,
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Playlist · ${item.subtitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openCollection(context, item),
              );
            },
          ),
        ],
        // Recently played (All only)
        if (_filter == 0)
          SliverToBoxAdapter(
            child: _LibraryTile(
              icon: Icons.history_rounded,
              colors: const [Color(0xFF18766F), Color(0xFF5FE0B8)],
              title: 'Recently Played',
              subtitle: 'Your listening history',
              onTap: () {
                if (collections.isNotEmpty) {
                  _openCollection(context, collections.first);
                }
              },
            ),
          ),
        // Saved imports
        if (showImports && visibleImports.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: _SectionTitle(title: 'Saved imports', compact: true),
          ),
          SliverList.builder(
            itemCount: visibleImports.length,
            itemBuilder: (context, i) {
              final item = visibleImports[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: CircleAvatar(
                  backgroundColor: NexMusicApp.violet.withValues(alpha: 0.14),
                  child: Icon(_mediaIcon(item), color: NexMusicApp.violet),
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _mediaSubtitle(music, item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) =>
                      _handleMediaAction(context, item, action),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit details'),
                      ),
                    ),
                    if (item.storagePath != null && !music.isDownloaded(item))
                      const PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.download_rounded),
                          title: Text('Download offline'),
                        ),
                      ),
                    if (music.isDownloaded(item))
                      const PopupMenuItem(
                        value: 'removeDownload',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.offline_pin_outlined),
                          title: Text('Remove offline copy'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete permanently'),
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  if (item.sourceUrl == null) {
                    _simpleSheet(
                      context,
                      item.title,
                      'Stored privately in Firebase Storage.',
                    );
                    return;
                  }
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NexBrowserScreen(sharedLink: item.sourceUrl!),
                    ),
                  );
                },
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

class _ImportBanner extends StatelessWidget {
  const _ImportBanner({required this.configured, required this.onTap});
  final bool configured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(23),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [NexMusicApp.violet, Color(0xFFC64FAD)],
          ),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.ios_share_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Import to nexMusic',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    configured
                        ? 'Links or your own media · Firebase ready'
                        : 'Preview mode · Google login to upload',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final List<Color> colors;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    leading: Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: Colors.white),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context
        .select<
          MusicController,
          ({
            String initials,
            String name,
            String email,
            int likedCount,
            bool darkMode,
            int downloadCount,
          })
        >(
          (music) => (
            initials: music.profileInitials,
            name: music.profileName,
            email: music.profileEmail,
            likedCount: music.liked.length,
            darkMode: music.darkMode,
            downloadCount: music.offlinePaths.length,
          ),
        );
    final music = context.read<MusicController>();

    return CustomScrollView(
      key: const PageStorageKey('profile'),
      slivers: [
        // Aurora profile header
        SliverToBoxAdapter(
          child: Stack(
            children: [
              Container(
                height: 190,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                  ),
                ),
              ),
              const Positioned(
                top: -50,
                right: -40,
                child: _AuroraBlob(color: NexMusicApp.violet, size: 200),
              ),
              const Positioned(
                top: 40,
                left: -60,
                child: _AuroraBlob(color: NexMusicApp.flamingo, size: 180),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 32, 22, 26),
                child: Row(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9D6FFF), Color(0xFF6D28D9)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NexMusicApp.violet.withValues(alpha: 0.45),
                            blurRadius: 22,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          profile.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile.email,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _simpleSheet(
                        context,
                        'Edit profile',
                        'Name and photo are synced from Firebase Google Auth.',
                      ),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Stats card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: _Stat(value: '12', label: 'Playlists'),
                    ),
                    Expanded(
                      child: _Stat(
                        value: '${profile.likedCount}',
                        label: 'Liked',
                      ),
                    ),
                    const Expanded(
                      child: _Stat(value: '8h', label: 'This week'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
        const SliverToBoxAdapter(child: _SettingHeader('Preferences')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: profile.darkMode,
                    onChanged: music.setDarkMode,
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text(
                      'Dark mode',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.high_quality_outlined),
                    title: const Text(
                      'Audio quality',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('High'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _simpleSheet(
                      context,
                      'Audio quality',
                      'Automatic · Data saver · High · Lossless',
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: Text(
                      'Downloads (${profile.downloadCount})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _simpleSheet(
                      context,
                      'Downloads',
                      '${profile.downloadCount} file(s) are stored privately inside nexMusic on this device.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        const SliverToBoxAdapter(child: _SettingHeader('Account')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_none_rounded),
                    title: const Text(
                      'Notifications',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _simpleSheet(
                      context,
                      'Notifications',
                      'Choose new release and playlist alerts.',
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text(
                      'About nexMusic',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Version 0.1.0'),
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'nexMusic',
                      applicationVersion: '0.1.0',
                      applicationIcon: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/branding/nexmusic-logo.png',
                          width: 64,
                          height: 64,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: OutlinedButton.icon(
              onPressed: music.signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: Colors.redAccent,
                side: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 28),
            child: Center(
              child: Text(
                'Made with rhythm by TheNex',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ],
  );
}

class _SettingHeader extends StatelessWidget {
  const _SettingHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 9),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI PLAYER  (glassmorphism + gradient progress + like button)
// ─────────────────────────────────────────────────────────────────────────────

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final track = music.current!;
    final max = math.max(1, music.duration.inMilliseconds).toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFF1A1A20).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: InkWell(
            onTap: () => _openPlayer(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gradient progress bar at top
                RepaintBoundary(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: music.positionListenable,
                    builder: (context, position, _) {
                      final ratio = (position.inMilliseconds / max).clamp(
                        0.0,
                        1.0,
                      );
                      return Stack(
                        children: [
                          Container(height: 2.5, color: Colors.transparent),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(
                              height: 2.5,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    NexMusicApp.violet,
                                    NexMusicApp.flamingo,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
                  child: Row(
                    children: [
                      Artwork(
                        colors: track.colors,
                        seed: track.id,
                        size: 48,
                        radius: 12,
                        hero: 'art-${track.id}',
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Like button inline in mini player
                      Builder(
                        builder: (ctx) {
                          final liked = context.select<MusicController, bool>(
                            (m) => m.isLiked(track),
                          );
                          return IconButton(
                            onPressed: () => music.toggleLike(track),
                            icon: Icon(
                              liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: liked ? const Color(0xFFFF4F9A) : null,
                              size: 20,
                            ),
                          );
                        },
                      ),
                      if (music.loading)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: music.togglePlay,
                          icon: Icon(
                            music.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      IconButton(
                        onPressed: music.next,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOW PLAYING SCREEN
// Fixes: rotating artwork, aurora gradient play button, correct repeat icon,
//        white text on all themes.
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  MusicController? _music;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_music == null) {
      _music = context.read<MusicController>();
      _music!.addListener(_syncSpin);
      _syncSpin();
    }
  }

  void _syncSpin() {
    if (!mounted) return;
    final playing = _music?.playing ?? false;
    if (playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _music?.removeListener(_syncSpin);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final track = music.current;
    if (track == null) {
      return const Scaffold(body: Center(child: Text('Nothing playing')));
    }
    final max = math.max(1, music.duration.inMilliseconds).toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              track.colors.first.withValues(alpha: dark ? 0.85 : 0.95),
              dark ? Colors.black : const Color(0xFF0A0A14),
            ],
            stops: const [0, 0.70],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final compact = viewport.maxHeight < 720;
              final ultraCompact = viewport.maxHeight < 560;
              final artworkSize = math.max(
                ultraCompact ? 88.0 : 160.0,
                math.min(
                  viewport.maxWidth - 80,
                  ultraCompact
                      ? viewport.maxHeight * 0.23
                      : compact
                      ? viewport.maxHeight * 0.38
                      : 290.0,
                ),
              );
              return Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: Navigator.of(context).pop,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                        const Expanded(
                          child: Column(
                            children: [
                              Text(
                                'NOW PLAYING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: Colors.white60,
                                ),
                              ),
                              Text(
                                'nexMusic Mix',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _simpleSheet(
                            context,
                            'Track options',
                            'Add to playlist · View artist · Share',
                          ),
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: ultraCompact
                        ? 2
                        : compact
                        ? 8
                        : 20,
                  ),
                  // Rotating circular artwork (new feature)
                  Center(
                    child: RotationTransition(
                      turns: _spin,
                      child: Artwork(
                        colors: track.colors,
                        seed: track.id,
                        size: artworkSize,
                        radius: artworkSize / 2, // Full circle
                        hero: 'art-${track.id}',
                      ),
                    ),
                  ),
                  SizedBox(
                    height: ultraCompact
                        ? 4
                        : compact
                        ? 18
                        : 32,
                  ),
                  // Track info + like
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: ultraCompact ? 21 : 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                track.artist,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => music.toggleLike(track),
                          icon: Icon(
                            music.isLiked(track)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: music.isLiked(track)
                                ? const Color(0xFFFF4F9A)
                                : Colors.white,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: ultraCompact
                        ? 4
                        : compact
                        ? 8
                        : 16,
                  ),
                  // Seek bar — white slider on dark background
                  RepaintBoundary(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: music.positionListenable,
                      builder: (context, position, _) {
                        final value = position.inMilliseconds
                            .clamp(0, max.toInt())
                            .toDouble();
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14,
                                  ),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white24,
                                ),
                                child: Slider(
                                  value: value,
                                  max: max,
                                  onChanged: (v) => music.seek(
                                    Duration(milliseconds: v.round()),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _time(position),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      _time(music.duration),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: ultraCompact
                        ? 3
                        : compact
                        ? 10
                        : 16,
                  ),
                  // Playback controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: music.toggleShuffle,
                          icon: Icon(
                            Icons.shuffle_rounded,
                            // FIX: color driven by state
                            color: music.shuffle
                                ? const Color(0xFFEC4899)
                                : Colors.white60,
                            size: 26,
                          ),
                        ),
                        IconButton(
                          onPressed: music.previous,
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                        // Play/pause — aurora gradient (FIX: was white-on-white)
                        GestureDetector(
                          onTap: music.loading ? null : music.togglePlay,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  NexMusicApp.violet,
                                  NexMusicApp.flamingo,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: NexMusicApp.violet.withValues(
                                    alpha: 0.55,
                                  ),
                                  blurRadius: 30,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: music.loading
                                ? const Center(
                                    child: SizedBox.square(
                                      dimension: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    music.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                          ),
                        ),
                        IconButton(
                          onPressed: music.next,
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                        IconButton(
                          onPressed: music.toggleRepeat,
                          icon: Icon(
                            // FIX: correct icon — repeat vs repeat_one
                            music.repeat
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: music.repeat
                                ? const Color(0xFFEC4899)
                                : Colors.white60,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom: lyrics + queue
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => _lyricsSheet(context, track),
                          icon: const Icon(
                            Icons.lyrics_outlined,
                            size: 19,
                            color: Colors.white60,
                          ),
                          label: const Text(
                            'Lyrics',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _queueSheet(context),
                          icon: const Icon(
                            Icons.queue_music_rounded,
                            size: 19,
                            color: Colors.white60,
                          ),
                          label: const Text(
                            'Queue',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SONG TILE  (FIX: trailing shows heart not hamburger menu)
// ─────────────────────────────────────────────────────────────────────────────

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.track,
    required this.queue,
    this.number,
  });
  final Track track;
  final List<Track> queue;
  final int? number;

  @override
  Widget build(BuildContext context) {
    final tileState = context
        .select<MusicController, ({String? currentId, bool liked})>(
          (music) =>
              (currentId: music.current?.id, liked: music.isLiked(track)),
        );
    final music = context.read<MusicController>();
    final active = tileState.currentId == track.id;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (number != null)
            SizedBox(
              width: 28,
              child: active
                  ? const Icon(
                      Icons.graphic_eq_rounded,
                      color: NexMusicApp.violet,
                      size: 18,
                    )
                  : Text(
                      '$number',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? NexMusicApp.violet : Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          Artwork(colors: track.colors, seed: track.id, size: 54, radius: 14),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 1,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: active ? NexMusicApp.violet : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (track.explicit)
            Container(
              margin: const EdgeInsets.only(right: 5),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'E',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
              ),
            ),
          Flexible(
            child: Text(
              '${track.artist} · ${track.album}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        onPressed: () => music.toggleLike(track),
        icon: Icon(
          // FIX: always show heart icon — filled when liked, outline when not
          tileState.liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          size: 21,
          color: tileState.liked ? const Color(0xFFFF4F9A) : null,
        ),
      ),
      onTap: () => music.play(track, from: queue),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ARTWORK WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.colors,
    required this.seed,
    this.size,
    this.radius = 20,
    this.hero,
  });
  final List<Color> colors;
  final String seed;
  final double? size, radius;
  final Object? hero;

  @override
  Widget build(BuildContext context) {
    final art = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius!),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _ArtworkPainter(seed.hashCode)),
    );
    return hero == null ? art : Hero(tag: hero!, child: art);
  }
}

class _ArtworkPainter extends CustomPainter {
  const _ArtworkPainter(this.seed);
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.14);
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        size.shortestSide * (0.08 + random.nextDouble() * 0.2),
        paint,
      );
    }
    final text = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.graphic_eq_rounded.codePoint),
        style: TextStyle(
          fontFamily: Icons.graphic_eq_rounded.fontFamily,
          package: Icons.graphic_eq_rounded.fontPackage,
          fontSize: size.shortestSide * 0.42,
          color: Colors.white.withValues(alpha: 0.88),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ArtworkPainter oldDelegate) =>
      seed != oldDelegate.seed;
}

// ─────────────────────────────────────────────────────────────────────────────
// COLLECTION SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key, required this.collection});
  final MusicCollection collection;

  @override
  Widget build(BuildContext context) {
    final songs = tracksFor(collection);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ...collection.colors,
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      Artwork(
                        colors: collection.colors.reversed.toList(),
                        seed: collection.id,
                        size: 205,
                        radius: 28,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    collection.subtitle,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.favorite_border_rounded),
                      ),
                      IconButton(
                        onPressed: () => _simpleSheet(
                          context,
                          'Playlist options',
                          'Share, download and collaborative controls.',
                        ),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: context
                            .read<MusicController>()
                            .toggleShuffle,
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                      const SizedBox(width: 8),
                      if (songs.isNotEmpty)
                        GestureDetector(
                          onTap: () => context.read<MusicController>().play(
                            songs.first,
                            from: songs,
                          ),
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  NexMusicApp.violet,
                                  NexMusicApp.flamingo,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: NexMusicApp.violet.withValues(
                                    alpha: 0.45,
                                  ),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SongTile(track: songs[i], number: i + 1, queue: songs),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 45)),
        ],
      ),
    );
  }
}

class LikedSongsScreen extends StatelessWidget {
  const LikedSongsScreen({super.key, required this.songs});
  final List<Track> songs;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Liked Songs')),
    body: songs.isEmpty
        ? const _EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'Your favorites live here',
            subtitle: 'Tap the heart on any track to save it.',
          )
        : ListView.builder(
            padding: const EdgeInsets.only(top: 10),
            itemCount: songs.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SongTile(track: songs[i], number: i + 1, queue: songs),
            ),
          ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVED MEDIA EDITOR
// ─────────────────────────────────────────────────────────────────────────────

class SavedMediaEditorScreen extends StatefulWidget {
  const SavedMediaEditorScreen({super.key, required this.item});
  final SavedMedia item;

  @override
  State<SavedMediaEditorScreen> createState() => _SavedMediaEditorScreenState();
}

class _SavedMediaEditorScreenState extends State<SavedMediaEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late String? _folderId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _urlController = TextEditingController(text: widget.item.sourceUrl ?? '');
    _folderId = widget.item.folderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final folders = context.read<MusicController>().mediaFolders;
      if (!mounted || folders.any((f) => f.id == _folderId)) return;
      if (folders.isNotEmpty) setState(() => _folderId = folders.first.id);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_folderId == null) return;
    setState(() => _saving = true);
    final success = await context.read<MusicController>().updateMedia(
      widget.item,
      title: _titleController.text,
      folderId: _folderId!,
      sourceUrl: widget.item.kind == 'link' ? _urlController.text : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final folders = context.select<MusicController, List<MediaFolder>>(
      (music) => music.mediaFolders,
    );
    final isLink = widget.item.kind == 'link';
    return Scaffold(
      appBar: AppBar(title: const Text('Edit saved item')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          TextField(
            controller: _titleController,
            textInputAction: isLink
                ? TextInputAction.next
                : TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Title',
              prefixIcon: Icon(Icons.title_rounded),
            ),
          ),
          if (isLink) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Video link',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _FolderSelector(
            folders: folders,
            value: _folderId,
            onChanged: (value) => setState(() => _folderId = value),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving || _folderId == null ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED IMPORT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SharedImportScreen extends StatefulWidget {
  const SharedImportScreen({
    super.key,
    required this.source,
    required this.isLocalMedia,
  });
  final String source;
  final bool isLocalMedia;

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
    final url =
        RegExp(r'https?://\S+')
            .firstMatch(widget.source)
            ?.group(0)
            ?.replaceAll(RegExp(r'[),.]+$'), '') ??
        widget.source;
    _urlController = TextEditingController(text: url);
    _titleController = TextEditingController(text: 'Shared video');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final folders = context.read<MusicController>().mediaFolders;
      if (mounted && folders.isNotEmpty) {
        setState(() => _folderId = folders.first.id);
      }
      if (!widget.isLocalMedia && widget.source.trim().isNotEmpty) {
        _copyLinkAndOpenBrowser();
      }
    });
  }

  Future<void> _copyLinkAndOpenBrowser() async {
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
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!mounted) return;
    if (supported) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => NexBrowserScreen(sharedLink: value)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied. In-app browser is available on mobile.'),
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
    if (_urlController.text.trim().isEmpty || _folderId == null) return;
    setState(() => _saving = true);
    final success = await context.read<MusicController>().saveSharedLink(
      url: _urlController.text.trim(),
      title: _titleController.text.trim().isEmpty
          ? 'Shared video'
          : _titleController.text.trim(),
      folderId: _folderId!,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocalMedia) {
      return OwnedMediaEditorScreen(
        source: widget.source,
        suggestedName: 'Shared media',
      );
    }
    final folders = context.select<MusicController, List<MediaFolder>>(
      (music) => music.mediaFolders,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Save video link')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF332361), Color(0xFF7D315E)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.smart_display_rounded,
                  color: Colors.white,
                  size: 38,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link inbox',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Save the link first, or open it directly to inspect.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Video link',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Save as',
              prefixIcon: Icon(Icons.title_rounded),
            ),
          ),
          const SizedBox(height: 12),
          _FolderSelector(
            folders: folders,
            value: _folderId,
            onChanged: (value) => setState(() => _folderId = value),
          ),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.bookmark_add_rounded),
                  ),
                  title: const Text(
                    'Save to library',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Adds this YouTube/video link inside selected folder',
                  ),
                  trailing: const Icon(
                    Icons.check_circle_rounded,
                    color: NexMusicApp.violet,
                  ),
                  onTap: _saveLink,
                ),
                const Divider(height: 1, indent: 72),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.language_rounded),
                  ),
                  title: const Text(
                    'Open this link',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Copies and loads the link in browser'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: _copyLinkAndOpenBrowser,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final file = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: const ['mp4', 'mov', 'm4a', 'aac', 'mp3'],
              );
              final source = file?.path;
              if (!context.mounted || file == null || source == null) return;
              Navigator.pushReplacement<void, void>(
                context,
                MaterialPageRoute(
                  builder: (_) => OwnedMediaEditorScreen(
                    source: source,
                    suggestedName: file.name,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.video_file_outlined),
            label: const Text('Choose my own media instead'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _saveLink,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_done_outlined),
            label: const Text('Save link'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEX BROWSER SCREEN
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
      ..setBackgroundColor(const Color(0xFFF7F6FA))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
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
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    final incoming = widget.sharedLink.trim();
    if (incoming.isEmpty) {
      _browser.loadHtmlString(_startPage);
    } else {
      unawaited(_go(incoming));
    }
    if (incoming.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showQuickPanel());
    }
  }

  static const _startPage = '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body { margin:0; min-height:100vh; display:grid; place-items:center;
      font-family:Arial,sans-serif; color:#292633;
      background:linear-gradient(145deg,#f7f6fa,#eeeafd); }
    main { text-align:center; padding:32px; }
    .mark { width:76px; height:76px; margin:auto; display:grid; place-items:center;
      border-radius:24px; color:white; font-size:34px; font-weight:900;
      background:linear-gradient(135deg,#7657ff,#ec4899);
      box-shadow:0 18px 45px #7657ff44; }
    h1 { margin:22px 0 8px; font-size:28px; }
    p { margin:0; color:#716c7d; line-height:1.5; }
  </style>
</head>
<body><main><div class="mark">N</div><h1>nexMusic Link Browser</h1>
<p>Paste a link, search YouTube, or run one of your saved shortcuts.</p></main></body>
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
    await _browser.loadRequest(destination);
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
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick actions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text('Save repeat searches or paste a link and run it.'),
              const SizedBox(height: 18),
              TextField(
                controller: _firstPillController,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) =>
                    _runPill(sheetContext, _firstPillController),
                decoration: InputDecoration(
                  hintText: 'First quick search',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Run',
                    onPressed: () =>
                        _runPill(sheetContext, _firstPillController),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _secondPillController,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) =>
                    _runPill(sheetContext, _secondPillController),
                decoration: InputDecoration(
                  hintText: 'Second quick search',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Run',
                    onPressed: () =>
                        _runPill(sheetContext, _secondPillController),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ),
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
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 19),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Go',
            onPressed: () => _go(_addressController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          IconButton(
            tooltip: 'Search YouTube',
            onPressed: () => _searchYouTube(_addressController.text),
            icon: const Icon(Icons.smart_display_rounded),
          ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: WebViewWidget(controller: _browser),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
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
              FilledButton.tonalIcon(
                onPressed: () => _searchYouTube(_addressController.text),
                icon: const Icon(Icons.smart_display_rounded),
                label: const Text('YouTube'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
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

// ─────────────────────────────────────────────────────────────────────────────
// OWNED MEDIA EDITOR
// ─────────────────────────────────────────────────────────────────────────────

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
  static const _mediaChannel = MethodChannel('com.thenex.nexmusic/media_tools');
  final _preview = AudioPlayer();
  late final TextEditingController _titleController;
  StreamSubscription<Duration>? _positionSub;
  double _durationSeconds = 180, _startSeconds = 0, _endSeconds = 30;
  String? _folderId, _exportPath, _error;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final folders = context.read<MusicController>().mediaFolders;
      if (mounted && folders.isNotEmpty) {
        setState(() => _folderId = folders.first.id);
      }
    });
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
    await _preview.play();
    if (mounted) setState(() => _previewing = true);
  }

  Future<void> _processAndSave() async {
    if (!_permitted || _folderId == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await _preview.pause();
      _exportPath = await _mediaChannel
          .invokeMethod<String>('extractAndTrimAudio', {
            'source': widget.source,
            'startMs': (_startSeconds * 1000).round(),
            'endMs': (_endSeconds * 1000).round(),
          });
      if (_exportPath == null) throw StateError('No export was created.');
      if (!mounted) return;
      final uploaded = await context.read<MusicController>().uploadOwnedAudio(
        filePath: _exportPath!,
        title: _titleController.text.trim().isEmpty
            ? 'Imported audio'
            : _titleController.text.trim(),
        folderId: _folderId!,
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
    if (!_permitted || _folderId == null) return;
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
        folderId: _folderId!,
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
    final editorState = context
        .select<
          MusicController,
          ({List<MediaFolder> folders, bool configured})
        >(
          (music) => (
            folders: music.mediaFolders,
            configured: music.backendConfigured,
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Edit & upload media')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
        children: [
          Container(
            height: 170,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF16736D), Color(0xFF7657FF)],
              ),
              borderRadius: BorderRadius.circular(27),
            ),
            child: CustomPaint(
              painter: _WavePainter(),
              child: const Center(
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Media title',
              prefixIcon: Icon(Icons.music_note_rounded),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Trim range',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_time(Duration(milliseconds: (_startSeconds * 1000).round()))} – '
                '${_time(Duration(milliseconds: (_endSeconds * 1000).round()))}',
                style: const TextStyle(
                  color: NexMusicApp.violet,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          RangeSlider(
            values: RangeValues(_startSeconds, _endSeconds),
            min: 0,
            max: _durationSeconds,
            divisions: math.max(1, _durationSeconds.round()),
            labels: RangeLabels(
              _time(Duration(milliseconds: (_startSeconds * 1000).round())),
              _time(Duration(milliseconds: (_endSeconds * 1000).round())),
            ),
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
            label: Text(_previewing ? 'Pause preview' : 'Preview selection'),
          ),
          const SizedBox(height: 16),
          _FolderSelector(
            folders: editorState.folders,
            value: _folderId,
            onChanged: (value) => setState(() => _folderId = value),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _permitted,
            onChanged: (value) => setState(() => _permitted = value ?? false),
            title: const Text(
              'I own this media or have permission to process it',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Only local, authorized media can be extracted.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          if (_exportPath != null && !editorState.configured)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(
                'Local export ready: $_exportPath',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          FilledButton.icon(
            onPressed: !_permitted || _processing ? null : _processAndSave,
            icon: _processing
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_processing ? 'Processing…' : 'Extract, trim & save'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: !_permitted || _processing ? null : _uploadOriginal,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Upload original audio/video'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOLDER SELECTOR
// ─────────────────────────────────────────────────────────────────────────────

class _FolderSelector extends StatelessWidget {
  const _FolderSelector({
    required this.folders,
    required this.value,
    required this.onChanged,
  });
  final List<MediaFolder> folders;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    MediaFolder? selectedFolder;
    for (final folder in folders) {
      if (folder.id == value) {
        selectedFolder = folder;
        break;
      }
    }
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selectedFolder == null ? null : value,
            decoration: const InputDecoration(
              labelText: 'Save in folder',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
            items: folders
                .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'New folder',
          onPressed: () async {
            final name = await _folderNameDialog(
              context,
              title: 'New media folder',
              action: 'Create',
              hintText: 'e.g. Workout clips',
            );
            if (!context.mounted || name == null) return;
            final folder = await context
                .read<MusicController>()
                .createMediaFolder(name);
            if (folder != null) onChanged(folder.id);
          },
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Folder options',
          enabled: selectedFolder != null,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) async {
            final folder = selectedFolder;
            if (folder == null) return;
            final music = context.read<MusicController>();
            if (action == 'rename') {
              final name = await _folderNameDialog(
                context,
                title: 'Rename folder',
                action: 'Save',
                initialValue: folder.name,
              );
              if (!context.mounted || name == null) return;
              await music.updateMediaFolder(folder, name);
              return;
            }
            if (action == 'delete') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete folder?'),
                  content: const Text(
                    'Only empty folders can be deleted. Saved items stay safe.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (!context.mounted || confirmed != true) return;
              final deleted = await music.deleteMediaFolder(folder);
              if (!deleted) return;
              for (final candidate in music.mediaFolders) {
                onChanged(candidate.id);
                break;
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'rename',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.drive_file_rename_outline_rounded),
                title: Text('Rename folder'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('Delete folder'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (double x = 10; x < size.width; x += 8) {
      final h = 18 + math.sin(x * 0.12).abs() * 55;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED UI WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.compact = false});
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, compact ? 18 : 26, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        if (!compact)
          TextButton(onPressed: () {}, child: const Text('See all')),
      ],
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand({this.light = false});
  final bool light;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/branding/nexmusic-logo.png',
          width: 44,
          height: 44,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'nexMusic',
        style: TextStyle(
          color: light ? Colors.white : null,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    ],
  );
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
      padding: const EdgeInsets.all(35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NexMusicApp.violet.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 44,
              color: NexMusicApp.violet.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, height: 1.45),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEETS & DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

Future<String?> _folderNameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String? hintText,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

void _showImportMenu(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'Add to nexMusic',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            subtitle: Text('Save a link, upload your own file, or trim audio'),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NexMusicApp.violet.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link_rounded, color: NexMusicApp.violet),
            ),
            title: const Text(
              'Save YouTube or web link',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Bookmark the original URL in your folders'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const SharedImportScreen(source: '', isLocalMedia: false),
                ),
              );
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF16736D).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_file_outlined,
                color: Color(0xFF16736D),
              ),
            ),
            title: const Text(
              'Upload my own media',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Private audio/video with optional trimming'),
            onTap: () async {
              final file = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: const ['mp4', 'mov', 'm4a', 'aac', 'mp3'],
              );
              final source = file?.path;
              if (!context.mounted || file == null || source == null) return;
              Navigator.pop(sheetContext);
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => OwnedMediaEditorScreen(
                    source: source,
                    suggestedName: file.name,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

void _simpleSheet(BuildContext context, String title, String body) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(color: Colors.grey, height: 1.45)),
        ],
      ),
    ),
  );
}

void _lyricsSheet(BuildContext context, Track track) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
        children: [
          Text(
            track.title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          Text(track.artist, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          const Text(
            'Lyrics will appear here',
            style: TextStyle(
              fontSize: 27,
              height: 1.7,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Connect your licensed lyrics provider later. The player UI and synchronized scrolling area are ready.',
            style: TextStyle(color: Colors.grey, fontSize: 17, height: 1.65),
          ),
        ],
      ),
    ),
  );
}

void _queueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      builder: (_, controller) => Consumer<MusicController>(
        builder: (_, music, _) {
          final queue = music.queue;
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Up next',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Playing from nexMusic Mix',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: queue.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SongTile(
                      track: queue[i],
                      number: i + 1,
                      queue: queue,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
