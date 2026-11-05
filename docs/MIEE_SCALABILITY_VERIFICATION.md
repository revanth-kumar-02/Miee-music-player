# Miee — Scalability Audit Verification & Ground Truth Report

**Document Version:** 1.0.0  
**Audit Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Scope:** Verification of initial scalability findings against actual repository implementation  

---

## 1. Executive Summary

This report rigorously audits and verifies every major finding from the initial **Miee 10K Scalability Audit** against the actual source code, database migrations, configuration, and dependencies in the Miee repository.

### Key Verification Verdicts:
1. **The "70,000 Simultaneous Full-Table Scans" Claim is PARTIALLY INCORRECT.**
   - While `SyncManager.triggerSync()` does execute 7 unpaginated queries for a user's library, **automatic sync on startup and on network reconnect is actually commented out** in both [`SplashPage`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/splash/presentation/splash_page.dart#L25) and [`SyncManager`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L41).
   - Furthermore, `liked_songs`, `playlists`, and `history` have B-tree indexes on `user_id`. They execute **Index Scans**, not database-wide sequential full-table scans.
   - However, `playlist_tracks` **lacks an index on `user_id`**, making that specific query an unindexed sequential scan on that table.
2. **The Supabase Realtime Quota Failure is VERIFIED CORRECT.**
   - Listening Rooms use Supabase Realtime channels with Postgres Change Data Capture (`onPostgresChanges` across 4 tables).
   - Supabase Free tier caps concurrent WebSocket connections at 200; Pro tier includes 500. A target of 1,000 to 10,000 simultaneous room listeners **will be hard-blocked by Supabase Realtime gateway quotas** unless connection quotas are explicitly upgraded.
3. **The Playback Zero-Server-Bandwidth Finding is VERIFIED CORRECT.**
   - Native audio playback streams directly from Google Video CDN (`googlevideo.com`) to `just_audio` (ExoPlayer) on the client device. Miee servers carry 0 MB of audio data.
4. **Artwork Memory Caching is VERIFIED CORRECT.**
   - The app uses standard Flutter `Image.network` across all UI widgets without persistent disk caching.

---

## 2. Detailed Finding-by-Finding Verification

```
+---------------------------------------------------------------------------------------------------------+
|                                    Audit Finding Verification Matrix                                    |
+---------+------------------------------+--------------------+-------------------------------------------+
| Item ID | Component                    | Audit Claim Status | Technical Reality                         |
+---------+------------------------------+--------------------+-------------------------------------------+
| VER-01  | SyncManager Auto-Sync Storm  | PARTIALLY CORRECT  | Startup & reconnect auto-sync are disabled|
| VER-02  | Sync Full-Table Scan Claim   | PARTIALLY CORRECT  | Index Scan on user_id; unpaginated fetch  |
| VER-03  | playlist_tracks Missing Index| VERIFIED DEFECT    | No index on user_id; sequential scan      |
| VER-04  | room_messages Missing Index  | VERIFIED DEFECT    | No index on (room_id, created_at)         |
| VER-05  | Supabase Realtime Limits     | VERIFIED CORRECT   | Hard ceiling at 200 (Free) or 500 (Pro)   |
| VER-06  | Database Connection Ceiling  | VERIFIED CORRECT   | Direct PostgreSQL caps at 60-120 conn     |
| VER-07  | Playback Audio Bandwidth     | VERIFIED CORRECT   | 0 MB server load; client-to-CDN direct    |
| VER-08  | Artwork Cache Lifecycle      | VERIFIED CORRECT   | In-memory RAM only; full redownload on boot|
| VER-09  | YouTube Data API Quota       | VERIFIED CORRECT   | 10,000 units/day exhausted in 100 queries |
+---------+------------------------------+--------------------+-------------------------------------------+
```

---

