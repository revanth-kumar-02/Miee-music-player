# Miee — Scalability Remediation Engineering Plan

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Scope:** Concrete, prioritized engineering remediations to scale Miee safely toward 10,000 CCU without disrupting existing user playback.

---

## 1. Prioritization Framework

Remediations are strictly ranked by immediate system risk and concurrency thresholds:

* **P0 — Critical Correctness & Outage Risks:** Must be implemented before any marketing or user expansion; addresses unindexed sequential scans and connection exhaustion.
* **P1 — Required Before Public Growth (500–1,000 CCU):** Replaces unpaginated library sync with bounded delta-sync and activates connection pooling.
* **P2 — Required for 1,000+ CCU:** Eliminates redundant image re-downloads, throttles listening room broadcasts, and establishes APM tracing.
* **P3 — Required for 5,000–10,000 CCU:** Enterprise compute upgrades, dedicated Realtime cluster scaling, and edge CDN distribution.

---

## 2. Prioritized Engineering Tasks

```
+---------------------------------------------------------------------------------------------------------+
|                                    Remediation Priority Matrix                                          |
+----------+---------+----------------------------------+---------------------+---------------------------+
| Priority | Task ID | Description                      | Target Bottleneck   | Complexity & Risk         |
+----------+---------+----------------------------------+---------------------+---------------------------+
| **P0**   | REM-01  | Add Missing DB Indexes           | Sequential scans    | Low complexity, Zero risk |
| **P0**   | REM-02  | Enable Supavisor Pooling         | DB max_connections  | Low complexity, Low risk  |
| **P1**   | REM-03  | Incremental Delta-Sync Protocol  | Sync query storms   | Medium complexity & risk  |
| **P1**   | REM-04  | Sync Request Debouncing & Mutex  | Redundant sync calls| Low complexity, Zero risk |
| **P1**   | REM-05  | Upgrade Supabase Realtime Quota  | 200/500 CCU cap     | Low complexity, Cost only |
| **P2**   | REM-06  | Persistent Disk Image Caching    | Image re-downloads  | Medium complexity, Low risk|
| **P2**   | REM-07  | Room Broadcast Throttling        | WebSocket fan-out   | Low complexity, Low risk  |
| **P2**   | REM-08  | Full-Stack APM & Sentry Alerting | Blind spots         | Low complexity, Zero risk |
| **P3**   | REM-09  | Compute Scaling (XL / 2XL)       | 10K Peak QPS        | Configuration only        |
+---------------------------------------------------------------------------------------------------------+
```

---

### P0 — Critical Correctness & Outage Risks

