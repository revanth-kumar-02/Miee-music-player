# Miee — Scalability & 10K CCU Engineering Roadmap

**Document Version:** 1.0.0  
**Target Milestone:** 10,000 Concurrent Active Users  
**Architecture Principles:** High Agency, Zero AI-Slop, Data-Driven Scaling  

---

## Roadmap Overview

```
Phase A: Stability          Phase B: Optimization       Phase C: Infrastructure    Phase D: Load Testing      Phase E: Production Ops
(Weeks 1-2)                (Weeks 3-4)                 (Weeks 5-6)                (Weeks 7-8)                (Weeks 9-10)
+-----------------------+   +-----------------------+   +----------------------+   +----------------------+   +-----------------------+
| - Supavisor Pooler    |   | - Delta-Sync Protocol |   | - Supabase Pro Tier  |   | - Stage 1 (100 CCU)  |   | - Sentry & APM Tracing|
| - Sync Rate-Limiting  |-->| - Disk Image Cache    |-->| - Compute Add-on (2XL|-->| - Stage 3 (1k CCU)   |-->| - Automated Backups   |
| - Missing DB Indexes  |   | - Room Broadcast Throt|   | - Realtime 10k Addon |   | - Stage 5 (10k CCU)  |   | - Incident Runbooks   |
+-----------------------+   +-----------------------+   +----------------------+   +----------------------+   +-----------------------+
```

---

## Phase A — Immediate Stability (Weeks 1–2)

### Task A.1: Enable Supavisor Transaction Connection Pooling
* **Why Necessary:** Direct PostgreSQL connections fail when simultaneous client connections exceed 60–120. PostgREST handles HTTP well, but background queries and stored procedures quickly exhaust PostgreSQL server processes.
* **Expected Benefit:** Increases maximum concurrent client database sessions from ~100 to 10,000+ pooled connections.
* **Implementation Complexity:** Low (Supabase configuration change; route traffic via port 6543 / pooler URL).
* **Infrastructure Cost Impact:** $0 (Included with Supabase).
* **Dependencies:** None.
* **Regression Risks:** Prepared statements must be disabled in transaction pooling mode (handled transparently by PostgREST).

### Task A.2: Guard Against Duplicate Sync Storms (`SyncManager`)
* **Why Necessary:** Multiple UI controllers currently call `triggerSync()` concurrently on app foregrounding, causing duplicate concurrent fetches of the same 7 tables.
* **Expected Benefit:** Eliminates up to 60% of redundant database requests during cold boot and app resume.
* **Implementation Complexity:** Low (Add an in-flight `_isSyncing` mutex and minimum 60-second debounce period in `SyncManager`).
* **Infrastructure Cost Impact:** $0.
* **Dependencies:** None.
* **Regression Risks:** None; local data in Hive is already served instantly.

### Task A.3: Audit and Add Missing Compound Database Indexes
* **Why Necessary:** As tables (`liked_songs`, `playlist_tracks`, `room_messages`, `history`) grow to hundreds of thousands of rows, queries filtering on `(user_id, updated_at)` or `(room_id, created_at)` will degrade from index scans to sequential disk scans.
* **Expected Benefit:** Reduces P95 query execution time from $> 250\text{ ms}$ to $< 5\text{ ms}$.
* **Implementation Complexity:** Low (Standard SQL migration).
* **SQL Migration Target:**
  ```sql
  create index if not exists idx_liked_songs_user_track on public.liked_songs(user_id, track_id);
  create index if not exists idx_room_messages_room_time on public.room_messages(room_id, created_at asc);
  create index if not exists idx_room_state_room_rev on public.room_state(room_id, revision);
  ```
* **Infrastructure Cost Impact:** Negligible disk storage increase (~15MB).
* **Dependencies:** None.

---

## Phase B — Query & Resource Optimization (Weeks 3–4)

### Task B.1: Implement Incremental Delta-Sync Protocol
* **Why Necessary:** Currently, `SyncManager.triggerSync()` downloads the *entire* library, all playlists, and all liked songs on every sync trigger. At scale, this moves gigabytes of redundant data over the network and thrashes PostgreSQL CPU.
* **Expected Benefit:** Replaces full-table scans with lightweight incremental queries (`where updated_at > :lastSyncTimestamp`), reducing payload size by $> 95\%$.
* **Implementation Complexity:** Medium (Add `last_synced_at` timestamp in Hive preferences and pass to Supabase queries).
* **Infrastructure Cost Impact:** Huge reduction in egress bandwidth costs ($> \$200/\text{mo}$ savings at 10K CCU).
* **Dependencies:** Task A.3 (Indexes on `updated_at`).
* **Regression Risks:** Deleted items must use soft-deletes (`deleted_at` column) to propagate deletions down to offline devices.

