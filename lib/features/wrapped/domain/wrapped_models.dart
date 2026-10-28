import 'package:flutter/material.dart';

/// Represents a single ranked song in Miee Wrapped.
class WrappedTrackItem {
  final int rank;
  final String trackId;
  final String title;
  final String artist;
  final String? imageUrl;
  final int playCount;
  final int totalMinutes;

  const WrappedTrackItem({
    required this.rank,
    required this.trackId,
    required this.title,
    required this.artist,
    this.imageUrl,
    required this.playCount,
    required this.totalMinutes,
  });
}

/// Represents a single ranked artist in Miee Wrapped.
class WrappedArtistItem {
  final int rank;
  final String name;
  final int playCount;
  final int totalMinutes;
  final String? imageUrl;

  const WrappedArtistItem({
    required this.rank,
    required this.name,
    required this.playCount,
    required this.totalMinutes,
    this.imageUrl,
  });
}

/// Personality archetype inferred from listening time distribution and diversity.
class ListeningArchetype {
  final String id;
  final String title;
  final String tagline;
  final String description;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;

  const ListeningArchetype({
    required this.id,
    required this.title,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
  });

  static const List<ListeningArchetype> allArchetypes = [
    ListeningArchetype(
      id: 'nocturnal',
      title: 'The Nocturnal Wanderer',
      tagline: 'Music is your late-night sanctuary',
      description: 'Most of your listening happened while the world was asleep. You gravitate towards deep, atmospheric melodies after dark.',
      icon: Icons.nightlight_round,
      primaryColor: Color(0xFF6366F1), // Deep Indigo
      secondaryColor: Color(0xFFC084FC),
    ),
    ListeningArchetype(
      id: 'sunrise',
      title: 'The Sunrise Architect',
      tagline: 'First track before first coffee',
      description: 'Your soundtrack starts at dawn. Morning energy sets your focus, powering productive days with rhythmic momentum.',
      icon: Icons.wb_sunny_rounded,
      primaryColor: Color(0xFFF59E0B), // Warm Amber
      secondaryColor: Color(0xFFF97316),
    ),
    ListeningArchetype(
      id: 'devotee',
      title: 'The Sonic Devotee',
      tagline: 'When you love an artist, you LOVE them',
      description: 'You fall deep into favorite discographies and put top tracks on repeat until the lyrics become muscle memory.',
      icon: Icons.favorite_rounded,
      primaryColor: Color(0xFFE11D48), // Rose Crimson
      secondaryColor: Color(0xFFFB7185),
    ),
    ListeningArchetype(
      id: 'explorer',
      title: 'The Endless Explorer',
      tagline: 'An appetite for every sonic horizon',
      description: 'Algorithms cannot pin you down. You bounce across artists, genres, and cultures with restless curiosity.',
      icon: Icons.explore_rounded,
      primaryColor: Color(0xFF10B981), // Emerald
      secondaryColor: Color(0xFF34D399),
    ),
    ListeningArchetype(
      id: 'connoisseur',
      title: 'The Melody Connoisseur',
      tagline: 'Curating perfection, track by track',
      description: 'You have a refined and balanced ear. Every listening session is intentional, spanning vibrant rhythms and quiet moments.',
      icon: Icons.album_rounded,
      primaryColor: Color(0xFFD78D9B), // Dusty Rose (Miee Signature)
      secondaryColor: Color(0xFFE9C9B7),
    ),
  ];
}

/// Complete aggregated statistical summary for Miee Wrapped.
class WrappedSummary {
  final int year;
  final String timeframeLabel;
  final int totalMinutes;
  final double totalHours;
  final int totalTracks;
  final int totalArtists;
  final List<WrappedTrackItem> topTracks;
  final List<WrappedArtistItem> topArtists;
  final ListeningArchetype archetype;
  final int peakHour;
  final String peakHourLabel;
  final String peakDayName;
  final DateTime? topDay;
  final int topDayTrackCount;
  final bool isSampleData;
  final bool hasSufficientHistory;

  const WrappedSummary({
    required this.year,
    required this.timeframeLabel,
    required this.totalMinutes,
    required this.totalHours,
    required this.totalTracks,
    required this.totalArtists,
    required this.topTracks,
    required this.topArtists,
    required this.archetype,
    required this.peakHour,
    required this.peakHourLabel,
    required this.peakDayName,
    this.topDay,
    required this.topDayTrackCount,
    required this.isSampleData,
    required this.hasSufficientHistory,
  });

  WrappedTrackItem? get topTrack => topTracks.isNotEmpty ? topTracks.first : null;
  WrappedArtistItem? get topArtist => topArtists.isNotEmpty ? topArtists.first : null;
}
