# Miee — Infrastructure Cost & Capacity Modeling

**Document Version:** 1.0.0  
**Date:** November 5, 2026  
**Pricing Basis:** Official Supabase, Cloudflare, and Sentry Published Rates (Q4 2026)  
**Target Concurrencies:** 100 | 1,000 | 5,000 | 10,000 Concurrent Active Users (CCU)  

---

## 1. Executive Cost Summary

Due to Miee's decentralized client-side audio playback architecture (where mobile devices resolve and stream audio bytes directly from Google Video CDN via ExoPlayer), **Miee incurs \$0 in audio streaming bandwidth, CDN egress, and media server compute**. 

The infrastructure costs are solely driven by:
1. **Supabase Database Compute & Connection Pooling (PostgreSQL / PostgREST)**
2. **Supabase Realtime WebSocket Concurrent Connection Quotas (Listening Rooms)**
3. **Database Egress Bandwidth (Sync & Profile Metadata)**
4. **Application Monitoring & Error Tracing (Sentry / Datadog)**

```
+-------------------------------------------------------------------------------------------------+
|                                 Total Monthly Operating Cost Model                              |
+--------------------------+-----------------+-----------------+-----------------+----------------+
| Concurrent Users (CCU)   | 100 CCU         | 1,000 CCU       | 5,000 CCU       | 10,000 CCU     |
| Est. Registered MAU      | ~5,000 MAU      | ~50,000 MAU     | ~250,000 MAU    | ~500,000 MAU   |
+--------------------------+-----------------+-----------------+-----------------+----------------+
| Supabase Base Plan       | $0 (Free)       | $25 (Pro)       | $25 (Pro)       | $25 (Pro)      |
| Compute Add-on           | $0 (Shared)     | $50 (Medium)    | $220 (XL)       | $440 (2XL)     |
| Realtime CCU Add-on      | $0 (Incl. 200)  | $10 (1k quota)  | $45 (5k quota)  | $95 (10k quota)|
| Egress Bandwidth         | $0 (Incl.)      | $0 (Incl. 250GB)| $18 (450GB)     | $67 (1,000GB)  |
| Database Storage & PITR  | $0 (Incl.)      | $5              | $15             | $30            |
| Monitoring & APM         | $0 (Free)       | $26 (Sentry)    | $80 (Sentry)    | $150 (Sentry)  |
+--------------------------+-----------------+-----------------+-----------------+----------------+
| TOTAL ESTIMATED COST     | $0 / month      | $116 / month    | $403 / month    | $807 / month   |
+--------------------------+-----------------+-----------------+-----------------+----------------+
| Cost Per Concurrent User | $0.00           | $0.116 / CCU    | $0.081 / CCU    | $0.081 / CCU   |
+--------------------------+-----------------+-----------------+-----------------+----------------+
```

---

## 2. Granular Cost Breakdown by Concurrency Tier

### Tier 1: 100 Concurrent Active Users (~5,000 MAU)
- **Primary Use Case:** Development, closed beta testing, internal family & friend cohort.
- **Infrastructure Plan:** **Supabase Free Tier ($0/month)**.
  - Compute: Shared Micro CPU / 1GB RAM ($0).
  - Realtime Connections: 200 included ($0). Max 100 room users easily fits within quota.
  - Database Storage: 500MB included ($0).
  - Bandwidth: 5GB included ($0).
  - Monitoring: Sentry Developer Plan (Free up to 5,000 errors/mo).
- **Monthly Infrastructure Outlay:** **$0.00**.

### Tier 2: 1,000 Concurrent Active Users (~50,000 MAU)
- **Primary Use Case:** Public beta launch, regional viral adoption.
- **Infrastructure Plan:** **Supabase Pro Tier ($25/mo base)**.
  - Compute Add-on: **Medium Compute (2-core vCPU, 4GB RAM) = $50/mo**.
    - Handles Supavisor transaction connection pooling for up to 1,000 active sessions.
  - Realtime Add-on: $10/mo (expands quota to 1,500 simultaneous WebSockets).
  - Bandwidth: Included 250GB/mo is more than sufficient with delta-sync.
  - Storage & Daily Backups: Included 8GB disk ($0) + $5 backup storage.
  - Monitoring: Sentry Team Plan ($26/mo).
- **Monthly Infrastructure Outlay:** **$116.00**.

### Tier 3: 5,000 Concurrent Active Users (~250,000 MAU)
- **Primary Use Case:** Scaled nationwide user base.
- **Infrastructure Plan:** **Supabase Pro + XL Dedicated Compute**.
  - Compute Add-on: **XL Compute (4-core vCPU, 16GB RAM, 6,000 IOPS) = $220/mo**.
    - Ensures PostgreSQL buffer cache can hold all hot indexes and active listening room states in RAM.
  - Realtime Add-on: $45/mo (covers up to 5,000 concurrent WebSockets).
  - Bandwidth: 450GB estimated total egress -> 250GB included + 200GB overage ($0.09/GB) = $18/mo.
  - Database Disk: 30GB allocated ($0.021/GB beyond 8GB) = $15/mo.
  - Monitoring: Sentry Business Plan ($80/mo).
- **Monthly Infrastructure Outlay:** **$403.00**.

### Tier 4: 10,000 Concurrent Active Users (~500,000 MAU)
- **Primary Use Case:** Full Production Target Concurrency.
- **Infrastructure Plan:** **Supabase Pro + 2XL Dedicated Compute**.
  - Compute Add-on: **2XL Compute (8-core vCPU, 32GB RAM, 10,000 IOPS) = $440/mo**.
    - Accommodates 5,000–8,000 queries per second with sub-50ms P95 latency.
  - Realtime Add-on: $95/mo (covers the full 10,000 concurrent WebSocket limit).
  - Bandwidth: ~1,000GB monthly metadata egress -> 750GB overage ($0.09/GB) = $67/mo.
  - Database Disk & PITR: 60GB disk + 14-day PITR retention = $30/mo.
  - Monitoring: Sentry Enterprise / Datadog APM = $150/mo.
- **Monthly Infrastructure Outlay:** **$807.00**.

---

## 3. Financial Sensitivity & Cost Risk Analysis

1. **The Audio Bandwidth Non-Risk:**
   If Miee were forced to proxy or host its own audio CDN (e.g. 5MB per song $\times$ 15 songs per user per day $\times$ 10,000 users = 750 GB/day = 22.5 TB/month), bandwidth costs on AWS CloudFront would exceed **$1,800/month**. Because Miee delegates playback directly to YouTube's CDN, this cost is **$0**.
2. **The Sync Storm Cost Risk:**
   Without the Phase B incremental delta-sync optimization, 10,000 users performing full-table scans will generate over 4 TB of redundant egress bandwidth, ballooning Supabase bandwidth overage bills by over **$360/month**. Implementing delta-sync protects against this bill shock.
3. **Supabase Realtime Quota Protection:**
   Realtime connections must be explicitly closed when users background the app or leave listening rooms to avoid paying for zombie idle connections.

