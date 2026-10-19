# Miee — Safe Repository Cleanup Report

**Date:** 2026-10-19  
**Branch:** `fix/yt-playback`  
**Purpose:** Pre-UI replication repository audit, decluttering, and structure verification for the Miee music player.

---

## 1. Original Repository Structure Overview

Prior to cleanup, the repository contained a mix of core Flutter production code, newly integrated Stitch design references, historical build outputs, local test diagnostics, and multiple uncommitted experimental artifacts:

- **Root Directory:** Contained stale generated binary outputs (`Miee-debug.apk` [96MB], `Miee-release.apk` [61MB]), runtime log files (`flutter_01.log`), legacy branding PNG (`image.png` [1.2MB]), PowerShell download scripts (`download_designs.ps1`), and root architecture guides (`ANDROID_MANIFEST_INSTRUCTIONS.md`, `MIEE_PROJECT_STATUS.md`).
- **Platform Folders:** Standard platform targets for `android/`, `ios/`, `web/`, and `windows/`. The `android/` directory had an obsolete JVM crash log (`hs_err_pid15440.log` [227KB]).
- **Assets (`assets/`):** Contained the active branding suite under `assets/logo/`, but also harbored an obsolete duplicate folder `assets/assets/logo/` containing 4 redundant icon files.
- **Designs (`design_source/`):** Contained the comprehensive Stitch design system (`design_source/miee_design_system/` with 19 active screens and 21 variant screens), alongside 9 loose unorganized raw HTML prototypes (`1_splash.html` through `9_settings.html`).
- **Tests (`test/`):** Contained 22 Dart test files comprising unit tests, widget tests, regression suites, and 7 ad-hoc YouTube streaming/header diagnostic experiments.
- **End-to-End (`e2e/`):** Full Playwright suite with 8 spec files, comparison scripts, and comparison screenshots.
- **Build & Tooling Caches:** Flutter tooling and build output caches (`build/` ~3.7GB, `.dart_tool/` ~1.4GB, `android/app/build/` ~3.0GB).

---

## 2. Files and Directories Removed

Only confirmed obsolete, temporary, or unreferenced duplicate files were removed. No production code or required platform configurations were deleted:

| File / Directory | Size | Reason for Removal |
|---|---|---|
| `Miee-debug.apk` | 96 MB | Stale debug APK binary at repository root from Oct 1. Regeneratable via `flutter build apk --debug`. Covered by `.gitignore`. |
| `Miee-release.apk` | 61 MB | Stale release APK binary at repository root from Oct 13. Regeneratable via `flutter build apk --release`. Covered by `.gitignore`. |
| `flutter_01.log` | 2.9 KB | Ephemeral run log at root from Oct 16. Covered by `.gitignore`. |
| `android/hs_err_pid15440.log` | 227 KB | Stale JVM crash log from July 16 inside `android/`. Covered by `.gitignore`. |
| `assets/assets/` (4 files) | ~1.5 MB | Confirmed duplicate nested directory (`assets/assets/logo/miee_*`) with 0 references in Dart or platform code. Canonical assets reside in `assets/logo/`. |

**Total Confirmed Deletions:** 5 file entries / ~158.7 MB freed from version control & working tree.

---

## 3. Files Moved and Reorganized

Files that hold historical, diagnostic, or tooling value were relocated to dedicated directories to maintain a clean root and test suite:

| Original Path | New Path | Rationale |
|---|---|---|
| `image.png` (root) | [`assets/logo/archive/old_app_icon_1024.png`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/assets/logo/archive/old_app_icon_1024.png) | Preserved original August 2026 app icon design in the asset archive while eliminating root clutter. |
| `download_designs.ps1` (root) | [`tools/download_designs.ps1`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/tools/download_designs.ps1) | Consolidated all utility scripts into `tools/` and updated destination paths. |
| `design_source/[1-9]_*.html` | [`design_source/initial_exports/`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/design_source/initial_exports/) | Grouped the 9 initial prototype screen exports cleanly away from the primary Stitch design system. |
| `ANDROID_MANIFEST_INSTRUCTIONS.md` (root) | [`docs/ANDROID_MANIFEST_INSTRUCTIONS.md`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/docs/ANDROID_MANIFEST_INSTRUCTIONS.md) | Archived configuration notes in `docs/`. |
| `MIEE_PROJECT_STATUS.md` (root) | [`docs/MIEE_PROJECT_STATUS.md`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/docs/MIEE_PROJECT_STATUS.md) | Retained core milestone tracker in `docs/` alongside other architecture documentation. |
| 7 diagnostic scripts (in `test/`) | [`diagnostics/`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/) | Isolated live network & device diagnostic scripts from headless regression test runner. |

