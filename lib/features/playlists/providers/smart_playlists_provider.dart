import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../library/providers/library_providers.dart';
import '../domain/playlist_model.dart';

enum SmartPlaylistType {
  recentlyAdded,
  mostRepeated,
  lateNightChill,
}

class SmartPlaylistDescriptor {
  final SmartPlaylistType type;
  final String title;
  final String subtitle;
  final String iconName;

  const SmartPlaylistDescriptor({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.iconName,
  });
}

const kSmartPlaylistDescriptors = [
  SmartPlaylistDescriptor(
    type: SmartPlaylistType.mostRepeated,
    title: 'On Repeat',
    subtitle: 'Your most played tracks',
    iconName: 'repeat_rounded',
  ),
  SmartPlaylistDescriptor(
    type: SmartPlaylistType.recentlyAdded,
    title: 'Recently Added',
    subtitle: 'Latest additions to your library',
    iconName: 'history_rounded',
  ),
  SmartPlaylistDescriptor(
    type: SmartPlaylistType.lateNightChill,
    title: 'Late Night Chill',
    subtitle: 'Down-tempo and acoustic evening moods',
    iconName: 'bedtime_rounded',
  ),
];

final smartPlaylistsProvider = Provider<List<PlaylistModel>>((ref) {
  final List<Track> favorites = ref.watch(favoritesProvider);
  final mostPlayedRepo = ref.watch(mostPlayedRepositoryProvider);

  final List<PlaylistModel> smartPlaylists = [];

  // 1. "On Repeat" (Tracks sorted by play count descending)
  final mostPlayedEntries = mostPlayedRepo.getMostPlayed(limit: 30);
  final Set<String> topTrackIds = mostPlayedEntries.map((e) => e.key).toSet();
  final onRepeatTracks = favorites.where((Track t) => topTrackIds.contains(t.id)).toList();
  onRepeatTracks.sort((Track a, Track b) {
    final countA = mostPlayedRepo.getCount(a.id);
    final countB = mostPlayedRepo.getCount(b.id);
    return countB.compareTo(countA);
  });

  if (onRepeatTracks.isNotEmpty) {
    smartPlaylists.add(
      PlaylistModel(
        id: 'smart_on_repeat',
        name: 'On Repeat',
        tracks: onRepeatTracks,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      ),
    );
  }

  // 2. "Recently Added" (Tracks in reverse chronological order)
  final recentlyAdded = List<Track>.from(favorites.reversed.take(30));
  if (recentlyAdded.isNotEmpty) {
    smartPlaylists.add(
      PlaylistModel(
        id: 'smart_recently_added',
        name: 'Recently Added',
        tracks: recentlyAdded,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      ),
    );
  }

  // 3. "Late Night Chill" (Acoustic / Soft / Mellow Tracks)
  final chillTracks = favorites.where((Track t) {
    final title = t.title.toLowerCase();
    final artist = t.artist.toLowerCase();
    return title.contains('chill') ||
        title.contains('acoustic') ||
        title.contains('slow') ||
        title.contains('night') ||
        title.contains('ambient') ||
        title.contains('lo-fi') ||
        artist.contains('ambient') ||
        artist.contains('chill');
  }).take(25).toList();

  if (chillTracks.isNotEmpty) {
    smartPlaylists.add(
      PlaylistModel(
        id: 'smart_late_night_chill',
        name: 'Late Night Chill',
        tracks: chillTracks,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      ),
    );
  }

  return smartPlaylists;
});
