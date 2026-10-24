# Miee — Supabase Backend Migration & Firebase Removal Report

**Date:** October 24, 2026  
**Status:** COMPLETED & VERIFIED  

---

## 1. Executive Summary
The backend for Miee has been successfully migrated from Firebase to Supabase. All 7 phases (including Complete Firebase Removal) have been executed with strict REA standards:
- All Firebase SDKs (`firebase_core`, `firebase_auth`, `cloud_firestore`) and Gradle plugins have been completely removed.
- Supabase Flutter SDK (`supabase_flutter: ^2.6.0`) is initialized and active using the official publishable anon key.
- Production Postgres database schema with RLS, atomic functions, and Realtime publications has been version-controlled and applied to Supabase project `qjvjmruovmftcbwrfjsq`.
- Local user data in Hive (`favorites`, `playlists`, `profile`, `playbackHistory`, `mostPlayed`, `searchHistory`) remains intact, ensuring zero data loss and seamless offline playback.
- Complete test suite passed (17/17 tests), static analysis passed with zero errors, and Android APK debug build succeeded cleanly.

---

## 2. Phase-by-Phase Audit & Implementation

### Phase 1: Audit & Backup
- **Firebase Dependencies Audited:**
  - `firebase_core: ^4.15.0`
  - `firebase_auth: ^6.7.0`
  - `cloud_firestore: ^6.10.0`
  - `android/settings.gradle.kts`: Google Services Gradle plugin 4.4.2
  - `android/app/build.gradle.kts`: `apply(plugin = "com.google.gms.google-services")`
  - `lib/firebase_options.dart` and `lib/core/services/firebase_service.dart`
- **Data Inventory:**
  - **Local Persistence:** Hive boxes (`favorites`, `playlists`, `profile`, `playbackHistory`, `recentlyPlayed`, `mostPlayed`, `searchHistory`, `offlineQueue`).
  - **Cloud Data:** User profiles and listening history in Firestore.
- **Safety & Backups:**
  - Original `google-services.json` backed up to `docs/firebase_backup/google-services.json` and `android/app/google-services.json.bak`.
  - Legacy Firebase implementations backed up to `docs/firebase_backup/`.
  - Remote Firebase project `miee-1ff89` was never modified or deleted.

---

### Phase 2: Supabase Setup
- **SDK:** `supabase_flutter: ^2.6.0`
- **Configuration:** Initialized in `lib/core/sync/supabase_config.dart`:
  - **Project Ref:** `qjvjmruovmftcbwrfjsq`
  - **Region:** `ap-northeast-1` (Tokyo)
  - **URL:** `https://qjvjmruovmftcbwrfjsq.supabase.co`
  - **Key:** Public anonymous key (`anon`) — zero service-role keys exposed.
  - Supports `--dart-define=SUPABASE_URL=...` and `--dart-define=SUPABASE_ANON_KEY=...` overrides.
  - Initialized with PKCE authentication flow and Realtime support in `lib/main.dart`.

---

### Phase 3 & 4: Database Schema, Security (RLS) & Realtime
Two version-controlled migrations were applied to the remote Supabase database:
1. `supabase/migrations/20261024000000_init_miee_schema.sql`
2. `supabase/migrations/20261024000001_sync_auxiliary_tables.sql`

| Table | Primary Key | Foreign Keys / Constraints | RLS Enforcement | Realtime |
|---|---|---|---|---|
| `profiles` | `id` (uuid) | `auth.users(id) on delete cascade` | Owner read (`auth.uid() = id`), owner update/insert | No |
| `playlists` | `id` (text) | `user_id -> auth.users(id)` | Owner CRUD (`auth.uid() = user_id`) | No |
| `playlist_tracks` | `id` (text) | `playlist_id -> playlists(id) on delete cascade`, `unique(playlist_id, track_id)` | Owner CRUD, deterministic `position` index | No |
| `liked_songs` | `id` (text) | `user_id -> auth.users`, `unique(user_id, track_id)` | Owner CRUD | No |
| `rooms` | `id` (text) | `host_id -> auth.users`, `capacity between 1 and 5`, `status in ('active','ended','paused')` | Viewable by members/host, editable only by host | Yes |
| `room_members` | `id` (text) | `room_id -> rooms(id)`, `user_id -> auth.users`, `unique(room_id, user_id)` | Viewable by members, removable by self or host | Yes |
| `room_state` | `room_id` (text) | `room_id -> rooms(id)`, `updated_by -> auth.users` | Read by members; **Update only by room host** | Yes |
| `history` | `id` (uuid) | `user_id -> auth.users` | Owner CRUD | No |
| `most_played` | `id` (text) | `user_id -> auth.users`, `unique(user_id, track_id)` | Owner CRUD | No |
| `search_history`| `id` (text) | `user_id -> auth.users`, `unique(user_id, query)` | Owner CRUD | No |

#### Server-Side Atomic Room Join (`join_room` RPC)
Enforced in Postgres:
- Locks the room row with `FOR UPDATE` to prevent race conditions during concurrent join requests.
- Counts active members including the host against room capacity (1–5).
- Rejects joins once capacity is reached or if room status is not `'active'`.
- Idempotently handles users already in the room.

---

### Phase 5: Flutter Feature Integration
- **Auth:**
  - `lib/features/auth/domain/auth_repository.dart`
  - `lib/features/auth/data/supabase_auth_repository.dart`
  - `lib/features/auth/providers/auth_providers.dart`
  - Full support for signup, login, password reset, logout, and session restoration via Supabase Auth.
- **Profiles & Onboarding:**
  - `lib/features/profile/domain/user_profile_repository.dart`
  - `lib/features/profile/data/supabase_user_profile_repository.dart`
  - `lib/features/profile/providers/profile_providers.dart`
  - Seamless caching in Hive with remote sync to `profiles` table.
- **Listening History:**
  - `lib/features/history/domain/listening_history_repository.dart`
  - `lib/features/history/data/supabase_listening_history_repository.dart`
  - `lib/features/history/providers/history_providers.dart`
  - `lib/features/recommendations/data/recommendation_service.dart`
- **Library Sync:**
  - `lib/core/sync/sync_manager.dart`
  - Replays offline queues and reconciles `liked_songs` and `playlist_tracks` with deterministic positional ordering.
- **Realtime Listening Rooms:**
  - `lib/features/rooms/domain/room_models.dart`
  - `lib/features/rooms/data/room_repository.dart`
  - `lib/features/rooms/providers/room_providers.dart`
  - Full client-side API for hosting, joining, leaving, host-only playback state updates, and subscribing to Postgres changes over WebSockets.

---

### Phase 6 & 7: Verification & Firebase Removal
- **All Firebase Dependencies Removed:**
  - Removed `firebase_core`, `firebase_auth`, `cloud_firestore` from `pubspec.yaml`.
  - Removed `com.google.gms.google-services` plugin from `android/settings.gradle.kts` and `android/app/build.gradle.kts`.
  - Deleted legacy Firebase Dart files and `google-services.json` from active trees.
- **Static Analysis:**
  - `flutter analyze`: **0 compile errors** across the entire workspace.
- **Test Suite Results:**
  - `test/supabase_backend_integration_test.dart`: 6/6 PASSED
  - `test/account_name_resolution_test.dart`: 4/4 PASSED
  - `test/auth_onboarding_recommendations_test.dart`: 7/7 PASSED
  - Total: **17/17 tests passing**.
- **Android APK Build:**
  - `flutter build apk --debug`: **SUCCESS** (`build\app\outputs\flutter-apk\app-debug.apk`), verifying clean build without Google Services or Firebase plugins.
