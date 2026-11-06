# Miee — Scalability Baseline Investigation & Architecture Discovery

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Status:** Verified against repository source and SQL migrations  
**Lead Engineer:** Senior Backend & Mobile Systems Engineer  

---

## Executive Summary

This baseline investigation audits the actual Miee database schema, Supabase client configuration, synchronization routines (`SyncManager`), and query lifecycles against ground-truth source code. It answers the 10 mandatory architectural questions required prior to implementing remediations **REM-01** through **REM-04**.

---

## 1. Verified Architecture & Schema Answers

### Q1: Which operations currently trigger synchronization?
Synchronization is initiated through two channels:
1. **User-Initiated:**
   - [`lib/features/profile/presentation/profile_page.dart#L202`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/profile/presentation/profile_page.dart#L202): The manual **"Sync Now"** button in `ProfilePage`.
2. **Automated Mutation Queue:**
   - [`lib/core/sync/sync_manager.dart#L56`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L56): Every call to `SyncManager.queueOperation(op)` immediately invokes `triggerSync()`.
   - Every local repository mutation queues an operation and triggers sync:
     - `FavoritesRepository.addFavorite()` (`favorite_add`)
     - `FavoritesRepository.removeFavorite()` (`favorite_remove`)
     - `PlaylistsRepository.createPlaylist()` (`playlist_create`)
     - `PlaylistsRepository.deletePlaylist()` (`playlist_delete`)
     - `PlaylistsRepository.renamePlaylist()` (`playlist_rename`)
     - `PlaylistsRepository.addTrackToPlaylist()` (`playlist_song_add`)
     - `PlaylistsRepository.removeTrackFromPlaylist()` (`playlist_song_remove`)
     - `PlaylistsRepository.reorderTracks()`
     - `RecentlyPlayedRepository.addEntry()` (`history_add`)
     - `MostPlayedRepository.incrementPlayCount()` (`most_played_increment`)
     - `SearchHistoryRepository.addSearchQuery()` (`search_add`)
     - `SearchHistoryRepository.removeSearchQuery()` (`search_remove`)
   *(Note: Automatic sync on network reconnect via `NetworkMonitor` in `sync_manager.dart#L40-L42` is currently commented out).*

### Q2: Which queries fetch entire catalogs?
The following remote queries in [`SyncManager.triggerSync()`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L339-L498) and `downloadAllRemoteData()` download unpaginated catalogs without range or timestamp filters:
1. `liked_songs`: `client.from('liked_songs').select().eq('user_id', userId)` (Full favorites catalog).
2. `playlists`: `client.from('playlists').select().eq('user_id', userId)` (All user playlists).
3. `playlist_tracks`: `client.from('playlist_tracks').select().eq('user_id', userId).order('position', ascending: true)` (All tracks across all playlists for the user).
4. `most_played`: `client.from('most_played').select().eq('user_id', userId)` (All most-played track play counts).

### Q3: Which queries are paginated or bounded?
The following queries apply row bounds:
1. `history`: `client.from('history').select().eq('user_id', userId).order('played_at', ascending: false).limit(100)` (Bounded to 100).
2. `search_history`: `client.from('search_history').select().eq('user_id', userId).order('timestamp', ascending: false).limit(20)` (Bounded to 20).
3. `room_messages`: `client.from('room_messages').select().eq('room_id', roomId).order('created_at', ascending: true).limit(100)` in [`room_repository.dart#L225`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/rooms/data/room_repository.dart#L225) (Bounded to 100).
4. `profiles`: `client.from('profiles').select().eq('id', userId).maybeSingle()` (Single row lookup).

### Q4: Are duplicate sync requests possible?
**YES.** There is currently:
- **No in-flight mutex or future reuse:** If multiple calls to `triggerSync()` occur simultaneously, each executes concurrently.
- **No debouncing or minimum interval:** If a user rapidly favorites 5 songs or adds multiple tracks to a playlist, 5 separate `triggerSync()` invocations execute concurrently.
- **Impact:** Each concurrent execution runs `replayOfflineQueue()`, triggers 7 parallel Supabase REST queries, and subsequently calls `favsBox.clear()`, `playlistsBox.clear()`, etc. This creates severe Hive cache thrashing, high database query volume, and redundant network egress.

### Q5: Which database indexes already exist?
Verified by inspecting `supabase/migrations/`:
- **Explicit Secondary Indexes:**
  - `idx_playlists_user_id` on `public.playlists(user_id)` ([`20261024000000_init_miee_schema.sql#L98`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000000_init_miee_schema.sql#L98))
  - `idx_playlist_tracks_playlist_pos` on `public.playlist_tracks(playlist_id, position)` ([`20261024000000_init_miee_schema.sql#L137`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000000_init_miee_schema.sql#L137))
  - `idx_liked_songs_user_id` on `public.liked_songs(user_id)` ([`20261024000000_init_miee_schema.sql#L169`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000000_init_miee_schema.sql#L169))
  - `idx_history_user_played` on `public.history(user_id, played_at desc)` ([`20261024000001_sync_auxiliary_tables.sql#L31`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000001_sync_auxiliary_tables.sql#L31))
- **Constraint-Generated B-Tree Indexes:**
  - `profiles(id)` (PK), `profiles(username)` (UNIQUE)
  - `playlists(id)` (PK)
  - `playlist_tracks(id)` (PK), `playlist_tracks(playlist_id, track_id)` (UNIQUE)
  - `liked_songs(id)` (PK), `liked_songs(user_id, track_id)` (UNIQUE)
  - `rooms(id)` (PK), `rooms(join_code)` (UNIQUE)
  - `room_members(id)` (PK), `room_members(room_id, user_id)` (UNIQUE)
  - `history(id)` (PK)
  - `most_played(id)` (PK), `most_played(user_id, track_id)` (UNIQUE)
  - `search_history(id)` (PK), `search_history(user_id, query)` (UNIQUE)
  - `room_messages(id)` (PK)

### Q6: Does `playlist_tracks` actually contain `user_id`?
**YES.** Verified in [`supabase/migrations/20261024000000_init_miee_schema.sql#L105`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000000_init_miee_schema.sql#L105):
```sql
create table if not exists public.playlist_tracks (
  id text primary key default gen_random_uuid()::text,
  playlist_id text not null references public.playlists(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  track_id text not null,
  ...
);
```
**Critical Finding:** Although `playlist_tracks` contains `user_id` and is queried by `user_id` in `SyncManager` line 373 (`eq('user_id', userId)`), **NO index exists on `playlist_tracks(user_id)`**. It only indexes `(playlist_id, position)`. Therefore, all playlist track sync queries require a full sequential scan of `public.playlist_tracks`.

### Q7: Which connection path does the Flutter application currently use?
Verified in [`lib/core/sync/supabase_config.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/supabase_config.dart):
- **REST Queries & RPC:** `HTTPS` to `https://qjvjmruovmftcbwrfjsq.supabase.co/rest/v1` via PostgREST.
- **Authentication:** `HTTPS` to `https://qjvjmruovmftcbwrfjsq.supabase.co/auth/v1` via GoTrue.
- **Realtime (Listening Rooms):** `WSS` to `wss://qjvjmruovmftcbwrfjsq.supabase.co/realtime/v1` via Supabase Realtime (Phoenix WebSocket).
The Flutter client **never** makes direct TCP connections to PostgreSQL port 5432 or 6543.

### Q8: Does the current configuration already use Supabase-managed connection pooling?
- **Server Side (PostgREST):** Supabase's hosted PostgREST layer connects to PostgreSQL using server-side connection pooling.
- **Client Side (Flutter):** Because Flutter uses HTTPS REST, connection pooling occurs natively at the PostgREST server layer.
- **Direct Database Connections:** Any direct PostgreSQL connections (e.g., CI/CD migrations, analytics tools, server-side cron jobs) must use Supavisor on port `6543` (transaction mode). Changing the Flutter client's base URL to port `6543` would break HTTPS PostgREST.

### Q9: Which operations depend on PostgreSQL direct connections?
Within the Flutter codebase, **none**. All client operations use PostgREST RPC, REST, and Realtime WebSockets. Direct PostgreSQL connections are strictly used for developer CLI commands (`supabase db push`), database migrations, and administrative maintenance.

### Q10: How are offline changes and deletions synchronized?
- **Local Queuing:** Offline mutations are recorded in Hive box `HiveBoxes.offlineQueue` as `OfflineOperation` objects.
- **Replay:** When online, `replayOfflineQueue()` replays each operation sequentially.
- **Deletions:**
  - Favorites: `.from('liked_songs').delete().eq('track_id', ...).eq('user_id', userId)`
  - Playlists: `.from('playlists').delete().eq('id', ...).eq('user_id', userId)`
  - Playlist Tracks: `.from('playlist_tracks').delete().eq('playlist_id', ...).eq('track_id', ...).eq('user_id', userId)`
  - Search History: `.from('search_history').delete().eq('query', ...).eq('user_id', userId)`
- **Remote Synchronization Conflict:** The remote database does not use soft deletion (no `deleted_at` tombstones). When `triggerSync()` runs, local Hive and remote tables are merged with `ConflictResolver.mergeLists`. If an item was deleted on device A, device B's local Hive cache would re-upload or re-insert it unless tombstones or authoritative sync boundaries exist.

---

## 2. Action Items for REM-01 to REM-04

1. **REM-01 (Indexes):**
   - Add `idx_playlist_tracks_user_id` on `public.playlist_tracks(user_id)`.
   - Add `idx_room_messages_room_created` on `public.room_messages(room_id, created_at asc)`.
   - Add `idx_liked_songs_user_liked_at` on `public.liked_songs(user_id, liked_at desc)`.
2. **REM-02 (Connection Pooling):**
   - Document connection topology and audit Supavisor pooler usage in `docs/MIEE_CONNECTION_POOLING_AUDIT.md`.
3. **REM-03 & REM-04 (SyncManager Optimization):**
   - Implement an in-flight `Future<void>?` mutex in `SyncManager` to eliminate duplicate concurrent sync runs.
   - Introduce request debouncing / minimum cooldown interval (e.g. 15-30s) for non-forced background sync triggers.
   - Implement delta-sync tracking `last_synced_at` in Hive to avoid full table downloads.

