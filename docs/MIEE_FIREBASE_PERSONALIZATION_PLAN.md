# Miee — Firebase Authentication, Onboarding & Personalized Music Recommendation Architecture Plan

## 1. Executive Summary & Audit Findings

### 1.1 Current Codebase State (Branch `fix/yt-playback`, HEAD: `0a4b3c6`)
- **Git Status:** Working tree clean on branch `fix/yt-playback`. Commit `0a4b3c6` contains the verified YouTube audio playback fix (`VISIONOS` client bypass for PoToken 403 error).
- **Dependencies (`pubspec.yaml`):**
  - Riverpod `2.5.1` is used for state management.
  - `go_router: ^17.3.0` manages navigation.
  - Audio stack: `just_audio: ^0.10.6`, `audio_service: ^0.18.12`, `audio_session: ^0.2.4`, `youtube_explode_dart: ^3.1.0`.
  - Local storage: `hive: ^2.2.3`, `hive_flutter: ^1.1.0`.
  - Remote sync stub: `supabase_flutter: ^2.6.0` (stubbed with placeholder URLs `https://your-project.supabase.co`; `hasActiveSupabase` returns `false`, effectively no-oping).
  - **Firebase packages:** Not yet added to `pubspec.yaml`.

### 1.2 Startup & Routing Pipeline
- **`lib/main.dart`:**
  1. `WidgetsFlutterBinding.ensureInitialized()`
  2. `await HiveService.init()` (opens 10 boxes: favorites, playlists, recentlyPlayed, mostPlayed, playbackHistory, queueState, searchHistory, preferences, profile, offlineQueue).
  3. `await AudioService.init<MieeAudioHandler>()` (starts foreground service and initializes audio session).
  4. Mounts `ProviderScope` with `MieeApp()`.
- **`lib/app/router/app_router.dart`:**
  - Root route `'/'` renders `SplashPage`.
  - `SplashPage` currently has a hardcoded `Future.delayed(2.5s)` that unconditionally navigates to `context.go('/home')`.
  - No authentication guards (`redirect`), no `refreshListenable`, and no auth/onboarding routes (`/login`, `/register`, `/onboarding`, `/forgot-password`).

### 1.3 State Management & Data Layer
- **Auth:** `lib/features/auth/presentation/auth_controller.dart` currently provides an in-memory/offline guest stub (`isOfflineMock = true`). No real email/password validation, session persistence, or secure token lifecycle.
- **Profile:** `lib/features/profile/` contains `ProfileModel` and `HiveProfileRepository`. Stores single active profile in Hive.
- **Listening History:** `PlaybackHistoryEntry` exists as Hive adapter type 4 (`TrackHiveModel`, `startTime`, `completionPercent`), but was not wired to playback completion events in `PlayerController`.
- **Home UI:** `lib/features/home/presentation/home_page.dart` only binds to local device storage tracks (`on_audio_query`). If local songs are empty, the screen is mostly blank with no online recommendations.
- **YouTube Audio Streaming:** Verified working with `VISIONOS` client resolving clean audio-only streams without 1MB cutoffs. Must remain completely intact.

---

## 2. Firebase Setup & Configuration Architecture

### 2.1 Required FlutterFire Dependencies
```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
```

### 2.2 Android Native Setup (`com.example.miee`)
1. **`android/settings.gradle.kts`:**
   Add Google Services Gradle plugin:
   ```kotlin
   plugins {
       id("dev.flutter.flutter-plugin-loader") version "1.0.0"
       id("com.android.application") version "9.0.1" apply false
       id("org.jetbrains.kotlin.android") version "2.3.20" apply false
       id("com.google.gms.google-services") version "4.4.2" apply false
   }
   ```
2. **`android/app/build.gradle.kts`:**
   Apply plugin:
   ```kotlin
   plugins {
       id("com.android.application")
       id("dev.flutter.flutter-gradle-plugin")
       id("com.google.gms.google-services")
   }
   ```
3. **`android/app/google-services.json`:**
   Placed in `android/app/` from Firebase Console (Package: `com.example.miee`).
4. **`lib/firebase_options.dart`:**
   Generated via `flutterfire configure` or configured with explicit initialization fallback.

