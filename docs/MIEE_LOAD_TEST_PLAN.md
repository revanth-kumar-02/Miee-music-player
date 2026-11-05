# Miee — 10K Concurrent Users Load Testing Plan

**Document Version:** 1.1.0  
**Status:** **READY FOR STAGING EXECUTION (Strictly Isolated Testing Protocol)**  
**Safety Classification:** Synthetic Staging Testing Protocol Only  

---

## 1. Objectives & Scope

This test plan defines a safe, reproducible, and verifiable methodology for stress-testing Miee's backend services (Supabase PostgREST, GoTrue Auth, and Realtime WebSockets) up to **10,000 Concurrent Users (CCU)**.

### Strict Safety & Anti-Abuse Directives
1. **Never Flood Production YouTube Endpoints:** Real YouTube stream resolutions must NEVER be used as an uncontrolled load generator. External YouTube calls must be mocked with synthetic responses simulating typical 300ms network latency.
2. **Never Test Against Production Supabase Database Unannounced:** Run tests exclusively against a dedicated staging branch or project (`miee-staging`), using synthetic test user pools.
3. **Dedicated Realtime WebSocket Testing:** Test Realtime separately at the actual target connection counts (up to 10,000 connections using distributed workers). **Do not claim 10K WebSocket capacity based on a 1K connection test.**
4. **Graceful Abort Triggers:** Automated test runners must abort immediately if error rate exceeds 2%, median latency exceeds 2,000ms, or database CPU exceeds 85% for more than 60 seconds.

---

## 2. Realistic User Behavior Profiles

To replicate true production conditions, the simulated 10,000 CCU population is decomposed into three behavioral cohorts:

```
+-------------------------------------------------------------------------------------------------+
|                                    10,000 CCU Cohort Distribution                               |
+--------------------------+------------+---------------------------------------------------------+
| Cohort                   | Percentage | Simulated Behaviors & Network Activity                   |
+--------------------------+------------+---------------------------------------------------------+
| A. Passive Listeners     | 70% (7,000)| Heartbeat sync every 5 mins, background playback, zero  |
|                          |            | search, 1 library update per hour.                      |
| B. Active Searchers      | 20% (2,000)| 1 search query every 45s, scrolling results, adding to  |
|                          |            | queue, toggling 3 likes per hour.                       |
| C. Room Participants     | 10% (1,000)| Persistent WebSocket connection, receiving state change |
|                          |            | broadcasts, 1 chat message every 60s, host sync.        |
+--------------------------+------------+---------------------------------------------------------+
```

---

## 3. Staged Load Progression

Tests must proceed through discrete stages with mandatory 5-minute cool-down and health checks between stages:

| Stage | Concurrent Virtual Users (VUs) | Target RPS (Requests/Sec) | Target Realtime WS | Focus Areas | Cooldown Period |
|---|---|---|---|---|---|
| **Baseline** | 10 | 5 req/s | 10 | Baseline latency & health | 3 minutes |
| **Stage 1** | 100 | 50 req/s | 100 | Free-tier ceiling validation | 5 minutes |
| **Stage 2** | 500 | 250 req/s | 500 | Pro-tier default quota limits | 5 minutes |
| **Stage 3** | 1,000 | 500 req/s | 1,000 | Supavisor pooler validation | 10 minutes |
| **Stage 4** | 5,000 | 2,500 req/s | 5,000 | Postgres IOPS & memory limits | 15 minutes |
| **Stage 5** | 10,000 | 5,000 req/s | 10,000 | Target capacity & Realtime cluster | 20 minutes |

---

## 4. Key Performance Indicators & Pass/Fail Criteria

| Metric | Target SLA (Stage 1–3) | Target SLA (Stage 5 @ 10K CCU) | Failure Threshold |
|---|---|---|---|
| **PostgREST Read Latency (P50)** | $< 50\text{ ms}$ | $< 120\text{ ms}$ | $> 250\text{ ms}$ |
| **PostgREST Read Latency (P95)** | $< 150\text{ ms}$ | $< 350\text{ ms}$ | $> 1,000\text{ ms}$ |
| **PostgREST Write Latency (P95)** | $< 200\text{ ms}$ | $< 500\text{ ms}$ | $> 1,500\text{ ms}$ |
| **Realtime Broadcast Latency** | $< 100\text{ ms}$ | $< 300\text{ ms}$ | $> 800\text{ ms}$ |
| **HTTP Error Rate (4xx / 5xx)** | $< 0.05\%$ | $< 0.1\%$ | $> 1.0\%$ |
| **Database CPU Utilization** | $< 40\%$ | $< 70\%$ | $> 85\%$ sustained |
| **Connection Pool Saturation** | $< 50\%$ | $< 80\%$ | $100\%$ (Rejections) |
| **Realtime Connection Drop Rate** | $< 0.01\%$ | $< 0.05\%$ | $> 0.5\%$ |
| **Sync Payload Size (Delta Sync)**| $< 15\text{ KB}$ | $< 15\text{ KB}$ | $> 100\text{ KB}$ |
| **Mobile Client Memory Footprint**| $< 180\text{ MB}$ | $< 220\text{ MB}$ | $> 350\text{ MB}$ |

