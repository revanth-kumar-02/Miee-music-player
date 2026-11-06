# Miee — Supabase Connection & Pooling Architectural Audit

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Auditor:** Senior Backend & Mobile Systems Engineer  
**Scope:** Connection management, Supavisor pooling topology, PostgREST concurrency, and pooler mode compatibility across Miee services.

---

## 1. Executive Summary

A critical misconception in mobile architecture is assuming client SDKs connect directly to PostgreSQL over TCP port 5432 and therefore need client-side redirection to Supavisor transaction pooler port 6543. 

**Finding:** The Miee Flutter application **never** connects directly to PostgreSQL. All client database operations are routed over HTTPS to PostgREST and GoTrue, while real-time room communication connects over WebSockets to the Supabase Realtime Phoenix cluster. 

PostgREST itself maintains an internal, server-side connection pool to PostgreSQL. However, administrative connections, Edge Functions, automated CI/CD migrations, and direct server scripts must use Supavisor to prevent exhausting PostgreSQL's `max_connections` (60–120 on standard compute) as concurrent user load reaches 10,000 CCU.

---

## 2. Verified Connection Paths by Component

```
+---------------------------------------------------------------------------------------------------------+
|                                    Miee Concurrency Architecture                                        |
+---------------------+-------------------+-------------------------------+-------------------------------+
| Client / Service    | Protocol & Port   | Server Endpoint               | Pooling Behavior              |
+---------------------+-------------------+-------------------------------+-------------------------------+
| Flutter Mobile App  | HTTPS (443)       | PostgREST (`/rest/v1`)        | PostgREST server-side pool    |
| Flutter Mobile App  | HTTPS (443)       | GoTrue Auth (`/auth/v1`)      | Dedicated Auth connection pool|
| Flutter Mobile App  | WSS (443)         | Realtime (`/realtime/v1`)     | Elixir Phoenix connection pool|
| DB Migrations & CLI | TCP (5432 / 6543) | PostgreSQL / Supavisor        | Direct / Transaction Pooler   |
| Supabase Functions  | TCP (6543)        | Supavisor (Transaction Mode)  | Multi-tenant pooler (10K cap) |
+---------------------+-------------------+-------------------------------+-------------------------------+
```

### A. Flutter Mobile Client (`supabase_flutter`)
- **HTTPS PostgREST API:** In [`lib/core/sync/supabase_config.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/lib/core/sync/supabase_config.dart), the client initializes with `https://qjvjmruovmftcbwrfjsq.supabase.co`. Every table query (`from('profiles')`, `from('liked_songs')`, etc.) and RPC (`rpc('create_room')`, `rpc('join_room')`) is a stateless HTTP/2 REST request.
- **Why Port 6543 Must NOT Be Configured in Flutter:** Supavisor on port 6543 is a raw PostgreSQL wire protocol proxy. Pointing the Flutter `SupabaseClient` URL to `https://...:6543` would cause HTTP requests to fail with connection reset or TLS handshake errors. The Flutter configuration is correct as designed.

### B. Supabase PostgREST Connection Management
- PostgREST runs on the Supabase container infrastructure and pools connections to the local Postgres database.
- By default, PostgREST maintains a pool of `db_pool = 10` to `20` database connections, which multiplex thousands of incoming HTTP requests per second.
- **Risk:** If hundreds of Flutter clients execute unpaginated, slow sequential queries simultaneously (e.g. unindexed `playlist_tracks` or multiple overlapping `triggerSync()` executions), PostgREST connections become held waiting on Postgres lock/I/O, causing HTTP 504 Gateway Timeouts. This is solved by **REM-01** (indexes) and **REM-03** (sync debouncing).

### C. Direct PostgreSQL Connections (Developer CLI, Edge Functions, Migrations)
- Supabase provides two direct database connection strings:
  1. **Direct Connection:** `db.<ref>.supabase.co:5432` — Session mode, directly touches PostgreSQL processes. Limited by `max_connections` (60 for Micro/Small, 120 for Medium).
  2. **Supavisor Transaction Pooler:** `aws-0-<region>.pooler.supabase.com:6543` — Transaction mode. Multiplexes thousands of clients over a small pool of active backend connections.
  3. **Supavisor Session Pooler:** `aws-0-<region>.pooler.supabase.com:5432` — Session mode via pooler (supports prepared statements and temporary tables).

---

## 3. Pooler Mode Compatibility Analysis

| Mode | Port | Best Used For | Prepared Statements | Max Concurrency | Compatibility in Miee |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Transaction Mode** | `6543` | Serverless functions, high-throughput APIs, short stateless queries | ❌ Not supported (must use text mode or close prepared stmts) | 10,000+ | Recommended for server-side services and Edge Functions |
| **Session Mode** | `5432` | Schema migrations, DDL (`ALTER TABLE`, `CREATE INDEX`), stateful CLI scripts | ✅ Fully supported | Limited by database compute RAM | Mandatory for migrations (`supabase db push`) |

---

## 4. Current Status & Required Configuration

### What Is Already Correct
1. **Flutter Client Transport:** Uses HTTPS PostgREST, avoiding PostgreSQL direct connection leaks or client-side connection drops.
2. **Secrets Protection:** Service role keys and database passwords are not hardcoded in the client application; only the public `anonKey` is present.
3. **Prepared Statements:** Client queries through PostgREST are translated server-side and do not conflict with Supavisor transaction pooling.

### What Requires Manual Supabase Dashboard Configuration
To ensure the backend infrastructure supports 10,000 concurrent users:

1. **Verify Supavisor Is Active in Supabase Dashboard:**
   - Navigate to: **Project Settings &rarr; Database &rarr; Connection Pooling**.
   - Verify that **Connection Pooler** is enabled.
   - **Pool Mode:** Transaction.
   - **Default Pool Size:** 20 (can scale up to 40% of `max_connections`).

2. **Realtime WebSocket Connection Quota:**
   - Free tier caps concurrent Realtime connections at 200.
   - Pro tier default caps concurrent Realtime connections at 500.
   - Navigate to: **Project Settings &rarr; Billing &rarr; Add-ons**.
   - Enable **Realtime Concurrent Connections** to support at least 1,500 simultaneous WebSockets for active Listening Rooms.

3. **Statement Timeout Configuration:**
   - To prevent long-running unindexed queries from holding pool connections indefinitely:
   ```sql
   alter role authenticator set statement_timeout = '8s';
   ```
   This ensures runaway client queries fail gracefully rather than saturating the connection pool.

---

## 5. Architectural Recommendation Summary

1. **Flutter Client:** Keep the current HTTPS initialization in `lib/core/sync/supabase_config.dart`. Do **not** redirect to port 6543.
2. **Database:** Deploy compound indexes (**REM-01**) so queries complete in $< 5\text{ ms}$, freeing PostgREST connections back to the pool instantly.
3. **Application Synchronization:** Enforce in-flight mutex and request cooldown (**REM-03**) to prevent client query storms from exhausting PostgREST pool workers.