### 2.3 Resilient Initialization Guard
In `lib/main.dart`, Firebase must initialize before authentication services run. If Firebase configuration is missing or throws an exception during offline startup, Miee must present an informative error state or graceful fallback rather than hanging on an infinite loading splash.

---

## 3. Data Model & Firestore Architecture

### 3.1 Document Hierarchy
```
firestore
├── users (collection)
│   └── {uid} (document)
│       ├── displayName: string
│       ├── email: string
│       ├── avatarUrl: string?
│       ├── onboardingCompleted: boolean
│       ├── selectedArtistIds: string[]
│       ├── selectedArtists: map[] [ { id, name, imageUrl } ]
│       ├── createdAt: timestamp
│       ├── updatedAt: timestamp
│       ├── schemaVersion: int (1)
│       │
│       ├── preferences (subcollection)
│       │   └── music (document)
│       │       ├── favoriteGenres: string[]
│       │       ├── audioQuality: string
│       │       └── preferredSource: string
│       │
│       └── listeningHistory (subcollection)
│           └── {eventId} (document)
│               ├── trackId: string
│               ├── title: string
│               ├── artist: string
│               ├── artistId: string?
│               ├── source: string ("youtube" | "local")
│               ├── timestamp: timestamp (serverTimestamp)
│               ├── durationSec: int
│               ├── listenedSec: int
│               └── completionRatio: double
```

### 3.2 Offline Caching & Multi-User Isolation (Hive)
- Cache user profile and preferences in Hive keyed by Firebase `uid`:
  - `profile_box.get('profile_${uid}')`
- On `signOut()`:
  - Clear Riverpod providers (`ref.invalidate(...)`).
  - Clear in-flight search and recommendation caches.
  - Reset navigation state to `/login`.

---

## 4. Firestore Security Rules (`firestore.rules`)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    function validProfileData() {
      let data = request.resource.data;
      return data.keys().hasAll(['displayName', 'email', 'onboardingCompleted', 'selectedArtistIds'])
        && data.displayName is string && data.displayName.size() > 0 && data.displayName.size() <= 100
        && data.email is string
        && data.onboardingCompleted is bool
        && data.selectedArtistIds is list
        && (!data.onboardingCompleted || (data.selectedArtistIds.size() >= 3 && data.selectedArtistIds.size() <= 5));
    }

    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId) && validProfileData();
      allow update: if isOwner(userId) && validProfileData();
      allow delete: if isOwner(userId);

      match /preferences/{prefId} {
        allow read, write: if isOwner(userId);
      }

      match /listeningHistory/{eventId} {
        allow read: if isOwner(userId);
        allow create: if isOwner(userId) && request.resource.data.keys().hasAll(['trackId', 'title', 'timestamp']);
        allow update, delete: if isOwner(userId);
      }
    }

    // Default deny
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## 5. Artist Discovery & Recommendation Architecture

### 5.1 Artist Discovery Service
- **Source:** Deezer Public API (`https://api.deezer.com/search/artist?q={query}`) + YouTube metadata fallback.
  - Free, unauthenticated, verified music API.
  - Returns verified artist entities with stable numeric IDs, names, fan counts, and high-res CDN photos (`picture_medium`: 250x250, `picture_big`: 500x500).
  - Handles missing images gracefully with artist initial avatars.
  - Zero scraping; high uptime and fast responses (< 300 ms).
- **Selection Constraints:**
  - Count: Min 3, Max 5.
  - Interactive selection chips with real circular artist avatars.
  - Live counter: `"X of 5 selected"`.
  - Continue button disabled until `3 <= count <= 5`.
  - Non-skippable onboarding guard.

### 5.2 Recommendation Engine (`RecommendationService`)
- **Inputs:**
  1. User selected favorite artists (from profile).
  2. Related artists (via `https://api.deezer.com/artist/{id}/related`).
  3. Real listening history (`listeningHistory` subcollection in Firestore & Hive).
  4. User liked tracks (`favorites` box).
- **Ranking Formula:**
  - Cold Start (no history):
    - Top tracks from each of the 3–5 selected artists (queried via YouTube repository).
    - Related artists discovery shelf.
  - Returning User (with history):
    - Weighted score: $S = w_a \cdot A_{pref} + w_r \cdot R_{recent} + w_f \cdot F_{fav} + w_d \cdot D_{disc}$
    - Deduplication across sections.
    - Excludes failed/unplayable streams.

