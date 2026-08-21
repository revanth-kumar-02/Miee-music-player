# Miee – Project Status & Phase Tracker

> **Last Updated:** 2026-08-21  
> **Version:** 1.0.0+1  
> **Flutter:** 3.47.1 (stable) · Dart 3.13.1  
> **Branch:** `main`

---

## ✅ Completed Phases

---

### Phase 1 — Foundation & Architecture Setup
**Commits:** `eef525f` → `5af6a52`

- Initialized Flutter project with clean directory architecture (`lib/app`, `lib/core`, `lib/features`, `lib/shared`)
- Set up Riverpod as the state management solution (`flutter_riverpod`)
- Wired up `go_router` for declarative navigation
- Established theming system with Google Fonts (`google_fonts`)
- Built reusable UI component library (cards, buttons, bottom sheets, mini-player)

---

### Phase 2 — Core Playback Engine
**Commits:** `dfe0d6e` → `1faecb8`

- Integrated `just_audio` for audio playback with full stream control (play, pause, seek, skip)
- Implemented `audio_service` for Android foreground service with persistent media notification
- Configured `audio_session` for audio focus management (interruptions, becoming noisy)
- Built `MieeAudioHandler` — the single audio engine subclassing `BaseAudioHandler`
- Built `PlayerController` for UI ↔ audio handler communication via Riverpod
- Resolved the Android foreground service / `AudioSession` circular deadlock by separating `initialize()` from the constructor

---

### Phase 3 — Local Music Library
**Commits:** `0a461cf` → `3a6c42b`

- Integrated `on_audio_query` for device-level music scanning
- Implemented `permission_handler` for Android `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE` permissions with in-app UI prompts
- Built Library screen with local songs list, artists, and albums
- Implemented rescan support with Hive caching to avoid repeated scans
- Fixed media type filtering and RenderFlex layout overflows in Home/Library screens

---

### Phase 4 — Offline-First Persistent Storage
**Commits:** `424698b` → `39c3cff`

- Integrated `hive` and `hive_flutter` for local persistent storage
- Built Hive adapters for: `TrackHiveModel`, `PlaylistHiveModel`, `QueueSnapshot`, `PlaybackHistoryEntry`, `HistoryEntry`
- Implemented `HiveService` for centralized box initialization and lifecycle management
- Built repositories: `PlaybackHistoryRepository`, `QueueStateRepository`, `PreferencesRepository`
- Implemented offline local music search across title, artist, and album fields

---

### Phase 5 — Playlist Management
**Commits:** `4df3215` → `ebd009e`

- Implemented full local playlist CRUD (Create, Read, Update, Delete)
- Built `AddToPlaylistSheet` bottom sheet for adding tracks to playlists
- Implemented `PlaylistDetailPage` with track listing and queue loading
- Added custom cover image picker (`image_picker`) for playlist artwork
- Normalized YouTube IDs in custom playlists to ensure cross-source compatibility

---

### Phase 6 — YouTube / Online Music Integration *(Partially Failing — see below)*
**Commits:** `c1a8e50` → `6c39d6e`

- Integrated `youtube_explode_dart ^3.1.0` as the YouTube data provider
- Built `YouTubeRepository` for search: uses `YoutubeExplode.search.search()` with `TypeFilters.video`
- Implemented smart result filtering:
  - Excludes live streams, podcasts, documentaries, karaoke, reactions
  - Filters by duration (30s < track ≤ 10 minutes)
  - Heuristic scoring to surface official audio releases (VEVO, "- Topic" channels, "Official Audio" titles)
- Built `YouTubeAudioResolver` (singleton) for resolving video IDs → direct audio-only stream URLs
  - Uses `YoutubeApiClient.androidSdkless` and `YoutubeApiClient.ios` clients
  - Selects highest bitrate audio-only stream from the manifest
  - In-memory URL cache (bounded to 100 entries) with cache validation
  - Background file download to local temp cache (`.m4a`) for mobile playback
- Integrated resolver into `MieeAudioHandler._loadCurrentTrack()` with self-healing retry on `setUrl` failure
- Built unified `MusicItem` abstraction to handle both local and YouTube tracks in the same queue
- Added `SmartSourceSelection` logic (user preference: local-first vs. online-first)
- Web platform playback partially attempted but blocked (see known issues below)

