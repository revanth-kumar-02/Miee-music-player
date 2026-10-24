# Miee — Release Notes v2.0.0

**Release Version:** `2.0.0` (Build `2`)  
**Release Target:** Android (SDK min 21, target 36) / Flutter  
**Official Support & Inquiries:** `imposterz.rev02@gmail.com`  

---

## 1. Overview

Miee is a minimalist, local-first music player application built with Flutter and Material 3 design principles. Designed with an artisanal Vanilla Cream palette and fluid typography, Miee unifies offline device audio playback with seamless cloud synchronization, synchronized multi-line lyrics, and online audio stream discovery.

Release **v2.0.0** represents a major evolutionary milestone, transitioning the application architecture to a robust Supabase cloud backend, introducing full multilingual lyrics rendering with overflow protection, resolving device sync resilience, and packaging complete legal and attribution documentation.

---

## 2. What's New in v2.0.0

### Local Audio Playback & Media Engine
- **Audio Service Integration:** High-performance background playback, Android media session management, notification drawer controls, and lock-screen playback controls powered by `just_audio` and `audio_service`.
- **Fast Media Scanning:** Local storage discovery with `on_audio_query`, extracting audio metadata (ID3 tags, album artwork, artist, duration, track numbering) with persistent Hive caching.
- **Cache & Storage Control:** In-app tools in Settings to view artwork cache size and database footprint, with granular options to clear image caches or reset library data.

### Multilingual Synchronized Lyrics Overlay
- **Natural Dynamic Height Layout:** Rewritten lyrics viewport supporting multi-line lyrical phrasing without text clipping or truncated lines.
- **Auto-Centering & Fluid Scrolling:** Active line tracking powered by `Scrollable.ensureVisible` with subtle scale emphasis.
- **Opaque Backdrop Guard:** High-legibility opaque card backing eliminating visual ghosting from the underlying album artwork.
- **Fallback Plain Lyrics:** Seamlessly renders unsynchronized plain lyrics when timed timestamps are unavailable.

### Cloud Synchronization & Profile Management
- **Supabase Cloud Backend:** Centralized data persistence for user profiles, liked songs, custom playlists, listening history, and shared listening rooms.
- **Avatar Customization:** Profile picture capture and selection via camera or photo gallery with persistent sandbox storage and top-bar avatar integration.
- **Offline Resilient Sync:** Background sync manager reconciles local Hive boxes with remote PostgreSQL tables, with safe null-coalescing and schema resilience.
- **Authenticated & Guest Modes:** Complete support for anonymous guest listening as well as email/password authentication.

### Online Music Discovery & Shared Listening
- **YouTube Audio Stream Deciphering:** Client-side audio stream manifest extraction via `youtube_explode_dart` for online search and discovery.
- **Deezer Artist Imagery:** Artist discovery cards enriched with high-resolution artist photography from Deezer CDN.
- **Shared Listening Rooms:** Real-time room synchronization for synchronized group listening sessions via Supabase Realtime.

---

## 3. Bug Fixes & Improvements

1. **Resolved Sync Loop ("Sync failed. Retrying..."):**
   - Corrected remote column mapping in `SyncManager` from legacy column names (`created_date`, `last_opened`) to canonical Supabase columns (`created_at`, `updated_at`).
   - Added `DateTime.tryParse` and safe fallback handling to prevent unhandled type errors during database synchronization.

2. **Fixed Lyrics Second-Line Clipping:**
   - Removed fixed 70px height capping in `LyricsOverlay` that clipped translated or wrapped lyric verses in multilingual scripts (such as Tamil, Telugu, Hindi, and Japanese).
   - Applied comfortable line-height (1.45) and card spacing for effortless readability.

3. **Fixed Profile Picture Bottom Sheet Occlusion:**
   - Updated avatar picker modal in Settings and Profile screens with `useRootNavigator: true` and `isScrollControlled: true`, ensuring image selection options are never hidden behind navigation bars.

4. **Streamlined Sign-Out & Navigation State:**
   - Improved GoRouter auth redirect handling and session teardown, ensuring immediate transition to the authentication portal upon signing out.

5. **Enhanced Recently Played Artwork Resolution:**
   - Fixed album artwork resolution for online tracks in the Recently Played feed, ensuring high-resolution thumbnails display consistently.

---

## 4. Known Limitations & Technical Notes

- **Android Signing Configuration:** The release build currently uses debug keystore signing (`signingConfig = signingConfigs.getByName("debug")`) for evaluation and direct device sideloading. Production distribution via Google Play will require an official production keystore and upload key.
- **YouTube Stream Deciphering:** Online stream extraction relies on dynamic manifest deciphering. Changes to YouTube's public web manifest formats may temporarily affect stream resolution until upstream library updates are applied.
- **Repository Licensing Status:** The Miee application codebase currently lacks a root `LICENSE` file. All rights to the application code and branding remain reserved by the maintainer pending official license designation. Third-party libraries remain governed by their respective open-source licenses.

---

## 5. Third-Party Integrations & External Services

| Service | Purpose | Network Domain |
| :--- | :--- | :--- |
| **Supabase** | Authentication, database persistence, and realtime rooms | `*.supabase.co` |
| **LRCLIB** | Open-source synchronized and plain lyrics API | `lrclib.net` |
| **Deezer CDN** | High-resolution artist discovery imagery | `cdn-images.dzcdn.net` |
| **YouTube** | Online audio stream extraction (client-side) | `googlevideo.com`, `youtube.com` |
| **Google Fonts** | Typography fonts (Geist, Playfair Display) | `fonts.googleapis.com` |

---

## 6. Legal & Compliance Documentation

Full release legal documents are bundled within the repository and accessible directly in-app under **Settings → About Miee**:

- **Privacy Policy:** [`docs/PRIVACY_POLICY.md`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/docs/PRIVACY_POLICY.md)
- **Terms of Service:** [`docs/TERMS_OF_SERVICE.md`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/docs/TERMS_OF_SERVICE.md)
- **Open-Source Notices:** [`docs/OPEN_SOURCE_NOTICES.md`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/docs/OPEN_SOURCE_NOTICES.md)
- **Release Readiness Checklist:** [`docs/MIEE_V2_RELEASE_READINESS.md`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/docs/MIEE_V2_RELEASE_READINESS.md)

---

## 7. Official Contact

For technical support, privacy inquiries, licensing questions, or bug reports, please contact:

**Official Support:** `imposterz.rev02@gmail.com`
