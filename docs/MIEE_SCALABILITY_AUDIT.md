# Miee — 10K Concurrent Users Scalability Audit

**Document Version:** 1.0.0  
**Audit Date:** November 5, 2026  
**Auditor:** Antigravity Engineering & Architecture  
**Methodology:** REA (Reasoning, Exploration, and Analysis)  
**Target Concurrency:** 10,000 Simultaneous Active Users (CCU)  

---

## 1. Executive Summary

This audit assesses whether the Miee mobile and web application architecture can reliably support **10,000 simultaneous active users** (Concurrent Users / CCU). 

### Headline Audit Finding
- **Current Architectural Readiness:** **Limited (Tier 1–2: ~200–500 CCU max on default configuration)**.
- **Can Miee support 10,000 CCU today without infrastructure & query upgrades?** **NO**. 
- **Critical Immediate Failure Point:** The Supabase default Realtime WebSocket limits (200 CCU on Free tier, 500 on Pro base tier) and unpaginated cascading full-table scans in `SyncManager.triggerSync()` will exhaust database connections and CPU at $\approx 300\text{--}500$ simultaneous active users.
- **Key Scalability Advantage:** Playback audio streaming does **not** route through Miee's backend. Native clients resolve and stream audio directly from Google's Video CDN to the device via `just_audio`/ExoPlayer. As a result, Miee carries **zero audio bandwidth egress cost or media streaming server load**.

---

## 2. REA Architecture Discovery

### 2.1 Application Architecture (Client-Side)
- **Framework & Language:** Flutter (Dart 3.x), targeting Android, iOS, and Web.
- **State Management:** Riverpod 2.5 (`flutter_riverpod`, `StateNotifier`, `ProviderScope`).
- **Routing:** GoRouter 17.3 with declarative state-driven routing.
- **Audio Engine:** `just_audio` 0.10.6 + `audio_service` 0.18.12 + `audio_session` 0.2.4.
  - Running as an Android Foreground Service with lockscreen notification controls and `MediaSessionCompat`.
  - Native playback delegates audio streaming to native Android ExoPlayer / iOS AVPlayer.
- **Local Persistence & Caching:**
  - `Hive` 2.2.3 + `hive_flutter` 1.1.0 (local NoSQL storage for favorites, playlists, profile, search history, playback history, and offline mutation queue).
  - `shared_preferences` 2.2.0 (primitive user settings).
  - In-memory bounded cache in `YouTubeAudioService` (100 URLs, 1-hour TTL) and `YouTubeRepository` (50 queries).
- **Network Stack:** `dio` 5.4.0 + Dart `HttpClient` + `supabase_flutter` 2.6.0.

### 2.2 Backend & Cloud Architecture
- **Backend Infrastructure:** **Supabase** (Managed PostgreSQL 15, PostgREST HTTP REST API, GoTrue Auth, Realtime WebSocket engine).
  - Project Reference: `qjvjmruovmftcbwrfjsq` (Region: `ap-northeast-1` Tokyo).
  - Connection Mode: PostgREST stateless HTTP over HTTPS + WebSockets for Realtime.
  - **Firebase Status:** Firebase SDKs have been completely removed from the project; Supabase is the sole cloud backend.
- **Third-Party Services:**
  - **YouTube (via YouTubei endpoints):** Native clients query YouTube directly via `youtube_explode_dart` (using Apple VisionOS & Android clients).
  - **Deezer Public API (`api.deezer.com`):** Direct client-side HTTP calls for curated artist albums, related artists, and discography metadata.

---

## 3. Feature-by-Feature Scalability Analysis (100 to 10,000 CCU)

