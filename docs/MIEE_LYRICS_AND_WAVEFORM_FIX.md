# Miee — Lyrics UI Cleanup, Waveform Performance, and Lyric Synchronization

This document records the analysis, root cause diagnosis, architectural solutions, and verification evidence for the three fixes implemented in Miee.

---

## Issue 1 — Remove Unwanted Horizontal Line Beneath Lyrics Header

### 1. Root Cause
In `lib/features/lyrics/presentation/widgets/lyrics_overlay.dart`, inside the modal bottom sheet layout, a `const Divider(height: 1)` was statically rendered immediately following the top header row (`LYRICS` text and close `IconButton`). This created an unwanted horizontal cut across the glassmorphic dark container.

### 2. Changes Made
- **File**: `lib/features/lyrics/presentation/widgets/lyrics_overlay.dart`
- Removed the `const Divider(height: 1)` from below the header.
- Preserved the `LYRICS` label, close button (`onClose`), margin/padding tokens (`AppSpacing.marginMobile`, `AppSpacing.sm`), and backdrop blur.
- Ensured dividers on unrelated screens (such as settings and library) remained untouched.

---

## Issue 2 — Fix Waveform Animation Lag in Expanded Now Playing

### 1. Root Causes
1. **Unbounded Parent Rebuilds on Playback Position Ticks:**
   In `lib/features/player/presentation/player_page.dart`, the top-level `PlayerPage.build()` was watching the entire state via `ref.watch(playerControllerProvider)`. Because the audio handler and `PlayerController` stream position updates at ~10–20 Hz (every 50–100ms), the entire 480-line `PlayerPage` widget tree—including complex album artwork drop-shadows, responsive layouts, action buttons, and hero widgets—was rebuilding on every playback tick.
2. **Paint Layer Invalidation:**
   `WaveformWidget`'s `CustomPaint` did not have a `RepaintBoundary`. As a result, the 60–120 FPS sine-wave oscillation animation invalidated and redrew parent layers continuously.
3. **Repeated Per-Frame Allocations in Painter:**
   `_WaveformPainter.paint()` was allocating 32 `Paint` objects, 32 `Radius` instances, and recomputing mathematical offsets inside the bar loop on every animation frame.

### 2. Changes Made
- **File**: `lib/shared/widgets/waveform_widget.dart`
  - Wrapped `CustomPaint` inside a `RepaintBoundary` to prevent visual repaint propagation up the render tree.
  - Optimized `_WaveformPainter`:
    - Reused pre-allocated `activePaint` and `inactivePaint` instances.
    - Cached `Radius.circular(cornerRadius)` outside the 32-bar loop.
    - Pre-computed phase bases and math terms outside the iteration.
- **File**: `lib/features/player/presentation/player_page.dart`
  - Replaced broad `ref.watch(playerControllerProvider)` with fine-grained selectors:
    - `currentTrack`: `playerControllerProvider.select((s) => s.currentTrack)`
    - `isPlaying`: `playerControllerProvider.select((s) => s.status == PlaybackStatus.playing)`
    - `isShuffleEnabled`: `playerControllerProvider.select((s) => s.isShuffleEnabled)`
    - `repeatMode`: `playerControllerProvider.select((s) => s.repeatMode)`
    - `playingFrom`: `playerControllerProvider.select((s) => s.playingFrom)`
  - Extracted waveform progress and elapsed/total duration labels into an isolated consumer component: `_WaveformProgressSection`.
  - Position stream updates now only trigger rebuilds of `_WaveformProgressSection` without dirtying or rebuilding the main `PlayerPage`.
  - Scrubbing, seeking, elapsed time, duration, and pause/resume states remain accurately synchronized with `PlayerController.seek()`.

---

## Issue 3 — Synchronize Lyrics with the Currently Playing Line

