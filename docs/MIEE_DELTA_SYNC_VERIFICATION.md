# Miee — Incremental Synchronization (Delta-Sync) Verification

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Scope:** Verification of change detection, cursor/timestamp columns, insert/update semantics, delete propagation, and catalog download behavior across all Miee datasets.

---

## 1. Dataset-by-Dataset Audit Matrix

```
+-------------------------------------------------------------------------------------------------------------------------+
|                                    Incremental Delta-Sync Audit Matrix                                                  |
+-------------------+-----------------------+--------------------+---------------------+------------------+---------------+
| Dataset           | Strategy              | Timestamp / Cursor | Delete Propagation  | Pagination / Cap | Classification|
+-------------------+-----------------------+--------------------+---------------------+------------------+---------------+
| `liked_songs`     | Incremental Delta     | `liked_at`         | Full sync reconcile | Unpaginated delta| **Verified**  |
| `playlists`       | Full Download + Merge | `last_modified`    | Full sync reconcile | Unpaginated      | **Partially** |
| `playlist_tracks` | Full Download + Merge | `added_at` (no upd)| Full sync reconcile | Unpaginated      | **Partially** |
| `most_played`     | Full Download + Merge | `updated_at`       | Full sync reconcile | Unpaginated      | **Partially** |
| `history`         | Bounded Window        | `played_at` (sort) | Local FIFO truncate | Top 100 limit    | **Verified**  |
| `search_history`  | Bounded Window        | `timestamp` (sort) | Local FIFO truncate | Top 20 limit     | **Verified**  |
| `profiles`        | Single-Row LWW Merge  | `updated_at`       | N/A (single record) | Single-row (1:1) | **Verified**  |
+-------------------+-----------------------+--------------------+---------------------+------------------+---------------+
```

---

## 2. In-Depth Technical Verification by Dataset

### A. `liked_songs` (Favorites)
- **Classification:** **Verified**
- **Change Detection Mechanism:** Filter by `liked_at > lastSync` when `lastSync != null` and `force == false`.
- **Timestamp Column:** `liked_at timestamptz default now()`.
- **Insert/Update Handling:** Newly fetched remote tracks are written to Hive via `favsBox.put(track.id, ...)` without invoking `favsBox.clear()`. Existing local songs remain undisturbed.
- **Delete Propagation:** Because `liked_songs` does not store soft-delete tombstones (`deleted_at`), an un-favorited track deleted on Device A cannot be detected via `gt('liked_at', lastSync)` on Device B. Reconciling remote deletions requires a full synchronization (`force: true`), which runs on manual "Sync Now" or initial sign-in.
- **Offline Mutation Handling:** Offline additions (`favorite_add`) and removals (`favorite_remove`) are stored in `_operationQueue` and replayed to Supabase on reconnection.

### B. `playlists`
- **Classification:** **Partially Verified (Full Catalog Download with Local Timestamp Merge)**
- **Change Detection Mechanism:** None on query. Every sync currently executes `client.from('playlists').select().eq('user_id', userId)`.
- **Timestamp Column:** `last_modified timestamptz default now()`.
- **Insert/Update Handling:** In-memory merge via `ConflictResolver.resolveLatest(local, remote)` based on `last_modified`.
- **Delete Propagation:** Box wiped via `playlistsBox.clear()` and refilled with resolved merged playlists.
- **Why Full Download Remains:** The number of playlists per user is strictly bounded by human behavior (typically 2–10 playlists, $< 5\text{ KB}$ payload). While `last_modified` exists, introducing partial playlist delta downloads without soft-delete tombstones causes deleted playlists to resurface from local cache.

### C. `playlist_tracks`
- **Classification:** **Partially Verified (Full Catalog Download)**
- **Change Detection Mechanism:** None on query. Queries all tracks owned by the user ordered by position: `client.from('playlist_tracks').select().eq('user_id', userId).order('position', ascending: true)`.
- **Timestamp Column:** `added_at timestamptz default now()`.
- **Architectural Constraint:** Tracks within playlists can be reordered (`position` integer changes). However, `public.playlist_tracks` has **no `updated_at` column**, only `added_at`. Filtering by `added_at > lastSync` would miss track position updates and song re-orderings! Full playlist track retrieval per user is therefore required until an `updated_at` trigger is added to the database.

### D. `most_played`
- **Classification:** **Partially Verified (Full Catalog Download)**
- **Change Detection Mechanism:** Full download of all rows for `user_id`.
- **Timestamp Column:** `updated_at timestamptz default now()`.
- **Merge Behavior:** Max-count merge between local integer count and remote integer count.

### E. `history` (Recently Played)
- **Classification:** **Verified (Bounded Query)**
- **Query Strategy:** Windowed query: `.eq('user_id', userId).order('played_at', ascending: false).limit(100)`.
- **Egress Boundary:** Hard-capped at 100 rows. Prevents unbounded payload expansion even after years of active listening.

### F. `search_history`
- **Classification:** **Verified (Bounded Query)**
- **Query Strategy:** Windowed query: `.eq('user_id', userId).order('timestamp', ascending: false).limit(20)`.
- **Egress Boundary:** Hard-capped at 20 rows.

### G. `profiles`
- **Classification:** **Verified (Single Row Lookup)**
- **Query Strategy:** `.eq('id', userId).maybeSingle()`.
- **Conflict Resolution:** Last-Write-Wins (LWW) comparing `remoteUpdated` vs `localProfile.lastOpened`.

---

## 3. Findings & Recommendations

1. **`liked_songs` Delta-Sync:** Successfully cuts egress and eliminates Hive thrashing for the largest unbounded user catalog.
2. **`playlist_tracks` Schema Limitation:** `playlist_tracks` lacks an `updated_at` column. As user playlists grow, a future P2 migration should add `updated_at timestamptz default now()` and an automatic `BEFORE UPDATE` trigger so playlist tracks can also be delta-synced safely without missing reordering events.

