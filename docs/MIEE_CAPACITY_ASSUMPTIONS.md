# Miee — Capacity & Concurrency Modeling Assumptions

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Purpose:** Establish mathematically consistent definitions, traffic models, and feature concurrency ratios for Miee at scale.

---

## 1. Concurrency Taxonomy & User State Distinctions

In production scalability planning, conflating registered accounts, active users, and concurrent network sessions leads to either massive over-provisioning or catastrophic under-provisioning. 

The following distinct metrics govern Miee's architecture:

```
+---------------------------------------------------------------------------------------------------------+
|                                    Miee Concurrency Funnel (10K Target)                                 |
+------------------------------------+------------------+-------------------------------------------------+
| User Metric                        | Ratio to CCU     | Scale @ 10,000 Target Concurrency (Peak)        |
+------------------------------------+------------------+-------------------------------------------------+
| 1. Registered User Accounts        | 50x – 100x       | 500,000 – 1,000,000 total accounts in database  |
| 2. Monthly Active Users (MAU)      | 30x – 50x        | 300,000 – 500,000 active accounts / month       |
| 3. Daily Active Users (DAU)        | 6x – 10x         | 60,000 – 100,000 active accounts / day          |
| 4. Concurrent Active Users (CCU)   | 1.0x (Baseline)  | 10,000 simultaneous open client apps            |
| 5. Concurrent Music Listeners      | 0.70x (70%)      | 7,000 users actively streaming audio            |
| 6. Concurrent Room Participants    | 0.10x (10%)      | 1,000 users in Listening Rooms (WebSockets)     |
| 7. Concurrent Database Requests    | 0.05x (5%)       | 500 – 1,000 active HTTP queries/sec             |
| 8. Concurrent Realtime WebSockets  | 0.10x – 0.15x    | 1,000 – 1,500 active persistent TCP connections  |
+------------------------------------+------------------+-------------------------------------------------+
```

### Detailed Metric Definitions:
* **Registered Users:** Total rows in Supabase `auth.users` and `public.profiles`. They impose cold disk storage requirements (~500MB to 1GB database disk) and zero runtime CPU overhead when inactive.
* **Monthly Active Users (MAU):** Users with at least one authenticated session in a rolling 30-day window. Directly dictates Supabase GoTrue Auth billing ($0.00325 per MAU above 100k tier limit).
* **Daily Active Users (DAU):** Users opening the app within 24 hours. Peak CCU is typically 10%–15% of DAU for consumer media apps.
* **Concurrent Active Users (CCU):** Devices with Miee open in the foreground or active in the background audio service at a single instant in time.
* **Concurrent Music Listeners:** CCU who are actively playing songs. **Crucially, their streaming bandwidth is handled by Google Video CDN, not Supabase.**
* **Concurrent Listening Room Participants:** CCU connected to a Supabase Realtime WebSocket channel (`room:roomId`).
* **Concurrent Database Requests:** In-flight HTTP REST requests reaching Supabase PostgREST or PostgreSQL at any single second.

---

## 2. Feature-by-Feature Traffic Modeling (10,000 CCU Peak)

Not all 10,000 concurrent users execute the same features at the same time. The traffic model reflects empirical usage patterns in mobile music streaming:

### Cohort A: Passive Listeners (70% = 7,000 CCU)
* **Activity:** Playing a queue of songs (either local device files or previously loaded YouTube streams).
* **Backend Interaction:**
  * Zero database queries during continuous playback.
  * Queue advancing and shuffling is computed 100% locally on the device.
  * Audio chunks are streamed directly from Google Video CDN (`googlevideo.com`).
  * 1 write mutation per user every 30 minutes (e.g. liking a track or recording a playback history entry).
* **Total Database Load:** $\approx 4\text{ writes/sec}$ across all 7,000 passive listeners.

### Cohort B: Active Browsers & Searchers (20% = 2,000 CCU)
* **Activity:** Searching for artists, browsing popular tracks, exploring curated categories.
* **Backend Interaction:**
  * Search queries execute client-side via `youtube_explode_dart` or Deezer API directly from device IPs.
  * 1 search query every 60 seconds per user = $\approx 33\text{ search queries/sec}$ globally.
  * Because searches are distributed across 2,000 distinct cellular/residential IPs, third-party rate limits (50 req/5 sec on Deezer) are never saturated.
  * Library updates: ~1 playlist modification or like toggle every 10 minutes.
* **Total Database Load:** $\approx 10\text{ writes/sec}$ and $\approx 15\text{ reads/sec}$.

### Cohort C: Listening Room Participants (10% = 1,000 CCU)
* **Activity:** Synchronized listening in social rooms (average 4 users per room = 250 active rooms).
* **Backend Interaction:**
  * **Persistent Connections:** Exactly **1,000 concurrent WebSocket connections** to Supabase Realtime.
  * **Host Playback Sync:** When a host changes tracks or pauses (~1 action every 3 minutes per room):
    - 250 rooms $\times$ 1 action / 180s = $\approx 1.4\text{ state writes/sec}$ to `room_state`.
    - Supabase Realtime broadcasts each update to 3 listeners = $\approx 4.2\text{ outgoing WebSocket messages/sec}$.
  * **In-Room Chat:** 1,000 users sending 1 message every 2 minutes:
    - $\approx 8.3\text{ chat inserts/sec}$ to `room_messages`.
    - Supabase Realtime broadcasts each message to 3 peers = $\approx 25\text{ broadcast packets/sec}$.
* **Total Database Load:** $\approx 10\text{ writes/sec}$ and $\approx 30\text{ WebSocket messages/sec}$.

---

## 3. Aggregate System Throughput at 10,000 CCU

```
+-------------------------------------------------------------------------------------------------+
|                                    System Throughput Summary                                    |
+------------------------------------+--------------------------+---------------------------------+
| System Layer                       | Normal Steady-State Load | Extreme Peak Spike (Burst)      |
+------------------------------------+--------------------------+---------------------------------+
| PostgREST HTTP Reads               | 25 – 50 req/sec          | 500 – 1,000 req/sec (e.g. sync) |
| PostgREST HTTP Writes              | 20 – 35 req/sec          | 150 – 300 req/sec               |
| Total Database QPS                 | 45 – 85 queries/sec      | 650 – 1,300 queries/sec         |
| Active WebSocket Connections       | 1,000 – 1,200 TCP        | 2,000 TCP (Major album release) |
| WebSocket Message Fan-Out Rate     | 25 – 40 msgs/sec         | 150 – 250 msgs/sec              |
| Media Streaming Bandwidth (Miee)   | 0 Mbps (Direct to Google)| 0 Mbps                          |
| Metadata Egress Bandwidth (Supabase)| 1.2 – 2.5 Mbps           | 15 – 30 Mbps                    |
+------------------------------------+--------------------------+---------------------------------+
```

### Key Analytical Takeaways:
1. **Steady-state database throughput is remarkably modest (under 100 QPS)** because media playback and queue logic are completely decentralized to the client.
2. **The only dangerous bottleneck is the "Sync Spike"**: If 10,000 users launch the app simultaneously and each fires an unindexed, unpaginated sync query, request volume surges from 50 QPS to over 1,000 QPS instantly.
3. **Realtime sizing is fixed and predictable:** Planning for 10% room participation at 10K CCU requires a Realtime connection quota of at least **1,500 to 2,000 concurrent WebSockets**, which is well within Supabase Pro's expandable capacity ($10/mo per 1k connections).