---

## 6. Implementation Stages & Verification Plan

| Stage | Focus Area | Status | Deliverables |
|---|---|---|---|
| **Stage 1** | **Dependencies & Build Config** | COMPLETED | Added `firebase_core`, `firebase_auth`, `cloud_firestore`; updated Android gradle plugins. |
| **Stage 2** | **Firebase Auth Layer** | COMPLETED | `FirebaseAuthRepository`, `authRepositoryProvider`, `LoginPage`, `RegisterPage` with email/password, reset & logout. |
| **Stage 3** | **Profile & Firestore Repository** | COMPLETED | `FirestoreUserProfileRepository`, `UserProfile`, `firestore.rules`, `firestore.indexes.json`. |
| **Stage 4** | **Artist Discovery Repository & UI** | COMPLETED | `DeezerArtistRepository`, `ArtistSelectionPage`, search, 3–5 artist enforcement, loading/error states. |
| **Stage 5** | **Navigation & Onboarding Guards** | COMPLETED | `AppRouterNotifier` in `app_router.dart` with auth and onboarding redirect guards. |
| **Stage 6** | **Recommendation Engine & Service** | COMPLETED | `RecommendationService`, `recommendationsProvider`, related artist expansion, track deduplication. |
| **Stage 7** | **Personalized Home UI** | COMPLETED | Render personalized greeting, Favourite Artists, From Your Artists, Explore Related Artists, Discover More, Recently Played. |
| **Stage 8** | **Device Verification & Tests** | COMPLETED | Unit tests passed (7/7); regression tests passed (10/10); release APK built & installed on physical device `10BF5809GA0029L`. |

---

## 7. Implementation & Verification Summary

### 7.1 Completed Deliverables
1. **FlutterFire Packages Added:**
   - `firebase_core: ^4.15.0`, `firebase_auth: ^6.7.0`, `cloud_firestore: ^6.10.0` integrated into `pubspec.yaml`.
   - Android Gradle configuration updated in `android/settings.gradle.kts` and conditional Google Services plugin in `android/app/build.gradle.kts`.
2. **Firestore Security Rules & Indexes:**
   - `firestore.rules`: Strict UID ownership boundary on `users/{userId}` and subcollections, preventing spoofing and validating artist count (3-5).
   - `firestore.indexes.json`: Created for `listeningHistory` collectionGroup timestamp ordering.
3. **Domain & Data Layers:**
   - Authentication: `FirebaseAuthRepository` with email/password signup, login, session observation, password reset, and logout.
   - User Profile: `FirestoreUserProfileRepository` with cloud persistence and UID-scoped Hive local caching.
   - Artist Discovery: `DeezerArtistRepository` for real-time artist search, artist pictures, and related-artists queries.
   - Listening History: `FirestoreListeningHistoryRepository` wired to track completion events in `PlayerController`.
   - Recommendation Engine: `RecommendationService` aggregating favourite artists, artist tracks, related artists, discover more, and recently played with deduplication across shelves.
4. **Presentation & UI:**
   - `LoginPage` and `RegisterPage` with validation, forgot password dialog, and loading states.
   - `ArtistSelectionPage` with 3-5 artist enforcement, interactive chips, and search.
   - `HomePage` updated with personalized shelves alongside local device songs.
   - `AppRouterNotifier` with auth & onboarding redirect guards.

### 7.2 Verification Results
- **Unit Tests (`test/auth_onboarding_recommendations_test.dart`):** 7/7 PASSED (Artist parsing, Profile serialization, 3-5 artist validation, ListeningEvent serialization, Recommendation aggregator).
- **Regression Playback & Search Tests (`test/youtube_playback_verification_test.dart`, `test/youtube_search_verification_test.dart`):** 10/10 PASSED. YouTube audio streaming via `VISIONOS` resolver and YouTubeExplode search remain 100% operational.
- **Release Build:** `flutter build apk --release` succeeded, producing `build/app/outputs/flutter-apk/app-release.apk` (63MB).
- **Device Installation:** Installed directly onto physical Android device `10BF5809GA0029L` via ADB (`Performing Streamed Install -> Success`).
- **Device Startup:** App launched cleanly, verified via Android logcat (`com.example.miee`), with graceful initialization handling and smooth navigation.
