# Miee — Universal Artist Metadata, Unified Song/Artist Search, and Artist Profiles

## Executive Summary
This document outlines the architectural enhancements and UI polish implemented for Miee:
1. **Issue 1 — Universal Artist Image Correctness**: Implemented `ArtistAvatar` with Deezer CDN empty-silhouette hash filtering (`d41d8cd98f00b204e9800998ecf8427e`), curated catalog fallback for major artists (Tamil, Telugu, Hindi, Malayalam, Kannada, Western), and neutral initials fallback.
2. **Issue 2 — Unified Song & Artist Search**: Replaced fragmented search with a unified search experience supporting filters (`All`, `Songs`, `Artists`, `Albums`), concurrent YouTube and Deezer search, responsive loading/empty/retryable error states, and canonical song deduplication without merging different artists' songs.
3. **Issue 3 — Reusable Artist Profile Page**: Created a single unified route `/artist/:id` used across Home and Search. Provides artist portrait header, fan count, Play/Shuffle actions, top tracks via Deezer with YouTube playback integration, verified album discography with release years, and empty/error states.
4. **Issue 4 — Home & Player UI Corrections**:
   - Replaced leading waveform indicator with album artwork in the Home song list and Queue's NOW PLAYING row.
   - Preserved mini-player and expanded player waveform animations.
   - Modestly expanded Now Playing waveform width by +12.5% (from 240.0 to 270.0).
   - Filtered out podcasts, full movies, and long jukeboxes from recommendations.

---

## Architectural Details

### 1. Universal Artist Avatar (`lib/shared/widgets/artist_avatar.dart`)
- **Validation**: Rejects URLs containing Deezer default empty silhouette hash (`d41d8cd98f00b204e9800998ecf8427e`) or malformed routes (`/artist//`).
- **Catalog Fallback**: Cross-references Deezer's curated artist repository when an artist lacks a direct image URL or has an invalid/broken link.
- **Initials Fallback**: Extracts the artist's first letter cleanly and styles with a neutral surface container background.
- **Decache Optimization**: Decodes images with `cacheWidth: 160` and `cacheHeight: 160` to conserve memory on low-RAM devices.

### 2. Unified Search Pipeline
- **Models (`SearchState`)**:
  - `onlineArtists`: Verified `ArtistModel` entities from Deezer and the curated catalog.
  - `onlineAlbums`: Verified `ArtistAlbum` entities with cover artwork, release date, and track counts.
  - `youtubeResults`: Deduplicated online song entities.
  - `activeFilter`: `'All'`, `'Songs'`, `'Artists'`, `'Albums'`.
- **Search Notifier (`SearchNotifier`)**:
  - Concurrently queries YouTube Explode (for audio tracks) and Deezer API (for artists and albums).
  - Integrates `SearchDeduplicator` to rank and group duplicate video uploads while keeping separate tracks and covers intact.
  - Provides instant tab filtering without re-fetching network resources.
  - Displays retry button if network fails.

### 3. Shared Reusable Artist Profile (`lib/features/library/presentation/artist_detail_page.dart`)
- **Unified Entry Points**:
  - Home → Favourite Artists → `/artist/:id` (passes `extra: artist`)
  - Home → Explore Related Artists → `/artist/:id` (passes `extra: artist`)
  - Search → Artists filter/results → `/artist/:id` (passes `extra: artist`)
- **Profile Header**: High-resolution artist portrait with smooth gradient overlay, name, fan count, and genres.
- **Top Tracks**: Fetches Deezer top tracks (or local tracks if offline), maps them to Miee `Track` models, and routes playback through `playerControllerProvider`.
- **Discography**: Displays verified albums with cover artwork and release years.

### 4. Player & Home UI Polish
- **Song Tile Leading Indicator**: In `lib/shared/widgets/song_tile.dart`, updated `leadingWidget` logic so that whenever `imageUrl` is provided, the album artwork is displayed even when `isPlaying == true`. This updates both the Home song list and Queue's NOW PLAYING row to show album artwork instead of the leading mini-equalizer.
- **Waveform Width**: Expanded `maxWidth` from `240.0` to `270.0` (+12.5%) in `lib/features/player/presentation/player_page.dart`.
- **Discover More Filters**: In `lib/features/recommendations/data/recommendation_service.dart`, added `isLegitimateSong(video)` filtering videos exceeding 18 minutes or matching keyword patterns (`full movie`, `podcast`, `all songs`, `jukebox`, `interview`, `audio launch`).

---

## Files Changed

| File | Change |
|---|---|
| `lib/shared/widgets/artist_avatar.dart` | New universal verified artist avatar with silhouette detection and fallbacks. |
| `lib/shared/widgets/widgets.dart` | Exported `ArtistAvatar`. |
| `lib/shared/widgets/song_tile.dart` | Preserved album artwork on playing tracks in song list and queue. |
| `lib/features/onboarding/data/artist_discovery_repository.dart` | Added `ArtistAlbum`, `ArtistTopTrack`, `getArtistTopTracks`, `getArtistAlbums`, `findCuratedByName`. |
| `lib/features/onboarding/domain/artist_model.dart` | Added `copyWith` method. |
| `lib/features/search/domain/search_state.dart` | Extended with `onlineArtists`, `onlineAlbums`, `activeFilter`, counters. |
| `lib/features/search/data/search_repository.dart` | Integrated Deezer artist and album search alongside YouTube Explode. |
| `lib/features/search/providers/search_providers.dart` | Concurrently resolves online artists and albums; added `setFilter`. |
| `lib/features/search/presentation/search_page.dart` | Unified filter chips (`All`, `Songs`, `Artists`, `Albums`), artist cards with `ArtistAvatar`, retry button. |
| `lib/features/home/presentation/home_page.dart` | Favourite & Related artists use `ArtistAvatar` and navigate to shared `/artist/:id`. |
| `lib/features/library/presentation/artist_detail_page.dart` | Complete rewrite supporting online and local artists with top tracks & albums. |
| `lib/app/router/app_router.dart` | Passes `state.extra` to `ArtistDetailPage`. |
| `lib/features/player/presentation/player_page.dart` | Modestly increased waveform container width by 12.5% to `270.0`. |
| `lib/features/recommendations/data/recommendation_service.dart` | Added `isLegitimateSong` filtering movies, podcasts, and massive jukeboxes. |

---

## Validation & Verification

### Unit and Widget Tests
Run command:
```bash
flutter test test/now_playing_refinement_test.dart test/search_deduplication_test.dart test/artist_discovery_and_images_test.dart test/unified_search_and_artist_profile_test.dart
```
**Result**: 35 passed, 0 failed.

### Static Analysis
Run command:
```bash
flutter analyze lib/shared/widgets lib/features/onboarding lib/features/search lib/features/library lib/features/home lib/features/player lib/features/recommendations
```
**Result**: 0 errors.

### Device Deployment
- Built debug APK and installed on physical device `10BF5809GA0029L` (Vivo I2404).
- Gradle daemons and Kotlin compiler processes terminated post-build to conserve RAM.
