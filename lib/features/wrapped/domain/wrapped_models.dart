import 'package:flutter/material.dart';
import '../../../shared/models/music_item.dart';

/// Represents a single ranked song in Miee Wrapped.
class WrappedTrackItem {
  final int rank;
  final String trackId;
  final String title;
  final String artist;
  final String? imageUrl;
  final int playCount;
  final int totalMinutes;
  final bool isFavorited;
  final MusicItem? musicItem; // For direct playback queue creation

  const WrappedTrackItem({
    required this.rank,
    required this.trackId,
    required this.title,
    required this.artist,
    this.imageUrl,
    required this.playCount,
    required this.totalMinutes,
    this.isFavorited = false,
    this.musicItem,
  });
}

/// Represents a single ranked artist in Miee Wrapped.
class WrappedArtistItem {
  final int rank;
  final String name;
  final int playCount;
  final int songsCount;
  final double totalHours;
  final String? imageUrl;
  final String quote;

  const WrappedArtistItem({
    required this.rank,
    required this.name,
    required this.playCount,
    required this.songsCount,
    required this.totalHours,
    this.imageUrl,
    required this.quote,
  });
}

/// Represents the top album in Miee Wrapped.
class WrappedAlbumItem {
  final String title;
  final String artist;
  final int playCount;
  final double totalHours;
  final String? artworkUrl;
  final String quote;

  const WrappedAlbumItem({
    required this.title,
    required this.artist,
    required this.playCount,
    required this.totalHours,
    this.artworkUrl,
    required this.quote,
  });
}

/// Milestone event for the Music Timeline slide (Slide 7).
class WrappedTimelineMilestone {
  final String monthLabel; // e.g. "Jan", "Apr", "Jul", "Oct"
  final String title;
  final String description;
  final String? imageUrl;

  const WrappedTimelineMilestone({
    required this.monthLabel,
    required this.title,
    required this.description,
    this.imageUrl,
  });
}

/// Language distribution item for Music Without Borders (Slide 8).
class WrappedLanguageItem {
  final String name;
  final int percentage;
  final Color color;

  const WrappedLanguageItem({
    required this.name,
    required this.percentage,
    required this.color,
  });
}

/// Listening context / time pattern item (Slide 9).
class WrappedContextItem {
  final String label;
  final String subLabel;
  final int percentage;
  final IconData icon;

  const WrappedContextItem({
    required this.label,
    required this.subLabel,
    required this.percentage,
    required this.icon,
  });
}

/// Personality archetype inferred from listening time distribution and diversity.
class ListeningArchetype {
  final String id;
  final String title;
  final String description;
  final List<String> tags;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;

  const ListeningArchetype({
    required this.id,
    required this.title,
    required this.description,
    required this.tags,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
  });

