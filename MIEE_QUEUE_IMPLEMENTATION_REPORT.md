# MIEE — Playing Queue Implementation Report (`Q-01`–`Q-06`)

- **Package:** `com.example.miee` (`Miee`, `2.0.0+2`)
- **Scope:** Root-cause fixes for Playing Queue defects `Q-01` through `Q-06` across state management, content classification, language/recording deduplication, artist diversity, artwork propagation, and playback source identity synchronization.

---

## 1. Phase-by-Phase Root Causes, Changes & Design Decisions

### Phase 1 (`Q-01`) — Reactive Queue State & Initial Population
- **Original Root Cause:** `queueManagerProvider` in `lib/core/audio/providers.dart` is a plain `Provider<QueueManager>`, so `_queueManager.addTracks(...)` never notified `QueuePage`. Additionally, `expandQueueIfNeeded()` was only triggered *after* `await _handler.loadQueue(...)` + `await _handler.play()`, and `state = state.copyWith(currentTrack: _queueManager.currentTrack)` emitted an equal `currentTrack`, leaving `QueuePage` without a rebuild trigger until the next song started.
- **Changes Made:**
  - `lib/core/audio/playback_state.dart`: Added `QueueGenerationStatus` (`idle`, `loading`, `ready`, `empty`, `error`), `queueVersion`, `queueGenerationStatus`, and `queueGenerationError` to `PlaybackState` and `copyWith`.
  - `lib/core/audio/player_controller.dart`: Incremented `queueVersion` on every actual queue mutation (`setQueue`, `appendUpcomingTracks`, `expandQueueIfNeeded`, `playTrack` source replacement, `toggleShuffle`, `addTrackToQueue`, `playNext`, `removeTrackAt`, `reorderQueue`, `clearQueue`). Started `unawaited(expandQueueIfNeeded())` immediately inside `setQueue` when `finalQueue.length <= 2 && state.repeatMode != RepeatMode.one`, and updated `queueGenerationStatus` through `loading` -> `ready`/`empty`/`error`.
  - `lib/features/queue/presentation/queue_page.dart`: Watched `queueVersion`, `queueGenerationStatus`, and `queueGenerationError`, rendering a compact loading indicator (`"Finding related tracks..."`), error retry action, or empty-state hint when `upcomingList.isEmpty`.
- **Design Decision:** Using `queueVersion` + `QueueGenerationStatus` in `PlaybackState` avoids replacing `QueueManager` across the entire app while giving Riverpod `select(...)` consumers deterministic, minimal rebuilds.

### Phase 2 (`Q-02`) — Non-Music & Editorial Storytelling Filtering
- **Original Root Cause:** `MusicResultClassifier.isValidIndividualSong` and `RecommendationService.isLegitimateSong` allowed short spoken/editorial label clips (`"Lyricist Rokesh shares the..."`, `0:44` on `Divo Music`) because `isMusicLabelChannel` was treated as sufficient evidence for clips `>= 25s`.
- **Changes Made:**
  - `lib/features/youtube/domain/music_result_classifier.dart`: Added `_isEditorialOrSpokenClip(...)` inside `isValidIndividualSong`, rejecting contextual storytelling/editorial phrases (`shares the/his/her`, `talks about`, `speaks about`, `opens up`, `story behind`, `creator commentary`, `artist discussion`, `sneak peek`, `special/first glimpse`, `making story`) when explicit song release markers are absent, and requiring explicit musical evidence for short clips `< 65s`.
  - `lib/features/recommendations/data/recommendation_service.dart`: Added `editorialClipRegex` and `< 65s` musical-evidence checks in `isLegitimateSong`.

