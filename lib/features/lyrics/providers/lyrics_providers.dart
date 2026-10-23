import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/music_item.dart';
import '../data/lyrics_repository.dart';
import '../domain/lyrics_model.dart';

/// Provider for the [LyricsRepository] abstraction.
/// Can be overridden in tests with mock or deterministic fixture implementations.
final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  return LrclibLyricsRepository();
});

/// Provider that resolves synchronized or plain lyrics for the active track.
final lyricsProvider = FutureProvider.family<LyricsData, MusicItem?>((ref, track) async {
  if (track == null) return LyricsData.empty;

  final repository = ref.watch(lyricsRepositoryProvider);
  return await repository.getLyrics(track);
});