```
+-------------------------------------------------------------------------------------------------+
|                               Miee Traffic Concurrency Evaluation                               |
+-------------------+--------------------+-----------------------+--------------------------------+
| Concurrency Level | Estimated App Load | Database Connections  | Primary Failure Risk           |
+-------------------+--------------------+-----------------------+--------------------------------+
| 100 CCU           | Baseline           | 10–25 pooled          | None (Supported on Free/Pro)   |
| 500 CCU           | Moderate           | 50–120 pooled         | Supabase Free tier Realtime cap|
| 1,000 CCU         | Heavy              | 150–350 pooled        | Sync storms; DB connection cap |
| 5,000 CCU         | Enterprise         | 800–2,000 pooled      | PostgREST CPU & Realtime cluster|
| 10,000 CCU        | Target             | 1,500–4,000 pooled    | Total service collapse w/o pooler|
+-------------------+--------------------+-----------------------+--------------------------------+
```

### 3.1 Music Search
* **Implementation:** `SearchRepository.searchYouTube()` -> `YouTubeRepository.search()`.
* **Behavior under load:**
  - On native Android/iOS, every search executes client-side through `youtube_explode_dart`.
  - Searches are distributed across 10,000 distinct mobile IP addresses (cellular carriers / residential Wi-Fi).
  - *Risk:* If users share a congested network IP (e.g. university campus Wi-Fi or corporate proxy), YouTube may serve HTTP 429 or CAPTCHA challenges to that specific IP.
  - *Data API fallback risk:* If an administrator configures `YOUTUBE_API_KEY`, the default YouTube Data API v3 daily quota is **10,000 units**. A single search costs 100 units. A mere 100 searches across all 10,000 users will exhaust the entire daily quota within 60 seconds.

### 3.2 Music Playback & Audio Stream Resolution
* **Implementation:** `YouTubeAudioService.getAudioStreamUrl()` -> `_resolveStream()`.
* **Behavior under load:**
  - Each resolution request is executed directly from the client device to YouTube's `youtubei/v1/player` endpoint using `VISIONOS` client tokens.
  - Deduplication: `_inFlight` map deduplicates concurrent calls for the same track on the same device.
  - Audio streaming: Direct byte stream from Google Video CDN (`googlevideo.com`). Miee servers transfer **0 MB** of audio data.
  - *Scalability rating for playback streaming:* **Excellent (near infinite client-side elasticity)**, provided YouTube does not introduce global client signature changes.

### 3.3 Queue & Playback State
* **Implementation:** `QueueManager` + `PlayerController`.
* **Behavior under load:**
  - Queue operations (reordering, shuffle, next, previous) execute 100% locally in-memory and write to local Hive storage.
  - Zero network overhead during queue modification.
  - *Scalability rating:* **Flawless (O(1) local compute)**.

### 3.4 Listening Rooms (Realtime Sync & Chat)
* **Implementation:** `RoomRepository` -> Supabase Realtime Channels (`room:roomId`) over WebSockets.
* **Database Tables Involved:** `rooms`, `room_members`, `room_state`, `room_messages`.
* **Behavior at 10,000 CCU:**
  - If 20% of users (2,000 users) participate in Listening Rooms with an average of 4 members per room = 500 active rooms.
  - Each room requires a persistent WebSocket channel subscribed to Postgres CDC (`onPostgresChanges` on 4 tables) and Broadcast (`room_chat`).
  - **Hard Bottleneck:** Supabase Free Tier caps Realtime at **200 concurrent connections**. Supabase Pro Tier includes **500 concurrent connections** (bursting costs $10 per 1,000 connections up to 10,000 max).
  - **Broadcast Amplification:** Whenever a room host seeks or skips a track, an update is written to `room_state` (with Postgres CDC broadcast to all members). A chat message writes to `room_messages` and broadcasts over WebSocket.
  - At 2,000 room users sending 1 message every 30 seconds = ~67 writes/sec and ~270 broadcast packets/sec. Supabase Realtime cluster requires dedicated sizing.

### 3.5 User Accounts, Library & Cloud Sync (`SyncManager`)
* **Implementation:** `lib/core/sync/sync_manager.dart` (`triggerSync()`).
* **Critical Finding:**
  When `triggerSync()` executes (on login, network reconnect, or manual trigger):
  1. `profiles`: `select().eq('id', userId)`
  2. `liked_songs`: `select().eq('user_id', userId)` (**unpaginated, full table scan for user**)
  3. `playlists`: `select().eq('user_id', userId)` (**unpaginated**)
  4. `playlist_tracks`: `select().eq('user_id', userId).order('position')` (**fetches entire user library in one shot**)
  5. `history`: `select().eq('user_id', userId)...`
  6. `most_played`: `select().eq('user_id', userId)...`
  7. `search_history`: `select().eq('user_id', userId)...`
