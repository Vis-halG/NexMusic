import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'music_controller.dart';
import 'music_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const _NexMusicErrorView();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    await GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? DefaultFirebaseOptions.ios.iosClientId
          : null,
    );
  }
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (_) => MusicController(
        preferences,
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
        storage: FirebaseStorage.instance,
      ),
      child: const NexMusicApp(),
    ),
  );
}

class _NexMusicErrorView extends StatelessWidget {
  const _NexMusicErrorView();

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: Material(
      // OLED true black for error overlay
      color: Color(0xFF000000),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFFB86B),
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'This screen could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Go back and try again. Your music and saved data are safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class NexMusicApp extends StatelessWidget {
  const NexMusicApp({super.key});

  /// Brand violet — NexSociety-style vivid violet identity.
  static const violet = Color(0xFF7C3AED);

  /// Aurora pink accent — used for gradients and highlights.
  static const flamingo = Color(0xFFEC4899);

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: violet,
          brightness: brightness,
          // OLED true-black dark surface (NexSociety One UI style)
          surface: dark ? const Color(0xFF131318) : Colors.white,
          primary: violet,
          secondary: flamingo,
        ).copyWith(
          // Keep scaffold backgrounds OLED-true on dark
          surfaceContainer: dark
              ? const Color(0xFF1A1A20)
              : const Color(0xFFF4F4F8),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // OLED true black canvas in dark mode
      scaffoldBackgroundColor: dark
          ? const Color(0xFF000000)
          : const Color(0xFFF6F6F6),
      fontFamily: 'Poppins',
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: violet,
        foregroundColor: Colors.white,
        toolbarHeight: 64,
        titleSpacing: 20,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF131318) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        margin: EdgeInsets.zero,
      ),
      // NavigationBar is replaced by custom _MusicBottomNav — keep minimal
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF0D0D12) : Colors.white,
        indicatorColor: violet.withValues(alpha: 0.17),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1C1C22) : const Color(0xFFF0F0F6),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(20),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(20),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: violet, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: TextStyle(
          color: dark ? Colors.white38 : Colors.black38,
          fontFamily: 'Poppins',
          fontSize: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(color: dark ? Colors.white24 : Colors.black12),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: violet,
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: violet,
        thumbColor: violet,
        overlayColor: violet.withValues(alpha: 0.18),
        inactiveTrackColor: dark ? Colors.white24 : Colors.black12,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        labelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context
        .select<MusicController, ({bool dark, bool signedIn})>(
          (music) => (dark: music.darkMode, signedIn: music.signedIn),
        );
    return MaterialApp(
      title: 'nexMusic',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: appState.dark ? ThemeMode.dark : ThemeMode.light,
      scrollBehavior: const NexMusicScrollBehavior(),
      home: appState.signedIn ? const MusicShell() : const WelcomeScreen(),
    );
  }
}

/// Keeps touch scrolling fluid while retaining mouse and trackpad dragging on
/// the desktop/web builds. This mirrors the native-feeling physics used by
/// NexSociety.
class NexMusicScrollBehavior extends MaterialScrollBehavior {
  const NexMusicScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