### Finding 1: `SyncManager.triggerSync()` Behavior & Auto-Sync Storms
* **Audit Claim:** When 10,000 users launch the app simultaneously, 70,000 cascading unpaginated database queries are triggered instantly.
* **Code Location:** 
  - [`lib/core/sync/sync_manager.dart` (lines 38–44, 228–380)](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L38-L44)
  - [`lib/features/splash/presentation/splash_page.dart` (lines 23–26)](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/splash/presentation/splash_page.dart#L23-L26)
* **Actual Observed Code:**
  ```dart
  // In SyncManager constructor:
  _networkSubscription = _networkMonitor.onConnectivityChanged.listen((isOnline) {
    // if (isOnline) {
    //   triggerSync();
    // }
  });

  // In SplashPage.initState():
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ref.read(syncManagerProvider).triggerSync();
  });
  ```
* **Evaluation:** **PARTIALLY CORRECT (Overstated immediate risk; verified structural flaw).**
  - **Correction:** In the current codebase, automatic background sync on startup and on network reconnect is **commented out**. Therefore, opening the app does **not** trigger an instant 70,000-query flood today.
  - **Remaining Structural Defect:** When a user triggers sync manually (from Profile Page) or triggers a write operation (`queueOperation` -> `triggerSync()`), `triggerSync()` does perform 7 sequential unpaginated queries:
    1. `profiles`: `select().eq('id', userId).maybeSingle()`
    2. `liked_songs`: `select().eq('user_id', userId)`
    3. `playlists`: `select().eq('user_id', userId)`
    4. `playlist_tracks`: `select().eq('user_id', userId).order('position', ascending: true)`
    5. `history`: `select().eq('user_id', userId).order('played_at', ascending: false).limit(100)`
    6. `most_played`: `select().eq('user_id', userId)`
    7. `search_history`: `select().eq('user_id', userId).order('timestamp', ascending: false).limit(20)`
* **Severity:** **HIGH** (Will become critical if auto-sync is re-enabled without delta-sync).

---

### Finding 2: Database Indexes & Query Execution Plans
* **Audit Claim:** `SyncManager` queries cause sequential full-table scans across all tables.
* **Code Location:** [`supabase/migrations/20261024000000_init_miee_schema.sql`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000000_init_miee_schema.sql)
* **Actual Observed Code:**
  - `playlists` has `create index if not exists idx_playlists_user_id on public.playlists(user_id);`
  - `liked_songs` has `create index if not exists idx_liked_songs_user_id on public.liked_songs(user_id);`
  - `history` has `create index if not exists idx_history_user_played on public.history(user_id, played_at desc);`
  - `most_played` has `constraint uq_most_played unique(user_id, track_id);` (Leading column `user_id` forms a B-tree index).
* **Evaluation:** **PARTIALLY INCORRECT.**
  - PostgreSQL uses an **Index Scan** or **Bitmap Index Scan** on `user_id` for `liked_songs`, `playlists`, `history`, and `most_played`. It does **not** scan the entire table across all users.
  - **However, two critical missing indexes were confirmed:**
    1. **`playlist_tracks` missing index on `user_id`:** The only index is `idx_playlist_tracks_playlist_pos on (playlist_id, position)`. When `SyncManager` executes `from('playlist_tracks').select().eq('user_id', userId)`, PostgreSQL must scan the table or rely on row-level security sub-plans.
    2. **`room_messages` missing index on `(room_id, created_at)`:** When `getRoomMessages(roomId)` executes `from('room_messages').select().eq('room_id', roomId).order('created_at', ascending: true)`, there is no index covering `(room_id, created_at)`.
* **Severity:** **HIGH** (Causes slow queries as table sizes surpass 100,000 rows).

---

### Finding 3: Supabase Realtime Quotas & Connection Lifecycle
* **Audit Claim:** Default Supabase Realtime concurrent connection quota is 200 (Free) or 500 (Pro). Listening Rooms will fail when concurrent participants exceed these numbers.
* **Code Location:** 
  - [`lib/features/rooms/data/room_repository.dart` (lines 324–442)](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/rooms/data/room_repository.dart#L324-L442)
  - [`lib/features/rooms/providers/room_providers.dart` (lines 679–685)](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/rooms/providers/room_providers.dart#L679-L685)
* **Actual Observed Code:**
  - In `RoomRepository.subscribeToRoom()`, each room listener establishes a Supabase Realtime channel (`room:roomId`) listening to Postgres changes on `room_state`, `room_members`, `room_messages`, and `rooms`.
  - In `ActiveRoomPage`, tapping back arrow minimizes the page via `context.pop()`, keeping the WebSocket subscription alive until the user explicitly taps "Leave Room" or the host ends the room.
* **Evaluation:** **VERIFIED CORRECT.**
  - Realtime connections remain persistent.
  - Supabase Free tier enforces a strict hard ceiling of **200 concurrent connections**.
  - Supabase Pro tier includes **500 concurrent connections**.
  - Supporting 1,000 to 10,000 concurrent room listeners requires explicit Realtime compute provisioning and paid connection quota expansion ($10 per 1,000 connections/month).
* **Severity:** **CRITICAL** (Hard infrastructure ceiling).

---

### Finding 4: YouTube Search & Playback Architecture
* **Audit Claim:** Playback does not consume Miee server bandwidth; native devices stream directly from Google Video CDN.
* **Code Location:** 
  - [`lib/core/audio/youtube_audio_service.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/audio/youtube_audio_service.dart)
  - [`lib/features/youtube/data/youtube_repository.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/youtube/data/youtube_repository.dart)
* **Actual Observed Code:**
  - `YouTubeAudioService` resolves media URLs using `youtube_explode_dart` directly from the mobile client to YouTubei player endpoints.
  - The resolved URL points to Google's CDN (`https://rr---sn-....googlevideo.com/videoplayback?...`).
  - `just_audio` (ExoPlayer) streams the media chunks directly over HTTPS from Google.
* **Evaluation:** **VERIFIED CORRECT.**
  - Miee carries **zero media egress costs**.
  - At 10,000 CCU, audio streaming bandwidth is completely offloaded to Google infrastructure.
* **Severity:** **INFORMATIONAL (Major architectural strength).**

---

### Finding 5: Image & Artwork Caching
* **Audit Claim:** The app relies on in-memory caching and lacks persistent disk caching for artwork.
* **Code Location:** 
  - `lib/features/home/presentation/home_page.dart`
  - `lib/features/library/presentation/artist_detail_page.dart`
  - `lib/features/player/presentation/player_page.dart`
* **Actual Observed Code:**
  - All widgets instantiate `Image.network(...)` directly.
  - `pubspec.yaml` contains `flutter_cache_manager`, but neither `cached_network_image` nor custom disk-backed image providers are used in the presentation layer.
* **Evaluation:** **VERIFIED CORRECT.**
  - When the OS reclaims RAM or the user restarts the app, album artwork is re-downloaded over the network.
* **Severity:** **MEDIUM** (Wastes mobile bandwidth and causes image popping, though does not impact Supabase database load).

