# Miee — Now Playing UI Refinement (Issues 1, 2 & 3)

## Overview
This document details the coordinated layout and animation improvements implemented for the Miee Now Playing screen (`PlayerPage`) and the reusable `WaveformWidget`.

---

## Root Causes & Issues Addressed

### Issue 1 — Align Song Title, Artist, Like, and Overflow Buttons
* **Root Cause**: 
  - In `PlayerPage`, the action row had no explicit `crossAxisAlignment`, and the heart button (`Consumer` returning `IconButton`) and overflow button (`IconButton`) lacked symmetric, fixed-dimension container bounds (48x48), causing optical vertical misalignment against the variable height of the text column.
  - The song title was constrained to `maxLines: 1`, truncating prematurely instead of wrapping gracefully on narrow screens.
* **Fix**:
  - Encapsulated the central text elements (song title, artist, or playback error) inside a dedicated `Column` with `mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center`.
  - Configured `Row(crossAxisAlignment: CrossAxisAlignment.center)` with symmetric `SizedBox(width: 48.0, height: 48.0)` anchors for the heart and overflow buttons, ensuring mathematical horizontal centering of the `Expanded` middle block.
  - Allowed long song titles to wrap up to 2 lines (`maxLines: 2, overflow: TextOverflow.ellipsis`), followed by `AppSpacing.heightXs` (4.0) vertical separation to the artist line (`maxLines: 1`).
  - Added safe horizontal padding (`AppSpacing.sm`) so long titles never collide with action buttons.

### Issue 2 — Waveform Width and Timer Alignment
* **Root Cause**:
  - In `WaveformWidget`, `_WaveformPainter` and `_handleScrub` previously hardcoded `maxBarWidth = 4.0` with 28 bars and 3.0px gaps, capping the visual width to exactly `28 * 4 + 27 * 3 = 193.0px`.
  - In `PlayerPage`, `WaveformWidget` was enclosed in `Container(constraints: BoxConstraints(maxWidth: 320.0), padding: EdgeInsets.symmetric(horizontal: 16.0))`, while the elapsed/total duration `Row` was outside that container, stretching across the entire screen width (e.g. 352px - 392px). This created a tiny waveform cluster in the middle with disconnected timer labels pushed far to the edges.
* **Fix**:
  - Placed both `WaveformWidget` and the duration `Row` inside the same `ConstrainedBox(constraints: BoxConstraints(maxWidth: 480.0))` container in `PlayerPage`.
  - Updated `WaveformWidget` and `_WaveformPainter` to dynamically scale across `effectiveWidth = min(width, 480.0)`.
  - Proportional bar sizing: `slotWidth = effectiveWidth / barCount`, `barWidth = (slotWidth * 0.52).clamp(3.0, 7.5)`, and `gap = (effectiveWidth - barCount * barWidth) / (barCount - 1)`.
  - The first bar starts at `x = startX` and the 28th bar ends at `x = startX + effectiveWidth`, exactly matching the start of the elapsed timer and the end of the total duration label.
  - Scrubbing accurately maps `(localX - startX) / effectiveWidth` clamped to `[0.0, 1.0]`.

### Issue 3 — Slow Down Waveform Animation
* **Root Cause**:
  - `_WaveformWidgetState` used an `AnimationController` with a duration of `1200ms`. In conjunction with `sin(phase).abs()`, each bar oscillated twice per cycle (every 600ms), resulting in a frantic, visually distracting flutter.
* **Fix**:
  - Adjusted the `AnimationController` duration from `1200ms` to `2400ms`, reducing perceived animation speed by 50%.
  - Preserved the existing 28-element `_baseHeights` amplitude distribution and capsule pill styling (`Radius.circular(barWidth / 2.0)`).
  - Maintained pure canvas repaints via `_WaveformPainter(repaint: animation)` without unnecessary widget tree rebuilds.
  - Maintained lifecycle management (`repeat()` when `isPlaying`, `stop()` when paused, and proper `dispose()`).

---

## Files Changed

1. `lib/features/player/presentation/player_page.dart`
   - Refined song info row with centered 48x48 action buttons, 2-line title wrapping, and ellipsis.
   - Unified `WaveformWidget` and duration timer `Row` inside a responsive `ConstrainedBox(maxWidth: 480.0)`.
2. `lib/shared/widgets/waveform_widget.dart`
   - Slowed animation duration to `2400ms`.
   - Replaced fixed 193px width clamp with responsive proportional bar and gap calculation.
   - Synchronized touch coordinates in `_handleScrub` with the painter geometry.
3. `test/now_playing_refinement_test.dart`
   - Created comprehensive automated test suite verifying layout, alignment, wrapping, timer bounds, scrubbing, and animation timing.

---

## Verification & Test Results

### Automated Tests (`flutter test test/now_playing_refinement_test.dart`)
```
00:00 +0: Issue 1: Title, Artist, Heart and Overflow Buttons Alignment renders song title and artist with maxLines 2 and proper alignment
00:01 +1: Issue 1: Title, Artist, Heart and Overflow Buttons Alignment long song title wraps to 2 lines without throwing overflow errors
00:01 +2: Issue 1: Title, Artist, Heart and Overflow Buttons Alignment heart button and overflow button are independently clickable
00:02 +3: Issue 2: Waveform Width and Timer Alignment waveform widget fills available container width and matches timer boundary
00:02 +4: Issue 2: Waveform Width and Timer Alignment waveform scrubbing calculates correct seek position across width
00:02 +5: Issue 3: Waveform Animation Speed & Lifecycle animation controller duration is 2400ms (50% speed)
00:02 +6: All tests passed!
```

### Static Analysis
`flutter analyze lib/features/player lib/shared/widgets/waveform_widget.dart test/now_playing_refinement_test.dart`
- **Result: No issues found!**

### Regression Tests
- `test/widget_test.dart`: Passed.
- `test/lana_test.dart`: Passed.
- `test/youtube_playback_verification_test.dart`: Passed (all 4 stream resolution and cache tests passed).