### 1. Root Causes
1. **Artificial Interpolation on Plain Lyrics:**
   The previous lyrics loader contained fallback logic that divided total track duration evenly across plain lyrics lines (`stepSec = totalSec / (lines.length + 1)`). When LRCLIB returned plain text (or when synced lyrics were unavailable), the app assigned fake timestamps, causing the highlighted active line to wander erratically and out of sync with singing.
2. **Lack of Lyric Sync Type Distinction:**
   The UI had no way to distinguish whether a lyric set was authentically synchronized (`.lrc` timestamps) or unsynchronized plain text.
3. **Stale Lyrics Retained Across Track Changes:**
   `LyricsOverlay` took `widget.track` at sheet creation. If the user skipped tracks or auto-play advanced to the next song, the overlay failed to clear its internal line index.

### 2. Changes Made
- **File**: `lib/features/lyrics/domain/lyrics_model.dart`
  - Added `LyricsData` container implementing `IterableMixin<LyricLine>`:
    - `lines`: List of parsed `LyricLine`s.
    - `isSynced`: Boolean flag explicitly indicating whether lines carry authentic timestamps.
    - `source`: Provenance tag (`local_lrc`, `lrclib_synced`, `lrclib_search_synced`, `plain_fallback`).
- **File**: `lib/features/lyrics/providers/lyrics_providers.dart`
  - Prioritizes authentic `.lrc` files on local storage.
  - Queries LRCLIB `/api/get` with track title, artist, and duration for exact synced matches.
  - Falls back to LRCLIB `/api/search` specifically checking candidate items for `syncedLyrics`.
  - If only plain lyrics exist, loads them with `isSynced: false` and `Duration.zero` timestamps. **Never fabricates artificial timestamps.**
- **File**: `lib/features/lyrics/presentation/widgets/lyrics_overlay.dart`
  - Watches active playback track from `playerControllerProvider.select((s) => s.currentTrack)`. Resets `_currentLineIndex = -1` when `activeTrack.id` changes, immediately discarding stale state.
  - Synchronizes active line highlighting strictly against the real audio player clock (`playerControllerProvider.select((s) => s.position)`).
  - Tapping a line triggers `playerController.seek(line.time)` when `isSynced` is true.
  - When `isSynced` is false:
    - Displays a subtle `"Unsynchronized lyrics"` badge.
    - Disables tap-to-seek and auto-scroll jumps.
    - Renders readable plain text cleanly.

---

## Verification & Test Results

### 1. Automated Tests
1. **`test/lyrics_sync_test.dart`** (Passed):
   - Position before first lyric timestamp returns -1 (no active line prematurely).
   - Exact timestamp match highlights appropriate line.
   - Position between timestamps keeps active line steady.
   - Seeking backwards jumps active line backwards immediately.
   - Plain lyrics fallback does not invent artificial line durations (`isSynced: false`, `Duration.zero`).
   - Verifies `Divider` is removed from `LyricsOverlay` while `LYRICS` header and close icon are intact.
   - Unsynchronized lyrics render badge without crash.
2. **`test/waveform_performance_test.dart`** (Passed):
   - Confirms `WaveformWidget` wraps `CustomPaint` in `RepaintBoundary`.
   - Scrubbing across waveform fires `onScrub` callback with bounded double values (0.0 to 1.0).
   - Toggling `isPlaying` starts and stops animation cleanly without errors or memory leaks.
   - Bounded values handling (-0.5 to 1.5 clamped).
3. **`test/lyrics_and_queue_persistence_test.dart`** (Passed):
   - Full `.lrc` parser verification.
   - Null track handling.
   - LRCLIB live network resolution.
   - Queue state serialization and restore.

### 2. Static Analysis
- `flutter analyze lib/`: 0 errors.

### 3. Architecture Constraints Preserved
- No secondary audio player introduced.
- `just_audio`, `audio_service`, and `PlayerController` architecture maintained.
- YouTube audio resolver and background playback untouched.
- Firebase, auth, and onboarding untouched.
- No automatic git commit performed.