---

## 5. Automated Abort Conditions

The load generation harness must automatically stop tests and trigger immediate cool-down if any of the following occur:
1. **HTTP Error Rate $\ge 2.0\%$** over any consecutive 30-second window.
2. **Median Request Latency (P50) $\ge 2,000\text{ ms}$** on PostgREST queries.
3. **Database CPU $\ge 85\%$ sustained** for 60 seconds.
4. **Any dropped connection** on the Supavisor connection pooler.
5. **Realtime WebSocket handshake failure rate $\ge 1.0\%$**.

---

## 6. Executable Load Test Scripts

### 6.1 PostgREST REST API Load Test (`tools/load_test_postgrest.js`)

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '3m', target: 500 },
    { duration: '5m', target: 1000 },
    { duration: '5m', target: 5000 },
    { duration: '10m', target: 10000 },
    { duration: '3m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<350', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.SUPABASE_URL || 'https://staging.supabase.co';
const ANON_KEY = __ENV.SUPABASE_ANON_KEY || 'staging-key';

export default function () {
  const headers = {
    'apikey': ANON_KEY,
    'Authorization': `Bearer ${ANON_KEY}`,
    'Content-Type': 'application/json',
  };

  // 1. User Profile Fetch
  const profileRes = http.get(`${BASE_URL}/rest/v1/profiles?select=*&limit=1`, { headers });
  check(profileRes, { 'profile 200': (r) => r.status === 200 });

  sleep(1);

  // 2. Incremental Liked Songs Sync Fetch (bounded)
  const likesRes = http.get(`${BASE_URL}/rest/v1/liked_songs?select=*&limit=25`, { headers });
  check(likesRes, { 'liked_songs 200': (r) => r.status === 200 });

  sleep(2);

  // 3. Active Rooms Discovery
  const roomsRes = http.get(`${BASE_URL}/rest/v1/rooms?status=eq.active&select=id,name,capacity&limit=10`, { headers });
  check(roomsRes, { 'active rooms 200': (r) => r.status === 200 });

  sleep(5);
}
```

### 6.2 Standalone 10,000 WebSocket Connection Test (`tools/load_test_realtime_10k.js`)

```javascript
import ws from 'k6/ws';
import { check, sleep } from 'k6';

// Distributed k6 execution plan targeting up to 10,000 simultaneous WebSockets
export const options = {
  stages: [
    { duration: '2m', target: 1000 },
    { duration: '5m', target: 5000 },
    { duration: '10m', target: 10000 },
    { duration: '5m', target: 10000 },
    { duration: '3m', target: 0 },
  ],
};

const WS_URL = __ENV.SUPABASE_WS_URL || 'wss://staging.supabase.co/realtime/v1/websocket?apikey=STAGING_KEY&vsn=1.0.0';

export default function () {
  const roomId = `load-test-room-${__VU % 250}`; // 250 active rooms
  const res = ws.connect(WS_URL, {}, function (socket) {
    socket.on('open', () => {
      socket.send(JSON.stringify({
        topic: `realtime:room:${roomId}`,
        event: 'phx_join',
        payload: {},
        ref: '1',
      }));
    });

    socket.on('message', (data) => {
      check(data, { 'message received': (d) => d.length > 0 });
    });

    socket.on('error', (e) => {
      console.error(`WebSocket Error on VU ${__VU}:`, e);
    });

    // Keep connection alive for test duration
    socket.setTimeout(() => {
      socket.close();
    }, 180000);
  });

  check(res, { 'connected 101': (r) => r && r.status === 101 });
}
```

---

## 7. Staging Environment Requirements Checklist
- [ ] Staging Supabase project created in `ap-northeast-1` with identical schema and RLS policies.
- [ ] Database initialized with 10,000 synthetic auth users and realistic seeded liked songs/playlists.
- [ ] Supavisor connection pooler enabled in Transaction Mode (Port 6543).
- [ ] Standalone mock server running for synthetic YouTube/Deezer API responses.
- [ ] Grafana / Prometheus agent scraping Supabase host metrics every 5 seconds.
- [ ] Dedicated test runners (e.g. 3x EC2 `c6i.2xlarge` instances) executing distributed k6 workers.
