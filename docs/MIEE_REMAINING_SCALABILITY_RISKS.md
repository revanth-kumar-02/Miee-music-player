# Miee — Remaining Scalability Risks & Remediation Roadmap

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Scope:** Transparent classification of remaining architectural constraints, failure boundaries, and required mitigations prior to 10,000 CCU.

---

## 1. Executive Risk Summary

While database indexes (**REM-01**), connection pooling topology (**REM-02**), and mutation queue debouncing (**REM-03 / REM-04**) successfully stabilized Miee up to 1,000 CCU, scaling past 1,000 to 10,000 CCU exposes three distinct infrastructural and schema boundaries.

```
+---------------------------------------------------------------------------------------------------------+
|                                    Remaining Scalability Risks                                          |
+------+-------------------------------+--------------------+---------------------+-----------------------+
| Risk | Area                          | Concurrency Ceiling| Severity            | Remediation Path      |
+------+-------------------------------+--------------------+---------------------+-----------------------+
| R-01 | Realtime WebSocket Hard Cap   | 500 CCU            | **High (P0)**       | Supabase Add-on ($10) |
| R-02 | `playlist_tracks` Schema Void | ~2,000 CCU         | **Medium (P1)**     | `updated_at` Migration|
| R-03 | Artwork Image Network Egress  | ~3,000 CCU         | **Medium (P2)**     | CachedNetworkImage    |
| R-04 | Dedicated DB Compute Limit    | ~5,000 CCU         | **Low (P3)**        | Compute Upgrade (XL)  |
+------+-------------------------------+--------------------+---------------------+-----------------------+
```

---

## 2. Technical Risk Deep Dive

### Risk R-01: Supabase Realtime WebSocket Quota Saturation
- **Problem:** Supabase Pro plans include 500 concurrent Realtime connections. Free plans cap at 200. At 1,000 CCU with 10% in collaborative Listening Rooms, or at 10,000 CCU with 1,000 room participants, new WebSocket connections will receive `HTTP 429` / connection drop.
- **Remediation:** In Supabase Dashboard &rarr; Project Settings &rarr; Billing &rarr; Add-ons, provision the **Realtime Concurrent Connections Add-on** ($10 per 1,000 connections/month) to support 2,500+ simultaneous room participants.

### Risk R-02: `playlist_tracks` Missing `updated_at` Column
- **Problem:** As discovered in Phase 2, `public.playlist_tracks` lacks an `updated_at` column. Track reordering changes `position`, but does not create an `added_at` delta. Thus, full track lists for playlists must currently be downloaded.
- **Remediation Plan:**
  1. Add `updated_at timestamptz default now()` to `public.playlist_tracks`.
  2. Attach an automatic `BEFORE UPDATE` trigger in PostgreSQL:
     ```sql
     create or replace function update_playlist_track_timestamp()
     returns trigger as $$
     begin
       new.updated_at = now();
       return new;
     end;
     $$ language plpgsql;
     ```
  3. When client syncs, only query tracks for playlists whose `last_modified` changed since local snapshot.

### Risk R-03: Repeated Remote Artwork Downloads
- **Problem:** `Image.network` in Flutter caches images only in RAM during an active process session. App restarts or memory pressure trigger full re-downloads of YouTube and local album artwork thumbnails.
- **Remediation:** Introduce a persistent disk-backed caching layer (e.g., `cached_network_image` with a 250MB bounded cache size and 7-day TTL).

### Risk R-04: Database Compute Saturation at 10K CCU
- **Problem:** Standard 2-core / 4GB RAM Supabase instances can handle up to ~3,000–4,000 peak QPS under indexed workloads. At 10,000 CCU, burst QPS during viral song drops or simultaneous active hours can exceed 5,000 QPS, driving database CPU above 80%.
- **Remediation:** Scale instance compute to XL (4-core / 16GB RAM) or 2XL (8-core / 32GB RAM) when monitored database CPU consistently exceeds 70%.