  static const List<ListeningArchetype> allArchetypes = [
    ListeningArchetype(
      id: 'midnight',
      title: 'The Midnight Listener',
      description: 'You find your peace in the quiet hours, with music that keeps you company.',
      tags: ['Late Night Vibes', 'Emotional Tracks', 'Consistent Listener'],
      icon: Icons.nightlight_round,
      primaryColor: Color(0xFFC87D6B), // Terracotta
      secondaryColor: Color(0xFF7D9D8B), // Soft Sage
    ),
    ListeningArchetype(
      id: 'explorer',
      title: 'The Explorer',
      description: 'Your appetite for sound has no boundaries. You roam freely across moods, cultures, and continents.',
      tags: ['Global Sounds', 'Endless Curiosity', 'Genre Hopper'],
      icon: Icons.explore_rounded,
      primaryColor: Color(0xFF7D9D8B),
      secondaryColor: Color(0xFFC87D6B),
    ),
    ListeningArchetype(
      id: 'repeat',
      title: 'The Repeat Listener',
      description: 'When you find a song you love, you live inside it until the melody becomes part of your soul.',
      tags: ['Deep Devotion', 'Infinite Loop', 'Loyal Listener'],
      icon: Icons.repeat_rounded,
      primaryColor: Color(0xFFD78D9B),
      secondaryColor: Color(0xFFE9C9B7),
    ),
    ListeningArchetype(
      id: 'curator',
      title: 'The Mood Curator',
      description: 'Every moment has a dedicated soundtrack. You craft emotional resonance through every playlist.',
      tags: ['Vibe Architect', 'Sunset Melodies', 'Acoustic Soul'],
      icon: Icons.filter_vintage_rounded,
      primaryColor: Color(0xFFE9C9B7),
      secondaryColor: Color(0xFF7D9D8B),
    ),
    ListeningArchetype(
      id: 'loyalist',
      title: 'The Album Loyalist',
      description: 'You appreciate music as a complete body of work, listening from start to finish as the artist intended.',
      tags: ['Front to Back', 'Sonic Purist', 'Vinyl Spirit'],
      icon: Icons.album_rounded,
      primaryColor: Color(0xFF3A252B),
      secondaryColor: Color(0xFFD78D9B),
    ),
    ListeningArchetype(
      id: 'newcomer',
      title: 'The Musical Newcomer',
      description: 'Your listening journey has just begun. As you explore more music, Miee will uncover your true musical personality.',
      tags: ['First Notes', 'Fresh Queue', 'Curious Ear'],
      icon: Icons.auto_awesome_rounded,
      primaryColor: Color(0xFF7D9D8B),
      secondaryColor: Color(0xFFC87D6B),
    ),
  ];
}

/// Complete aggregated statistical summary for Miee Wrapped across all 10 reference slides.
class WrappedSummary {
  final int year;
  final String timeframeLabel;
  final int totalMinutes;
  final double totalHours;
  final int totalTracks;
  final int totalArtists;
  final int totalAlbums;
  final int longestStreakDays;
  final int totalLanguages;
  final List<WrappedTrackItem> topTracks;
  final WrappedArtistItem? topArtist;
  final WrappedAlbumItem? topAlbum;
  final List<WrappedTimelineMilestone> timelineMilestones;
  final List<WrappedLanguageItem> languages;
  final List<WrappedContextItem> listeningContexts;
  final ListeningArchetype archetype;
  final int peakHour;
  final String peakHourLabel;
  final String peakDayName;
  final DateTime? topDay;
  final int topDayTrackCount;
  final bool isSampleData;
  final bool hasSufficientHistory;
  final int anniversaryYear;

  const WrappedSummary({
    required this.year,
    required this.timeframeLabel,
    required this.totalMinutes,
    required this.totalHours,
    required this.totalTracks,
    required this.totalArtists,
    required this.totalAlbums,
    required this.longestStreakDays,
    required this.totalLanguages,
    required this.topTracks,
    this.topArtist,
    this.topAlbum,
    required this.timelineMilestones,
    required this.languages,
    required this.listeningContexts,
    required this.archetype,
    required this.peakHour,
    required this.peakHourLabel,
    required this.peakDayName,
    this.topDay,
    required this.topDayTrackCount,
    required this.isSampleData,
    required this.hasSufficientHistory,
    this.anniversaryYear = 1,
  });

  WrappedTrackItem? get topTrack => topTracks.isNotEmpty ? topTracks.first : null;
}

/// Represents the user's eligibility and anniversary milestone status for Miee Wrapped.
///
/// Wrapped only unlocks once the user's account is at least 1 year old (>= 365 days / 1 full calendar year),
/// and unlocks iteratively year after year (Year 1 recap, Year 2 recap, Year 3 recap, etc.).
class WrappedEligibility {
  /// Whether the user's account has reached at least 1 year old.
  final bool isEligible;

  /// The original registration or first launch timestamp of this account.
  final DateTime accountStartDate;

  /// Number of full days since account creation.
  final int accountAgeDays;

