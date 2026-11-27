# MIEE — Playing Queue Changed Files

| File | Why It Was Modified |
|---|---|
| `lib/core/audio/playback_state.dart` | Added `QueueGenerationStatus` enum and `queueVersion`, `queueGenerationStatus`, and `queueGenerationError` fields to `PlaybackState` (`Q-01`). |
| `lib/core/audio/player_controller.dart` | Incremented `queueVersion` on all queue mutations; started immediate `expandQueueIfNeeded()` on 1-track queues; tracked `loading`/`ready`/`empty`/`error` generation states (`Q-01`); enforced `computeLanguageAgnosticRecordingKey` in expansion (`Q-03`); wired `_handler.onPlaybackSourceResolved` (`Q-06`). |
| `lib/core/audio/audio_handler.dart` | Added `onPlaybackSourceResolved` callback, strengthened fallback candidate validation via `_sourceResolver.selectBestCandidate`, and synced `sourceId` on `_queue` while preserving recording identity (`Q-06`). |
| `lib/features/queue/presentation/queue_page.dart` | Watched `queueVersion`, `queueGenerationStatus`, and `queueGenerationError` (`Q-01`); rendered loading/error/empty Next Up states (`Q-01`); passed `null` instead of `''` for empty artwork URLs (`Q-05`). |
| `lib/features/youtube/domain/music_result_classifier.dart` | Added `_isEditorialOrSpokenClip` in `isValidIndividualSong` to reject editorial storytelling/interview clips and unverified `< 65s` spoken clips (`Q-02`). |
| `lib/features/recommendations/data/recommendation_service.dart` | Added editorial/short-clip checks in `isLegitimateSong` (`Q-02`); added `computeLanguageAgnosticRecordingKey` deduplication and seed-language scoring in `getUpcomingQueueRecommendations` (`Q-03`); removed `deferred` same-artist backfill and added bounded related-artist discovery (`Q-04`). |
| `lib/features/search/domain/search_deduplicator.dart` | Added `computeLanguageAgnosticRecordingKey` without altering existing `computeRecordingKey` (`Q-03`). |
| `lib/features/artwork/domain/artwork_query.dart` | Preserved `Track.resolvedArtworkUrl` in `ArtworkQuery.fromMusicItem` without promoting YouTube thumbnails to album artwork (`Q-05`). |
| `test/playing_queue_root_cause_regression_test.dart` | Added deterministic unit and widget regression tests covering `Q-01` through `Q-06`. |