---

### Phase 7 — Search Experience
**Commits:** `1b8e190` → `e047ea3`

- Unified search across local library and YouTube results on a single screen
- Implemented search auto-suggestions API
- Built result scoring and filtering pipeline
- Fixed Hive bug that caused search results to be lost between sessions

---

### Phase 8 — Settings, Profile & Sync
**Commits:** `45d7277` → `f093031`

- Complete Settings module rewrite using Clean Architecture
- Built local Profile system with avatar, display name, and preferences
- Integrated `supabase_flutter` for offline-first sync layer
- `connectivity_plus` used for network state detection to gate sync operations
- Moved profile into the Settings page

---

### Phase 9 — UI Polish & Design System
**Commits:** `dc92a7f` → `bb41fac`

- Production-quality polish pass: consistent spacing, typography, shadows
- Integrated official Miee brand logo and configured launcher icons via `flutter_launcher_icons`
- Enforced a single permanent dark theme (removed light/dark/system switcher)
- Built responsive `MainAppShell` with Frosted Glass design (Web v2)
- Implemented live animated waveform visualizer on the Player screen
- Fixed `BackdropFilter` GPU whiteout crash on Vivo devices (blur reduced to 20.0)
- Minimalist top app bars with centered titles

---

### Phase 10 — Queue Management
**Commits:** `ad9f2bf` → `a15b7f2`

- Interactive play queue with drag-to-reorder and swipe-to-remove
- `reorderQueue()` implemented in `MieeAudioHandler` keeping the active track index in sync
- Queue state persisted via `QueueStateRepository` (Hive-backed)

---

## ⚠️ Known Issues / Failing Features

---

### 🔴 YouTube Music Integration — Stream Playback Failing

**Provider used:** [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart) v3.1.0

The YouTube integration uses `youtube_explode_dart` — a reverse-engineered Dart library that scrapes YouTube's internal APIs to resolve video stream manifests without requiring an official API key. It is **not** an official YouTube API integration.

#### What is failing:
- Stream manifest resolution is intermittently failing with `YoutubeExplodeException` errors
- HTTP 403 Forbidden errors on resolved stream URLs (Google's CDN blocking)
- The `androidSdkless` and `ios` `ytClients` workaround has only partially mitigated the 403 issue
- On Flutter Web, stream URLs expire very quickly and CORS restrictions prevent direct playback
- The self-healing retry logic in `MieeAudioHandler` helps but does not fully prevent failures
- YouTube regularly changes internal API contracts, causing `youtube_explode_dart` to break until the package is updated

#### Root cause:
`youtube_explode_dart` relies on reverse-engineering YouTube's private web/Android/iOS API endpoints. Google actively detects and blocks unauthorized clients. The package needs frequent updates to stay working and offers **no stability guarantees** for production apps.

#### Potential fixes (not yet implemented):
1. Replace `youtube_explode_dart` with the **official YouTube Data API v3** for search (requires API key and quota) + **YouTube IFrame Player** for web playback
2. Use **Piped API** (open-source YouTube frontend) as a backend proxy for stream URLs
3. Use **InnerTube API** with a proper session token and visitor data
4. Migrate to a self-hosted `yt-dlp` backend that handles stream extraction server-side

---

## 📦 Dependencies Summary

| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management |
| `go_router` | Navigation |
| `just_audio` | Audio playback engine |
| `audio_service` | Background playback + media notification |
| `audio_session` | Audio focus management |
| `on_audio_query` | Local music scanning |
| `permission_handler` | Runtime permissions |
| `hive` / `hive_flutter` | Local persistent storage |
| `youtube_explode_dart` | YouTube search + stream resolution *(unstable)* |
| `supabase_flutter` | Cloud sync |
| `connectivity_plus` | Network state |
| `dio` | HTTP client |
| `path_provider` | File system paths |
| `image_picker` | Playlist cover images |
| `google_fonts` | Typography |
| `share_plus` | Share functionality |
| `url_launcher` | External URL handling |

---

*This document is auto-generated from the Miee project codebase and git history.*
