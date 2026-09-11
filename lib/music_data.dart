import 'package:flutter/material.dart';

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.url,
    required this.colors,
    this.explicit = false,
  });
  final String id, title, artist, album, url;
  final Duration duration;
  final List<Color> colors;
  final bool explicit;
}

class MusicCollection {
  const MusicCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.trackIds,
    required this.colors,
  });
  final String id, title, subtitle;
  final List<String> trackIds;
  final List<Color> colors;
}

class MoodStation {
  const MoodStation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.trackIds,
    required this.colors,
  });
  final String id, title, subtitle;
  final IconData icon;
  final List<String> trackIds;
  final List<Color> colors;
}

class MediaFolder {
  const MediaFolder({required this.id, required this.name});
  final String id, name;

  MediaFolder copyWith({String? name}) =>
      MediaFolder(id: id, name: name ?? this.name);
}

class SavedMedia {
  const SavedMedia({
    required this.id,
    required this.title,
    required this.kind,
    required this.folderId,
    this.sourceUrl,
    this.storagePath,
  });
  final String id, title, kind, folderId;
  final String? sourceUrl, storagePath;

  SavedMedia copyWith({
    String? title,
    String? folderId,
    String? sourceUrl,
    String? storagePath,
  }) => SavedMedia(
    id: id,
    title: title ?? this.title,
    kind: kind,
    folderId: folderId ?? this.folderId,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    storagePath: storagePath ?? this.storagePath,
  );
}

const tracks = <Track>[
  Track(
    id: 'midnight',
    title: 'Midnight Drive',
    artist: 'Aarav Ray',
    album: 'After Hours',
    duration: Duration(minutes: 4, seconds: 42),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    colors: [Color(0xFF4B2BBE), Color(0xFFFF4F9A)],
  ),
  Track(
    id: 'baarish',
    title: 'Baarish Ki Baat',
    artist: 'Mira Sen',
    album: 'Monsoon Letters',
    duration: Duration(minutes: 3, seconds: 58),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    colors: [Color(0xFF096A76), Color(0xFF36D1C4)],
  ),
  Track(
    id: 'city',
    title: 'City Lights',
    artist: 'Neon Valley',
    album: 'Electric Hearts',
    duration: Duration(minutes: 5, seconds: 4),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    colors: [Color(0xFF132B5B), Color(0xFF4A9DFF)],
  ),
  Track(
    id: 'safar',
    title: 'Safar',
    artist: 'Kabir & Co.',
    album: 'Open Roads',
    duration: Duration(minutes: 4, seconds: 16),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    colors: [Color(0xFFF0753C), Color(0xFFFFD36E)],
  ),
  Track(
    id: 'orbit',
    title: 'Orbit',
    artist: 'Lunar Club',
    album: 'Zero Gravity',
    duration: Duration(minutes: 6, seconds: 12),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    colors: [Color(0xFF121422), Color(0xFF8B6DFF)],
  ),
  Track(
    id: 'khwaab',
    title: 'Khwaab',
    artist: 'Rhea Malhotra',
    album: 'Soft Focus',
    duration: Duration(minutes: 3, seconds: 36),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    colors: [Color(0xFFB02D62), Color(0xFFFF91B9)],
  ),
  Track(
    id: 'slow',
    title: 'Slow Sunday',
    artist: 'The Paper Planes',
    album: 'Good Morning',
    duration: Duration(minutes: 4, seconds: 27),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
    colors: [Color(0xFF68713B), Color(0xFFD2DD87)],
  ),
  Track(
    id: 'higher',
    title: 'Higher Ground',
    artist: 'Nova Bloom',
    album: 'Bloom',
    duration: Duration(minutes: 5, seconds: 18),
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
    colors: [Color(0xFF74309B), Color(0xFFE96DF1)],
    explicit: true,
  ),
];

const collections = <MusicCollection>[
  MusicCollection(
    id: 'daily',
    title: 'Daily Mix 01',
    subtitle: 'Aarav Ray, Mira Sen, Kabir & Co.',
    trackIds: ['midnight', 'baarish', 'safar', 'khwaab'],
    colors: [Color(0xFF6C46EF), Color(0xFFFF4F9A)],
  ),
  MusicCollection(
    id: 'chill',
    title: 'Chill Station',
    subtitle: 'Soft beats for slower days',
    trackIds: ['slow', 'khwaab', 'baarish'],
    colors: [Color(0xFF12726F), Color(0xFF75E6C8)],
  ),
  MusicCollection(
    id: 'neon',
    title: 'Neon Nights',
    subtitle: 'Synth, electronic and indie pop',
    trackIds: ['city', 'orbit', 'higher', 'midnight'],
    colors: [Color(0xFF18214A), Color(0xFF5E7CFF)],
  ),
  MusicCollection(
    id: 'roads',
    title: 'Open Roads',
    subtitle: 'Made for long drives',
    trackIds: ['safar', 'midnight', 'higher'],
    colors: [Color(0xFFB54827), Color(0xFFFFC75B)],
  ),
];

const moodStations = <MoodStation>[
  MoodStation(
    id: 'focus-flow',
    title: 'Focus Flow',
    subtitle: 'Clean, low-friction tracks for work',
    icon: Icons.psychology_alt_rounded,
    trackIds: ['orbit', 'slow', 'city'],
    colors: [Color(0xFF1B5A7A), Color(0xFF6FE3C1)],
  ),
  MoodStation(
    id: 'late-drive',
    title: 'Late Drive',
    subtitle: 'Night-road energy without the clutter',
    icon: Icons.route_rounded,
    trackIds: ['midnight', 'city', 'safar', 'higher'],
    colors: [Color(0xFF5938C8), Color(0xFFFF6AA2)],
  ),
  MoodStation(
    id: 'reset',
    title: 'Soft Reset',
    subtitle: 'Gentle songs when everything feels loud',
    icon: Icons.spa_rounded,
    trackIds: ['khwaab', 'baarish', 'slow'],
    colors: [Color(0xFF0F766E), Color(0xFFB9E769)],
  ),
  MoodStation(
    id: 'boost',
    title: 'Boost',
    subtitle: 'Fast picks for walks and workouts',
    icon: Icons.bolt_rounded,
    trackIds: ['higher', 'safar', 'midnight'],
    colors: [Color(0xFFD94B4B), Color(0xFFFFC85C)],
  ),
];

Track trackById(String id) => tracks.firstWhere((track) => track.id == id);
List<Track> tracksFor(MusicCollection list) =>
    list.trackIds.map(trackById).toList();
List<Track> stationTracks(MoodStation station) =>
    station.trackIds.map(trackById).toList();