---

## 4. Test Audit & Disposition

Every file under `test/` was audited for purpose, execution environment, and regression value:

### Retained in `test/` (Automated CI / Local Unit & Widget Suites)

1. **[`test/preview_duration_regression_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/preview_duration_regression_test.dart)**:
   - *Purpose:* Validates YouTube full track duration preservation and prevents the 30-second preview URL regression.
   - *Status:* Retained (PASSED).
2. **[`test/search_deduplication_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/search_deduplication_test.dart)**:
   - *Purpose:* Pure unit tests for `SearchDeduplicator` (Lana Del Rey variants, artist collisions, version tags).
   - *Status:* Retained (8/8 PASSED).
3. **[`test/live_search_dedup_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/live_search_dedup_test.dart)**:
   - *Purpose:* Live YouTube integration test confirming canonical search deduplication.
   - *Status:* Retained (PASSED).
4. **[`test/youtube_playback_verification_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/youtube_playback_verification_test.dart)**:
   - *Purpose:* End-to-end stream resolution verification with VISIONOS client, TTL caching, and local track independence.
   - *Status:* Retained (4/4 PASSED).
5. **[`test/youtube_search_verification_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/youtube_search_verification_test.dart)**:
   - *Purpose:* Live query testing (Imagine Dragons, Coldplay) and error propagation handling.
   - *Status:* Retained (6/6 PASSED).
6. **[`test/youtube_audio_service_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/youtube_audio_service_test.dart)**:
   - *Purpose:* In-memory stream caching verification and batch song resolution.
   - *Status:* Retained (PASSED).
7. **[`test/web_music_discovery_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/web_music_discovery_test.dart)**:
   - *Purpose:* Web fallback music discovery source parsing and full duration integrity.
   - *Status:* Retained (PASSED).
8. **[`test/universal_title_normalization_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/universal_title_normalization_test.dart)**:
   - *Purpose:* Validates regex title cleaning, tag stripping, and artist name normalization.
   - *Status:* Retained (PASSED).
9. **[`test/recommendation_and_title_normalization_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/recommendation_and_title_normalization_test.dart)**:
   - *Purpose:* Recommendation aggregation and title deduplication integration test.
   - *Status:* Retained (PASSED).
10. **[`test/auth_onboarding_recommendations_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/auth_onboarding_recommendations_test.dart)**:
    - *Purpose:* Tests Firestore schema roundtrip, Deezer artist model, and onboarding state constraints (3-5 artists).
    - *Status:* Retained (PASSED).
11. **[`test/artist_discovery_and_images_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/artist_discovery_and_images_test.dart)**:
    - *Purpose:* Tests curated artist catalog, fallback image generation, and `ArtistAvatar` widget initials.
    - *Status:* Retained (PASSED).
12. **[`test/widget_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/widget_test.dart)**:
    - *Purpose:* Basic smoke test verifying `SplashPage` title rendering.
    - *Status:* Retained (PASSED).
13. **[`test/now_playing_refinement_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/now_playing_refinement_test.dart)**:
    - *Purpose:* Now Playing UI component layout and playback interaction test.
    - *Status:* Retained (Pre-existing widget structure mismatch noted in Section 7).
14. **[`test/search_page_widget_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/search_page_widget_test.dart)**:
    - *Purpose:* Search page UI rendering for search results and error states.
    - *Status:* Retained (Pre-existing widget state expectation noted in Section 7).
