# MIEE 2.0 — Remediation Changelog

## Modified Source Files

- `lib/features/search/data/playback_source_resolver.dart`
  - Added `Set<String> excludeVideoIds = const {}` to `resolveCandidate`, `_resolveCandidateInternal`, and `_pickBestScoredCandidate` so failed video IDs are bypassed in cache, in-flight deduplication, and candidate scoring.
- `lib/core/audio/audio_handler.dart`
  - Updated `_loadCurrentTrack` fallback loop to pass `excludeVideoIds` and retry up to 2 alternate candidates when stream resolution fails.
- `lib/features/player/presentation/player_page.dart`
  - Added `playbackError` / `playbackStatus` listeners and an inline error banner with a **Retry** action in both mobile and desktop Now Playing views.
- `lib/core/audio/player_controller.dart`
  - Moved `_recordRecentlyPlayed` out of `mediaItem` listener into `_playerStateSub` so only confirmed `PlaybackStatus.playing` tracks are recorded (deduplicated via `_lastRecordedTrackKey`).
- `lib/features/library/data/recently_played_repository.dart`
  - Updated `recordPlay` and `_resolveEntryTrack` to use `copyWith(...)`, preserving `albumArtworkUrl`, `albumName`, `sourceProvider`, `sourceId`, `rawTitle`, `rawArtist`, and `youtubeThumbnailUrl`.
- `lib/features/search/domain/canonical_music_ranker.dart`
  - Added derivative edit penalties (`slowedReverb`, `spedUpNightcore`, `mashupRemake`, `audioModified`, `statusVideo`, `fanEdit`, `fourKEdit`, `promoTeaser`, `karaokeVersion`, `coverSong`, `compilationMix`) when not requested by `QueryIntent`, plus official `- Topic` / `VEVO` channel boost.
- `lib/shared/utils/display_title_normalizer.dart`
  - Added ripper/download-site regex (`MassTamilan`, `Isaimini`, `StarMusiq`, etc.), trailing `- Video` / `- Audio` / `- Topic` stripping, and `DisplayTitleNormalizer.normalizeArtist(...)`.
- `lib/features/artwork/presentation/miee_artwork_image.dart`
  - Updated loading and neutral-fallback rendering to display valid `fallbackThumbnailUrl` / `explicitUrl` when available instead of blank placeholders.
- `lib/features/settings/presentation/settings_page.dart`
  - Fixed `_calculateCacheSize` and `_clearArtworkCache` to target `${docDir.path}/artwork_cache` as well as temp files; replaced clipped `36px` artist chip list with `Wrap`; styled `Preferred Playback Source` `DropdownButton` for high contrast.
- `lib/features/playlists/presentation/local_songs_page.dart`
  - Set `color: AppColors.cocoaPlum` on `AppHeader` back and refresh `IconButton` icons.
- `lib/features/home/presentation/home_page.dart`
  - Increased bottom scroll clearance to `120.0 + MediaQuery.of(context).padding.bottom` on mobile so `Made for you` and lower shelves clear the floating navigation bar.
- `lib/features/library/data/playlists_repository.dart`
  - Added case-insensitive duplicate guard in `createPlaylist` to return the existing playlist ID instead of creating case-variant duplicates.
- `lib/features/search/presentation/search_page.dart`
  - Replaced hardcoded `Lo-fi Beats`, `Focus Mix`, `Anime OST` with dynamic trending tracks from `RecommendationSections` and `searchHistoryProvider`, with offline fallback.
- `lib/features/recommendations/data/daily_mix_service.dart`
  - Derived cold-start artists from live `trendingTracks` before falling back to `staticCuratedArtists`.
- `lib/features/recommendations/data/recommendation_service.dart`
  - Derived exploration artists from live `trendingTracks` and `recentReleases` before falling back to `staticCuratedArtists`.
- `lib/features/home/presentation/widgets/artist_rotation_section.dart`
  - Derived initial artists from `widget.initialTracks` before falling back to `staticCuratedArtists`.
- `lib/features/desktop/presentation/views/desktop_dashboard_view.dart`
  - Wired notification bell button to `NotificationSheet.show(context)`.
- `lib/features/desktop/presentation/views/desktop_local_library_view.dart`
  - Wired album card `onTap` to play matching album tracks via `PlayerController.selectTrack`.
- `lib/features/desktop/presentation/widgets/desktop_sidebar.dart`
  - Wired System Info & Diagnostics utility button to `onSectionChanged(DesktopNavSection.settings)`.
- `lib/features/desktop/presentation/widgets/left_console_rail.dart`
  - Wired Record Crates items to `onSectionChanged(DesktopNavSection.cratesAndMixes)`.

## Added Test Files

- `test/remediation_rd_hc_regression_test.dart`
  - Regression unit tests covering `RD-01` through `RD-05`.
