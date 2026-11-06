# Miee — Benchmark Integrity & Methodology Audit (REM-07)

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Scope:** Independent audit of `tools/staging_load_test.dart` and `docs/MIEE_LOAD_TEST_RESULTS.md` against real-world network, database, and auth behavior.

---

## 1. Executive Summary & Verification Matrix

The script [`tools/staging_load_test.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/tools/staging_load_test.dart) served as a local asynchronous client event-loop simulation. However, evaluating it against full end-to-end production standards reveals that it was a **synthetic client-side micro-benchmark**, not an end-to-end network load test against live Supabase infrastructure.

```
+---------------------------------------------------------------------------------------------------------+
|                                    Benchmark Integrity Scorecard                                        |
+---+---------------------------------------------------+--------------------+----------------------------+
| # | Verification Criterion                            | Actual Status      | Classification             |
+---+---------------------------------------------------+--------------------+----------------------------+
| 1 | Connected to dedicated staging Supabase project   | No (In-memory)     | **Failed**                 |
| 2 | Executed against real PostgREST & PostgreSQL      | No (`Future.delay`)| **Failed**                 |
| 3 | Only YouTube stream resolution mocked             | No (DB mocked too) | **Failed**                 |
| 4 | 100–1,000 VUs genuinely concurrent               | Yes (In Dart loop) | **Partially Verified**     |
| 5 | RPS calculated from real completed operations     | Yes (In-process)   | **Verified**               |
| 6 | Latency includes TCP/TLS & network round-trips    | No (Simulated ms)  | **Failed**                 |
| 7 | Requests distributed across real user JWTs        | No (Synthetic IDs) | **Failed**                 |
| 8 | RLS policy evaluation and database lock overhead  | No (Bypassed)      | **Failed**                 |
+---+---------------------------------------------------+--------------------+----------------------------+
```

---

## 2. Granular Technical Findings

### A. Synthetic Delay vs. Real Network I/O
In `staging_load_test.dart`:
```dart
Future<int> _mockIndexedQuery() async {
  final delayMs = 5 + _rng.nextInt(20);
  await Future.delayed(Duration(milliseconds: delayMs));
  return delayMs;
}
```
- **Finding:** Database read and write operations were simulated by inserting asynchronous delays between 5ms and 35ms.
- **Impact:** This accurately measured the Dart asynchronous runtime's ability to schedule and handle 14,000+ simultaneous microtasks without event-loop starvation. However, it did **not** generate TCP traffic, perform TLS handshakes, or test PostgREST HTTP gateway saturation.

### B. YouTube Resolution vs. Database Query Isolation
- **Intended Requirement:** Mock only YouTube endpoints (to prevent Google bot challenges and IP blocks), but hit real staging PostgREST and PostgreSQL endpoints.
- **Observed Behavior:** Both YouTube stream resolution and Supabase database requests were simulated inside the local script.

### C. Concurrency Semantics in Dart
- Dart runs on a single-threaded event loop. Launching 1,000 asynchronous worker tasks via `Future.wait()` tests concurrent task scheduling in Dart.
- In production, 1,000 concurrent physical mobile devices communicate over cellular radios with distinct IP addresses, varying latency (30ms–400ms), packet loss, and socket lifecycles.

### D. RLS & Auth Context
- PostgreSQL Row-Level Security (RLS) evaluates `auth.uid() = user_id` on every query.
- Because `staging_load_test.dart` ran in-process sleep functions, PostgreSQL never executed the RLS evaluation routines.

---

## 3. Methodological Correction

To achieve true empirical validation without endangering production:
1. **Separation of Concerns:** 
   - Unit/Widget tests validate Dart client logic, in-flight mutexes, and Hive persistence.
   - Network benchmarks (e.g. via `k6` in [`docs/MIEE_LOAD_TEST_PLAN.md`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/docs/MIEE_LOAD_TEST_PLAN.md)) must issue real HTTP/2 POST/GET requests to PostgREST endpoints.
2. **Readiness Recalibration:**
   - Previous reported RPS (2,599 req/s) reflects **local client event-loop throughput**, not Supabase server network throughput.
   - Production readiness must be downgraded from "Certified" to "Architecturally Prepared (Pending Live Staging PostgREST Execution)".