* **Sync Storm Disaster Scenario:**
  If 10,000 users open the app simultaneously (e.g. push notification or evening peak hour):
  - $10,000 \text{ users} \times 7 \text{ queries} = \mathbf{70,000 \text{ simultaneous complex database queries}}$.
  - Even with database connection pooling, 70,000 queries will saturate Postgres connection queues, causing HTTP 504 Gateway Timeouts, client retry storms, and service outage.

### 3.6 Artwork and Media
* **Implementation:** Standard Flutter `Image.network` across all UI widgets (`HomePage`, `ArtistDetailPage`, `PlayerPage`, `QueuePage`).
* **Behavior under load:**
  - Standard `Image.network` caches only in temporary RAM (`PaintingBinding.instance.imageCache`, max 1000 images or 100MB).
  - Every time the app process restarts or RAM is reclaimed, all artwork is re-downloaded over the public internet from Deezer and YouTube CDNs.
  - While this does not burden Miee's database, it wastes user cellular data, causes image flicker, and triggers unnecessary mobile battery drain.

---

## 4. Confirmed Bottlenecks & Risk Classifications

| Risk ID | Component | Severity | Description | Evidence File & Line |
|---|---|---|---|---|
| **BOT-01** | `SyncManager` | **CRITICAL** | Cascading unpaginated 7-table sync queries per active user on sync trigger. Generates 70,000 queries at 10K CCU. | [`lib/core/sync/sync_manager.dart#L248-L380`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/sync_manager.dart#L248-L380) |
| **BOT-02** | Supabase Realtime | **CRITICAL** | Default Supabase Realtime concurrent connection quota is 200 (Free) or 500 (Pro). Fails when room users exceed 500. | [`lib/features/rooms/data/room_repository.dart#L324-L442`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/rooms/data/room_repository.dart#L324-L442) |
| **BOT-03** | Database Pooler | **CRITICAL** | Direct Postgres connections on Small/Medium compute are capped at 60–120 connections. Exceeded without Supavisor pooling. | [`supabase/migrations/20261024000000_init_miee_schema.sql`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/supabase/migrations/20261024000000_init_miee_schema.sql) |
| **BOT-04** | YouTube Data API | **HIGH** | If `YOUTUBE_API_KEY` is configured, 10,000 units/day quota collapses at 100 searches total ($100 \times 100 = 10,000$). | [`lib/features/youtube/data/youtube_data_source.dart#L9-L50`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/youtube/data/youtube_data_source.dart#L9-L50) |
| **BOT-05** | Image Caching | **MEDIUM** | No persistent disk cache for artwork (`Image.network` instead of disk-cached provider). Redownloads images on restart. | [`lib/features/home/presentation/home_page.dart#L855`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/home/presentation/home_page.dart#L855) |
| **BOT-06** | Deezer Public API | **MEDIUM** | Deezer API rate limit is 50 requests / 5 seconds per IP. Shared Wi-Fi networks could experience throttling. | [`lib/features/onboarding/data/artist_discovery_repository.dart#L91`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/features/onboarding/data/artist_discovery_repository.dart#L91) |

---

## 5. Architectural Verdict

- **100 Concurrent Users:** **READY NOW**. Zero modifications required.
- **500 Concurrent Users:** **MARGINAL**. Requires Supabase Pro tier for Realtime quota.
- **1,000 Concurrent Users:** **UNSAFE**. `SyncManager` queries will cause intermittent HTTP 504 timeouts.
- **5,000 Concurrent Users:** **FAIL**. Database connection exhaustion; Realtime WebSocket disconnects.
- **10,000 Concurrent Users:** **FAIL**. Complete system lockout unless delta-sync, Supavisor connection pooling, and compute scaling are implemented.