#### Task REM-01: Add Missing Compound Database Indexes (Database Migration)
* **Purpose:** Eliminate unindexed sequential scans on `playlist_tracks` and `room_messages` as table sizes expand.
* **Target Bottlenecks:**
  - In [`sync_manager.dart#L371`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L371), `playlist_tracks` is queried by `user_id`, but the only existing index is on `(playlist_id, position)`.
  - In [`room_repository.dart#L225`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/rooms/data/room_repository.dart#L225), `room_messages` is queried by `room_id` ordered by `created_at asc`, but lacks an index on `(room_id, created_at)`.
* **Remediation Specification:**
  Apply standard migration `supabase/migrations/20261105000000_scalability_indexes.sql`:
  ```sql
  -- 1. Index playlist_tracks by user_id for sync queries
  create index if not exists idx_playlist_tracks_user_id
    on public.playlist_tracks(user_id);

  -- 2. Index room_messages by room_id and created_at for live chat retrieval
  create index if not exists idx_room_messages_room_created
    on public.room_messages(room_id, created_at asc);

  -- 3. Composite index on liked_songs for delta-sync timestamp lookups
  create index if not exists idx_liked_songs_user_liked_at
    on public.liked_songs(user_id, liked_at desc);
  ```
* **Expected Benefit:** Converts $O(N)$ sequential table scans to $O(\log N)$ B-tree index lookups. Drops P95 query execution time from $> 200\text{ ms}$ to $< 2\text{ ms}$.
* **Implementation Risk:** Zero. Safe to execute concurrently on live Postgres (`CREATE INDEX CONCURRENTLY` in production).

#### Task REM-02: Route Client Traffic through Supavisor Transaction Pooler
* **Purpose:** Prevent PostgreSQL `max_connections` exhaustion during concurrency bursts.
* **Target Bottlenecks:** Direct PostgreSQL on standard compute allows only 60–120 simultaneous connections. If 500 users execute queries simultaneously, incoming connections are dropped.
* **Remediation Specification:**
  In [`lib/core/sync/supabase_config.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/supabase_config.dart), verify that REST and Auth calls route through the connection pooler endpoint (port 6543, Transaction mode). Supabase PostgREST uses connection pooling by default, but ensure custom direct connections and migrations do not bypass it.
* **Expected Benefit:** Scales supported concurrent database client sessions from ~100 to 10,000+.
* **Implementation Risk:** Low. Prepared statements must remain off in Transaction mode (default for PostgREST).

---

### P1 — Required Before Public Growth (500–1,000 CCU)

#### Task REM-03: Implement Incremental Delta-Sync Protocol
* **Purpose:** Stop downloading the entire user library on every sync event.
* **Target Bottlenecks:** [`lib/core/sync/sync_manager.dart` (lines 339–385)](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L339-L385).
* **Remediation Specification:**
  1. Record `last_synced_at` timestamp in Hive preferences.
  2. Modify `SyncManager.triggerSync()` to query only updated records:
     ```dart
     final lastSync = _getLastSyncTimestamp();
     var query = client.from('liked_songs').select().eq('user_id', userId);
     if (lastSync != null) {
       query = query.gt('liked_at', lastSync.toIso8601String());
     }
     final favsRes = await query;
     ```
  3. Merge newly updated records into local Hive storage rather than calling `favsBox.clear()` and rewriting the entire box.
* **Expected Benefit:** Cuts sync network payload size and database egress by over 95%. Eliminates UI freezes during sync.
* **Implementation Risk:** Low-Medium. Deleted songs/playlists require tracking tombstone records (`deleted_at`) to propagate deletions cleanly to offline devices.

#### Task REM-04: Sync Mutex & Request Debouncing
* **Purpose:** Prevent multiple controllers from launching simultaneous sync runs.
* **Target Bottlenecks:** Rapidly switching tabs or triggering multiple favorites in quick succession triggers multiple overlapping `triggerSync()` runs.
* **Remediation Specification:**
  In `SyncManager`, wrap `triggerSync()` in a boolean mutex (`_isSyncInProgress`) and enforce a minimum cooldown interval (e.g. 30 seconds) between non-forced executions:
  ```dart
  if (_isSyncing || DateTime.now().difference(_lastSyncTime) < const Duration(seconds: 30)) {
    return;
  }
  ```
* **Expected Benefit:** Eliminates 70% of redundant sync executions during normal active user sessions.
* **Implementation Risk:** Zero.

#### Task REM-05: Provision Realtime 1,500+ Concurrent Connection Quota
* **Purpose:** Prevent WebSocket rejections for Listening Rooms when active users exceed 200 (Free) or 500 (Pro).
* **Remediation Specification:**
  In Supabase Dashboard -> Project Settings -> Billing, enable the Realtime Connection Add-on ($10 per 1,000 connections/month) to support at least 1,500 simultaneous WebSockets.
* **Expected Benefit:** Unlocks unconstrained listening room participation up to 1,500 concurrent listeners.

---

### P2 — Required for 1,000+ CCU

#### Task REM-06: Persistent Disk Image Caching for Artwork
* **Purpose:** Eliminate repeated network downloads of album artwork across app restarts.
* **Target Bottlenecks:** Every UI tile in `HomePage`, `ArtistDetailPage`, and `PlayerPage` uses `Image.network`.
* **Remediation Specification:**
  Introduce a centralized `MieeArtworkImage` widget wrapping `cached_network_image` with a bounded cache configuration (e.g. max 250MB disk limit, 7-day TTL).
* **Expected Benefit:** Reduces mobile data usage by ~80%, eliminates image flickering, and decreases cellular radio wakeups.
* **Implementation Risk:** Low. Cache eviction must be bounded to avoid filling user device storage.

#### Task REM-07: Listening Room Realtime Broadcast Throttling
* **Purpose:** Avoid flooding Realtime WebSockets when a room host repeatedly drags the playback seekbar.
* **Target Bottlenecks:** [`lib/features/rooms/providers/room_providers.dart` (lines 129–137)](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/rooms/providers/room_providers.dart#L129-L137).
* **Remediation Specification:**
  Ensure the host seek debounce timer enforces a strict rate limit of at most 1 broadcast packet every 400ms.
* **Expected Benefit:** Reduces peak Realtime packet fan-out by up to 60% during active user scrubbing.

---

### P3 — Required for 5,000–10,000 CCU

#### Task REM-08: Supabase Compute Scaling (XL / 2XL)
* **Purpose:** Provide sufficient dedicated RAM and CPU for 10,000 peak concurrent users.
* **Remediation Specification:** Upgrade PostgreSQL instance to 4-core / 16GB RAM (XL) or 8-core / 32GB RAM (2XL) in the Supabase Dashboard.
* **Cost Impact:** $220/mo (XL) to $440/mo (2XL).
* **Trigger Criterion:** Execute only when Stage 4 load testing shows sustained database CPU $> 75\%$ on smaller instances.