### Task B.2: Persistent Disk Image Caching for Artwork
* **Why Necessary:** Standard Flutter `Image.network` purges artwork from memory on low RAM or process restart, forcing full re-downloads from external CDNs.
* **Expected Benefit:** Eliminates repeat image downloads, cuts mobile data consumption by ~80%, and eliminates image popping/flashing.
* **Implementation Complexity:** Low-Medium (Adopt `cached_network_image` with local cache key based on track/artist ID).
* **Infrastructure Cost Impact:** $0.
* **Dependencies:** None.
* **Regression Risks:** Cache eviction policy must be bounded (e.g. 250MB disk limit) to avoid consuming user device storage.

### Task B.3: Listening Room Realtime Broadcast Throttling
* **Why Necessary:** During active room playback, seeks or queue adjustments trigger real-time updates. If the host seeks repeatedly or messages are rapid, message cascades occur across all connected listeners.
* **Expected Benefit:** Caps host broadcast frequency to a maximum of 1 packet per 400ms, stabilizing WebSocket message throughput.
* **Implementation Complexity:** Low (Enforce debouncing inside `_broadcastHostState`).
* **Infrastructure Cost Impact:** Reduces Realtime message volume by ~50%.
* **Dependencies:** None.

---

## Phase C — Infrastructure Upgrades (Weeks 5–6)

### Task C.1: Upgrade to Supabase Pro + Compute Add-on (2XL / 4XL)
* **Why Necessary:** 10,000 active concurrent connections and thousands of queries per second require dedicated PostgreSQL RAM for buffer pools and connection memory.
* **Expected Benefit:** Guarantees 8–16 CPU cores, 32–64GB RAM, and 10,000 IOPS on PostgreSQL instance.
* **Implementation Complexity:** Low (1-click compute upgrade in Supabase Dashboard; zero code changes).
* **Infrastructure Cost Impact:** ~$200 to $400/month.
* **Dependencies:** Phase B optimizations verified.

### Task C.2: Provision Supabase Realtime 10,000 Concurrent Connections Add-on
* **Why Necessary:** Supabase Pro includes 500 concurrent WebSocket connections. Supporting thousands of simultaneous room participants requires upgrading the Realtime quota.
* **Expected Benefit:** Unlocks up to 10,000 simultaneous persistent WebSocket listeners without dropped connections.
* **Infrastructure Cost Impact:** ~$95/month ($10 per 1,000 connections over 500).
* **Dependencies:** None.

---

## Phase D — Staged Load Testing & Verification (Weeks 7–8)

### Execution Protocol:
1. **Week 7:** Run Baseline (10 CCU) and Stage 1 (100 CCU) against isolated staging environment. Record P50/P95 latencies.
2. **Mid-Week 7:** Run Stage 2 (500 CCU) and Stage 3 (1,000 CCU). Validate Supavisor connection pooling and delta-sync efficiency.
3. **Week 8:** Run Stage 4 (5,000 CCU) and Stage 5 (10,000 CCU) stress tests. Verify database CPU stays $< 75\%$ and zero dropped WebSocket connections.

---

## Phase E — Production Readiness & Observability (Weeks 9–10)

### Task E.1: Full-Stack APM & Crash Reporting (Sentry / Datadog)
* Real-time monitoring of app crash-free session rate ($> 99.9\%$).
* Tracing of network latency and resolution timeouts in `YouTubeAudioService`.

### Task E.2: Supabase Automated Daily Backups & Point-in-Time Recovery (PITR)
* Enable 7-day or 14-day PITR in Supabase.
* Run a quarterly disaster recovery restore drill.

### Task E.3: Automated Alerts
* Alert on Postgres CPU $> 80\%$ for $> 5\text{ minutes}$.
* Alert on Realtime connection count reaching $85\%$ of quota limit.
* Alert on PostgREST 5xx error rate $> 0.5\%$.