15. **[`test/unified_search_and_artist_profile_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/unified_search_and_artist_profile_test.dart)**:
    - *Purpose:* Unified search and artist profile navigation testing.
    - *Status:* Retained (Pre-existing Indian artist fallback expectation noted in Section 7).

### Moved to `diagnostics/` (Preserved Standalone Diagnostic Scripts)

These 7 files serve specific runtime troubleshooting purposes (such as testing raw byte ranges, probing YouTube client credentials, or testing on-device platform channels) and are documented in [`diagnostics/README.md`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/README.md):

1. **[`diagnostics/device_playback_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/device_playback_test.dart)**: Requires real device/emulator with native audio channels.
2. **[`diagnostics/stream_diag_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/stream_diag_test.dart)**: Inspects itag, bitrate, codecs, and Android client credentials.
3. **[`diagnostics/stream_diag_test2.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/stream_diag_test2.dart)**: Targeted header evaluation for video ID `o0LydWpBQts`.
4. **[`diagnostics/stream_range_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/stream_range_test.dart)**: Tests chunked streaming past the 1MB allowance.
5. **[`diagnostics/visionos_headers_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/visionos_headers_test.dart)**: Tests ExoPlayer UA vs default headers for 2MB chunk fetch.
6. **[`diagnostics/visionos_streams_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/visionos_streams_test.dart)**: Format breakdown for VISIONOS audio streams.
7. **[`diagnostics/lana_test.dart`](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/diagnostics/lana_test.dart)**: Live scratch search and stream manifest fetch.

---

## 5. Stitch Design References Preserved

All design references and assets were 100% preserved and structured:

1. **`design_source/miee_design_system/`**:
   - `DESIGN_SYSTEM.md`: Design tokens, Editorial Tactility theme, typography, color palette, component specifications.
   - `README.md`: Complete catalog of 40 screens with IDs and descriptions.
   - `active_screens/html/`: 19 active HTML prototypes.
   - `active_screens/images/`: 19 high-resolution reference screenshots.
   - `archive_variants/html/`: 21 design variant HTML files.
   - `archive_variants/images/`: 21 variant screenshots.
   - `download_screens.sh`: Official fetch script.
2. **`design_source/initial_exports/`**:
   - `1_splash.html` through `9_settings.html`: Initial exported screen designs.
3. **`tools/download_designs.ps1`**:
   - Updated to point to `design_source/initial_exports/`.

---

## 6. Validation Results (Pre-Cleanup Baseline vs Post-Cleanup)

### A. Dependency Verification (`flutter pub get`)
- **Baseline:** Exited with code 0.
- **Post-cleanup:** Exited with code 0 (`Got dependencies!`).

### B. Code Analysis (`flutter analyze --no-fatal-infos --no-fatal-warnings`)
- **Baseline:** Exited with code 0 (0 compilation/analyzer errors, 375 lint/info warnings).
- **Post-cleanup:** Exited with code 0 (0 compilation/analyzer errors, 375 lint/info warnings).
- **Result:** Identical; zero analyzer regressions introduced.

### C. Test Suite (`flutter test`)
- **Baseline:** 91 passed, 5 failed (including `device_playback_test.dart` MissingPluginException and temporary stream network timeout).
- **Post-cleanup:** 87 automated tests passed in `test/`, 3 failed (the 3 pre-existing UI tests detailed below).
- **Key Verification:** `preview_duration_regression_test.dart` and `youtube_playback_verification_test.dart` passed 100%.

### D. Target Build (`flutter build web`)
- **Baseline:** Successfully built `build/web` in 123.7s.
- **Post-cleanup:** Successfully built `build/web` in 105.2s (`✓ Built build/web`).
- **Result:** Build is healthy and functional.

---

## 7. Remaining Pre-Existing Issues & Recommendations

The following pre-existing issues were documented during the audit and should be addressed during the upcoming Stitch UI replication phase:

1. **`now_playing_refinement_test.dart` Widget Mismatch:**
   - The test searches for `WaveformWidget`, but the implementation in `player_page.dart` uses `WaveformProgressBar`. Align the test widget finder or widget class during the player screen redesign.
2. **`search_page_widget_test.dart` Container Expectations:**
   - Test expects a specific container key for YouTube search results that changed during the recent search refactor.
3. **`unified_search_and_artist_profile_test.dart` Artist Fallback:**
   - Test expectation for Indian artist fallback image URL needs updating to match the active `ArtistDiscoveryRepository` catalog.
4. **Lint Warnings (`withOpacity` & `avoid_print`):**
   - 375 lint warnings exist (principally deprecated `withOpacity` vs `withValues` in Flutter 3.27+ and debugging `print` calls). These can be addressed incrementally during UI implementation.
5. **Disk Hygiene:**
   - `build/` (3.7 GB) and `.dart_tool/` (1.4 GB) can be cleaned with `flutter clean` whenever local disk space is needed, then regenerated on demand.