  /// Number of completed 1-year cycles (0 if < 1 year, 1 if 1 year, 2 if 2 years, etc.).
  final int completedYears;

  /// The exact date when the next anniversary occurs.
  final DateTime nextAnniversaryDate;

  /// Days remaining until the next anniversary milestone.
  final int daysUntilNextAnniversary;

  /// List of completed milestone years available for viewing (e.g. [1] or [1, 2] or [1, 2, 3]).
  final List<int> availableYears;

  /// Active anniversary year being viewed (e.g. 1 for first year, 2 for second year).
  final int activeYear;

  /// Human-readable title for current status (e.g. "Year 1 Milestone", "1st Anniversary").
  final String milestoneTitle;

  /// Descriptive message explaining unlock status or milestone.
  final String statusDescription;

  const WrappedEligibility({
    required this.isEligible,
    required this.accountStartDate,
    required this.accountAgeDays,
    required this.completedYears,
    required this.nextAnniversaryDate,
    required this.daysUntilNextAnniversary,
    required this.availableYears,
    required this.activeYear,
    required this.milestoneTitle,
    required this.statusDescription,
  });

  /// Calculates leap-year safe anniversary date for any given number of years.
  static DateTime anniversaryForYear(DateTime start, int yearsToAdd) {
    final targetYear = start.year + yearsToAdd;
    var day = start.day;
    final month = start.month;
    if (month == 2 && day == 29) {
      final isLeap = (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0);
      if (!isLeap) day = 28;
    }
    return DateTime(
      targetYear,
      month,
      day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
    );
  }

  /// Computes eligibility accurately given an account start date and reference time.
  factory WrappedEligibility.compute({
    required DateTime accountStartDate,
    DateTime? currentTime,
    int? activeYearOverride,
    bool forceEligible = false,
  }) {
    final now = currentTime ?? DateTime.now();
    final difference = now.difference(accountStartDate);
    final ageDays = difference.isNegative ? 0 : difference.inDays;

    int completed = 0;
    while (true) {
      final nextAnniv = anniversaryForYear(accountStartDate, completed + 1);
      if (now.isAfter(nextAnniv) || now.isAtSameMomentAs(nextAnniv)) {
        completed++;
      } else {
        break;
      }
    }

    final effectiveCompleted = forceEligible ? (completed < 1 ? 1 : completed) : completed;
    final isEligible = forceEligible || (effectiveCompleted >= 1);

    final nextAnniversaryDate = anniversaryForYear(accountStartDate, effectiveCompleted + 1);
    final daysUntilNext = nextAnniversaryDate.difference(now).inDays;
    final daysRemaining = daysUntilNext < 0 ? 0 : daysUntilNext;

    final availableYears = List<int>.generate(effectiveCompleted, (i) => i + 1);
    final activeYear = (activeYearOverride != null && availableYears.contains(activeYearOverride))
        ? activeYearOverride
        : (availableYears.isNotEmpty ? availableYears.last : 1);

    final String milestoneTitle;
    final String statusDescription;

    if (isEligible) {
      milestoneTitle = 'Year $activeYear Milestone';
      statusDescription = effectiveCompleted == 1
          ? 'Your 1st Year Miee Wrapped is unlocked!'
          : 'Your Year $activeYear Wrapped is unlocked! ($effectiveCompleted years with Miee)';
    } else {
      milestoneTitle = '1st Year Milestone in Progress';
      statusDescription = 'Your Year 1 Miee Wrapped unlocks in $daysRemaining days.';
    }

    return WrappedEligibility(
      isEligible: isEligible,
      accountStartDate: accountStartDate,
      accountAgeDays: ageDays,
      completedYears: effectiveCompleted,
      nextAnniversaryDate: nextAnniversaryDate,
      daysUntilNextAnniversary: daysRemaining,
      availableYears: availableYears,
      activeYear: activeYear,
      milestoneTitle: milestoneTitle,
      statusDescription: statusDescription,
    );
  }
}
