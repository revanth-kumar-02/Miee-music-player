# Miee — Per-Track Online Playback Loading Feedback

## Overview

This document details the implementation and empirical verification of per-track loading feedback during online YouTube Music playback in Miee. 

Prior to this implementation, when a user tapped an online track in Search, Home, or Artist pages, there was no immediate visual indicator inside the tapped track's play button while the audio stream URL was being resolved and buffered. This could lead users to tap repeatedly or assume the app was unresponsive.

With this update:
1. Tapping an online track immediately renders an inline `CircularProgressIndicator` styled in Miee's signature `AppColors.dustyRose` within that specific song's play-button area.
2. Loading state is strictly tracked by track identity (`loadingTrackId`), so only the single track undergoing network resolution or buffering displays the spinner.
3. Repeated taps for an in-flight request are debounced at both the widget layer (`onPressed: null`) and controller layer (`playTrack`).
4. Selecting a different song cancels the superseded request's UI claim and updates the loading indicator immediately to the new track.
5. Local track playback continues immediately without entering the online loading indicator path.
6. Mini-player, Now Playing screen, and desktop player controls reflect actual player preparation states.
7. Playback/resolution errors clear the loading indicator and present recoverable floating SnackBar feedback with a dismiss action.

---

## Architecture & State Model

### 1. `PlaybackState` Enhancement (`lib/core/audio/playback_state.dart`)
- Added `final String? loadingTrackId;` to `PlaybackState`.
- Implemented `isSameTrackId(String? a, String? b)` helper to compare raw 11-char YouTube IDs and prefixed `youtube_` IDs seamlessly while preserving local audio IDs.
- Updated `copyWith` with `loadingTrackId` and `bool clearLoadingTrackId = false` sentinel flag to allow explicit clearing to `null`.

### 2. `PlayerController` Pipeline (`lib/core/audio/player_controller.dart`)
- **Tap Debounce**: If `state.status == PlaybackStatus.loading && state.loadingTrackId != null && isSameTrackId(state.loadingTrackId, track.id)`, subsequent taps are discarded immediately.
- **Request Inception**: In `playTrack(MusicItem track)`:
  - If `track.isYoutube`, sets `loadingTrackId: track.id` and `status: PlaybackStatus.loading`.
  - If `!track.isYoutube` (local track), sets `clearLoadingTrackId: true` to bypass online resolution loading.
- **Player Stream Integration**: In `_playerStateSub`, when the player reports `ProcessingState.ready` (mapped to `PlaybackStatus.playing` or `paused`) or `ProcessingState.completed`, `clearLoadingTrackId: true` is dispatched.
- **Error Handling**: In `_errorSub` and `playTrack` catch blocks, `clearLoadingTrackId: true` clears the spinner and surfaces `PlaybackStatus.error` with the error message.
- **Superseded Requests**: The monotonic `_playRequestToken` ensures that if Song B is tapped while Song A is resolving, Song A's late resolution returns early without clobbering Song B's active loading indicator.
- **Stop / Pause**: Calling `stop()` or `pause()` clears `loadingTrackId`.

### 3. Granular Rebuild Isolation (`YouTubeResultTile`, `SongTile`, `HomePage`)
To satisfy the performance requirement ("Avoid rebuilding the entire Search or Home screen for a single button's loading animation"):
- In `YouTubeResultTile`:
  ```dart
  final isTrackLoading = ref.watch(
    playerControllerProvider.select((s) =>
        s.loadingTrackId != null &&
        isSameTrackId(s.loadingTrackId, video.id)),
  );
  ```
  The selector produces a boolean specific to each tile. When a track starts or stops loading, only that specific tile rebuilds; all other search results evaluate `false == false` and do not rebuild.
- In `SongTile` and `_buildPopularTrackCard`:
  Tile and card rows wrap their loading checks inside individual Riverpod `Consumer` widgets, preventing whole-page rebuilds of `HomePage` or `SearchPage`.

### 4. Player Surfaces Consistency
- **`MiniPlayer` (`lib/shared/widgets/mini_player.dart`)**: Added `final bool isLoading;`. Renders an 18x18 `CircularProgressIndicator` inside the 40x40 circular play/pause FAB.
- **`PlayerPage` (`lib/features/player/presentation/player_page.dart`)**: Renders a 24x24 white `CircularProgressIndicator` inside the 58x58 circular Dusty Rose play button while loading/buffering.
- **`MainAppShell` (`lib/shared/widgets/main_app_shell.dart`)**:
  - Desktop persistent player bar renders a 18x18 white spinner in its 38x38 circular play button.
  - Desktop Now Playing drawer renders a 22x22 white spinner in its 48x48 circular play button.
  - Added a global `ref.listen` on `PlaybackStatus.error` that triggers a non-intrusive floating SnackBar with a 'Dismiss' action.

---

## Verification & Test Results

### 1. Focused Unit & Widget Test Suite (`test/online_playback_loading_test.dart`)
14 tests covering all mandatory requirements:
- `isSameTrackId handles raw and prefixed YouTube IDs correctly` (PASS)
- `PlaybackState copyWith sets and clears loadingTrackId cleanly` (PASS)
- `Selecting an online track immediately sets loadingTrackId and status` (PASS)
- `Local track does NOT enter online-resolution loading state` (PASS)
- `Rapid taps for the same in-flight track do NOT create duplicate requests` (PASS)
- `Selecting another track updates loadingTrackId immediately to new track` (PASS)
- `Stale request from earlier token cannot overwrite current track state` (PASS)
- `Playback or resolution failure clears loadingTrackId and surfaces error` (PASS)
- `Player reaching ready state clears loadingTrackId and becomes playing` (PASS)
- `Stop or pause clears loadingTrackId` (PASS)
- `Only the selected track shows CircularProgressIndicator in play button` (PASS)
- `Tapping a track in-flight does not trigger duplicate resolution` (PASS)
- `Spinner transitions to pause icon when playback begins` (PASS)
- `MiniPlayer displays spinner when isLoading is true` (PASS)

### 2. Full Regression Test Suite
Executed 60 tests across 7 test suites:
- `test/online_playback_loading_test.dart` (14/14 passed)
- `test/youtube_search_queue_test.dart` (11/11 passed)
- `test/search_artwork_playlist_fix_test.dart` (6/6 passed)
- `test/track_switching_race_condition_test.dart` (17/17 passed)
- `test/desktop_now_playing_more_menu_test.dart` (7/7 passed)
- `test/waveform_performance_test.dart` (2/2 passed)
- `test/search_page_widget_test.dart` (3/3 passed)
**Total: 60/60 tests passing (0 failures).**

### 3. Static Analysis
`flutter analyze lib/` confirmed zero compilation errors.

---

## Limitations & Edge Cases

1. **Physical Device Availability**: `adb devices` reported no physical Android hardware currently connected to the local development environment. Verification was completed via native headless test harnesses and standard debug APK compilation.
2. **Offline Streams**: If network connectivity drops mid-resolution, the YouTube client extraction will throw, cleanly terminating the spinner and surfacing the error via the floating SnackBar.