### Phase 3 (`Q-03`) — Recording Identity & Language-Aware Queue Filtering
- **Original Root Cause:** `SearchDeduplicator.computeRecordingKey` includes `|$lang`, causing `"Alaakaa Loova (Telugu)"` and `"Alaakaa Loova Lyrical (Tamil)"` to bypass queue duplicate detection; `getUpcomingQueueRecommendations` also ignored the seed track's detected language.
- **Changes Made:**
  - `lib/features/search/domain/search_deduplicator.dart`: Preserved `computeRecordingKey` for global search, and added `computeLanguageAgnosticRecordingKey` (collapsing language variants of the same underlying recording while keeping `Remix`, `Live`, `Acoustic`, `Cover`, `Instrumental` distinct).
  - `lib/features/recommendations/data/recommendation_service.dart`: Added `queueBaseKeys` / `seenPoolBaseKeys` checks in `getUpcomingQueueRecommendations` and scored candidates using `seedLanguage` (`+25.0` match, `-35.0` conflict) with `preferredLanguages` as secondary tie-breaker.
  - `lib/core/audio/player_controller.dart`: Enforced `computeLanguageAgnosticRecordingKey` in `expandQueueIfNeeded()`.

### Phase 4 (`Q-04`) — Strict Artist Diversity
- **Original Root Cause:** `getUpcomingQueueRecommendations` defined `maxTracksPerArtist = 2`, but subsequently ran `for (final entry in deferred)` which backfilled same-artist tracks into all remaining queue slots.
- **Changes Made:**
  - `lib/features/recommendations/data/recommendation_service.dart`: Removed the `deferred` same-artist backfill completely so `maxTracksPerArtist = 2` is strictly enforced; added bounded related-artist discovery (max 2 related artists via `ArtistRepository.searchArtists` + `getRelatedArtists` with 3s timeouts) when diverse candidates < `limit`.

### Phase 5 (`Q-05`) — Unified Artwork Propagation
- **Original Root Cause:** `ArtworkQuery.fromMusicItem(Track)` did not check `item.resolvedArtworkUrl`, and `QueuePage` passed empty `''` strings as `explicitUrl` / `imageUrl`.
- **Changes Made:**
  - `lib/features/artwork/domain/artwork_query.dart`: Preserved `item.resolvedArtworkUrl` (when non-YouTube) in `ArtworkQuery.fromMusicItem(Track)` without promoting YouTube thumbnails to `albumArtworkUrl`.
  - `lib/features/queue/presentation/queue_page.dart`: Passed `null` instead of `''` when `imageUrl.isEmpty` so `SongTile` / `MieeArtworkImage` never treats an empty string as an explicit URL.

### Phase 6 (`Q-06`) — Playback Source & Queue Identity Consistency
- **Original Root Cause:** `MieeAudioHandler._loadCurrentTrack` could switch to an alternate `fallbackCandidate.id` after stream resolution failure without validating full candidate identity or synchronizing `sourceId` back to `_queue` / `PlayerController`.
- **Changes Made:**
  - `lib/core/audio/audio_handler.dart`: Added `onPlaybackSourceResolved` callback; validated fallback candidates through `_sourceResolver.selectBestCandidate` in addition to duration checks; updated `_queue[_currentIndex]`'s `sourceId` while preserving recording identity (`id`, `title`, `artist`, `albumName`, `albumArtworkUrl`) and invoked `onPlaybackSourceResolved`.
  - `lib/core/audio/player_controller.dart`: Wired `_handler.onPlaybackSourceResolved` to synchronize `sourceId` on `_queueManager` and `state.currentTrack`, increment `queueVersion`, and persist the snapshot.

---

## 2. Verification Summary

- **Analyzer:** `flutter analyze --no-fatal-infos` on all modified `lib/` files + `test/playing_queue_root_cause_regression_test.dart` — **0 errors** (`21` pre-existing info lints).
- **Targeted Tests Executed:** **82 / 82 passed** across 8 test suites (see `MIEE_QUEUE_REGRESSION_TEST_REPORT.md`).
- **Real-Device Runtime Verification:** **Not executed in this phase** (Android device runtime verification on `vivo I2404` is still required to confirm live YouTube Innertube responses and end-to-end audio playback).
- **Remaining Risks / Notes:** `language_personalized_recommendations_test.dart` and `queue_extension_and_deduplication_test.dart` have pre-existing stale `MockYouTubeRepo` stubs missing `explodeCircuitCooldown` / `isExplodeCircuitOpen` from an earlier repository update.
