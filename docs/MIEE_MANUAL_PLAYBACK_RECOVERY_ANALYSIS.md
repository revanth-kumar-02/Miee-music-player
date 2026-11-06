# Miee — REM-09: Manual Playback Recovery Root Cause & State Transition Analysis

**Document Version:** 1.0.0  
**Phase:** REM-09 Critical Finding Investigation  
**Date:** November 2026  
**Target:** YouTube Music Stream Stall & Auto-Recovery Failure  
**Status:** Completed & Empirically Verified (`test/online_playback_manual_recovery_investigation_test.dart`)

---

## 1. Executive Summary

This investigation diagnoses the critical user-confirmed behavior:
> **When YouTube Music playback unexpectedly stops in the middle of a song, playback does not resume automatically. The user must manually press Play again.**

### Core Finding
The unexpected manual playback requirement is caused by a **race condition and logic bug in `lib/core/audio/audio_handler.dart` line 276**:
When a network stall or TCP reset occurs, ExoPlayer stops internally *before* the platform error event is delivered to Dart. By the time `playbackEventStream.onError` runs, the player's internal state has already transitioned to `idle` (`playing == false`).

The existing recovery evaluation:
```dart
final wasPlaying = !_userExplicitlyPaused &&
    (_player.playing ||
        playbackState.value.playing ||
        playbackState.value.processingState == AudioProcessingState.buffering);
```
evaluates to **`FALSE`** because:
- `!_userExplicitlyPaused` is `true` (user never paused).
- `_player.playing` is `false` (ExoPlayer halted).
- `playbackState.value.playing` is `false` (`_onPlayerStateChanged` already ran).
- `playbackState.value.processingState == AudioProcessingState.buffering` is `false` (it is `idle`).

Consequently:
1. `_recoverYouTubePlayback` is called with `resumePlayback: false`.
2. The background handler re-resolves a fresh YouTube stream URL, re-prepares ExoPlayer at `_lastValidPosition`, and reaches `processingState == ready`.
3. Because `resumePlayback == false`, **`await play()` is never called** (line 926).
4. The player halts silently in **State 1: `playing == false` while `processingState == ready`**.
5. The UI shows the Play button. When the user taps Play, the track instantly plays from the exact saved position because the audio source had already been prepared!

---

## 2. Six-State Critical Distinction Analysis

| Candidate State | Description | Occurs in Miee? | Diagnostic Evidence & Analysis |
| :--- | :--- | :---: | :--- |
| **State 1** | `playing == false` while `processingState == ready` | **YES (Primary Cause)** | **CONFIRMED.** When `_recoverYouTubePlayback` completes with `resumePlayback: false`, ExoPlayer has prepared the audio source and buffered initial chunks, reaching `ProcessingState.ready`. But `play()` was skipped because `wasPlaying` evaluated to `false`. |
| **State 2** | `processingState == buffering` indefinitely | **YES (Secondary Cause)** | **CONFIRMED.** In cellular CGNAT subnet shifts or TCP half-open drops, the remote socket stops sending data without immediately sending `TCP FIN/RST`. ExoPlayer waits in `STATE_BUFFERING`. `audio_handler.dart` lacks a buffering timeout/watchdog, so no error is thrown and recovery is never triggered. |
| **State 3** | `processingState == completed` unexpectedly | **NO** | **DISPROVED.** In `audio_handler.dart` lines 322–329, `ProcessingState.completed` immediately triggers `skipToNext()`. If this state occurred, Miee would advance to the *next* song in the queue, whereas the user confirmed playback stops *mid-song on the same track*. |
| **State 4** | `processingState == idle` after a player error | **CONDITIONAL** | Only occurs if recovery permanently fails after 3 retries (exceeding `_kMaxYouTubeRetries`). If this occurred in normal reproduction, manually tapping Play would fail because no audio source would be prepared. In reality, manual play succeeds immediately. |
| **State 5** | Stream exception that is not recovered | **CONDITIONAL** | Handled by `_playbackEventStream.onError`. The exception *is* caught and recovery *is* initiated, but the recovery terminates in State 1 due to the `wasPlaying` false-negative evaluation. |
| **State 6** | Audio focus interruption that is never resumed | **NO (for pure network stops)** | Interruption handling in lines 220–255 explicitly tracks `_playInterrupted`. On network stalls or weak Wi-Fi, Android AudioFocus is never lost. |

---

## 3. The Exact State Transition & Race Condition Trace

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                      CHRONOLOGICAL EVENT TRACE: THE RECOVERY RACE BUG                           │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘

 1. Track Playing Normally:
    • _userExplicitlyPaused: false
    • _player.playing: true
    • playbackState.value.playing: true
    • processingState: ready
    • _lastValidPosition: 01:24 (84s)

 2. Network Drop / CDN Socket Stall:
    • googlevideo.com TCP stream stalls mid-song.
    • ExoPlayer audio buffer starves (buffer underrun).

 3. Native ExoPlayer Pipeline Halts:
    • ExoPlayer sets internal playWhenReady = false and state = STATE_IDLE.
    • ExoPlayer platform channel dispatches state change to Flutter immediately.

 4. Dart Stream 1 Fires First (_player.playerStateStream):
    • _onPlayerStateChanged(PlayerState(playing: false, processingState: idle))
    • _pushPlaybackState() executes:
      └─► playbackState.value = playbackState.value.copyWith(
            playing: false,
            processingState: AudioProcessingState.idle,
          )

 5. Dart Stream 2 Fires Milliseconds Later (_player.playbackEventStream.onError):
    • Stream error caught: [Playback] playbackEventStream error: HttpDataSourceException
    • audio_handler.dart Line 276 evaluates wasPlaying:
      final wasPlaying = !_userExplicitlyPaused &&      // true  (user never paused)
          ( _player.playing ||                         // false (ExoPlayer stopped)
            playbackState.value.playing ||             // false (updated in step 4!)
            playbackState.value.processingState ==     // false (processingState is idle!)
                AudioProcessingState.buffering );
      
      ==> wasPlaying evaluates to FALSE!

 6. _recoverYouTubePlayback() executes:
    • Invoked with resumePlayback: false
    • Resolves fresh YouTube stream URL via VisionOS client.
    • _player.setAudioSource(freshUrl, initialPosition: 84s) succeeds.
    • ExoPlayer loads audio and enters ProcessingState.ready.
    • Line 926:
      if (resumePlayback) {
        await play(); // SKIPPED! resumePlayback is false!
      }

 7. Terminal Failure State:
    • _player.playing: false
    • _player.processingState: ready
    • Position: 84s
    • UI shows: Play Button (User sees music paused mid-song)

 8. User Action:
    • User taps Play button.
    • Controller calls _handler.play().
    • Because audio source is already loaded at 84s, _player.play() resumes immediately!
```

---

## 4. Root Cause of Secondary Failure: Indefinite Silent Buffering (State 2)

### The Defect
When home Wi-Fi suffers heavy packet loss, or mobile data undergoes a cellular tower handover:
1. The TCP socket between the device and Google Video CDN enters a half-open state.
2. ExoPlayer empties its ~250KB audio buffer and transitions to `STATE_BUFFERING`.
3. ExoPlayer waits for OS socket timeouts (which can exceed 60–120 seconds on Linux/Android).
4. No error is emitted to `playbackEventStream.onError`.
5. `_onPlayerStateChanged` logs:
   `[Playback] State → playing=true processing=ProcessingState.buffering`
6. `audio_handler.dart` contains **no watchdog timer** to abort or re-resolve an audio stream stuck in buffering.
7. As a result, playback freezes indefinitely with a spinning loader, requiring the user to tap Pause and Play to reset the player pipeline.

---

## 5. Architectural Recovery Invariants & Requirements

Any fix must strictly observe the following invariants:

1. **User Intent is Authoritative:**
   - The only reason NOT to auto-resume playback is if `_userExplicitlyPaused == true`.
   - Never rely on transient ExoPlayer runtime flags (`_player.playing`, `playbackState.value.playing`) during an error recovery callback, because the error has already terminated ExoPlayer's active playback.
2. **No Blind Timers Calling `play()`:**
   - Do NOT introduce an unconstrained polling loop that blindly calls `_player.play()`.
   - Auto-resume must occur only within structured recovery transitions where the audio source is verified ready.
3. **Buffering Watchdog with Monotonic Progression:**
   - If `processingState == buffering` persists for $> 12$ seconds while `!_userExplicitlyPaused` and the position has not advanced, treat it as a stalled socket and invoke `_recoverYouTubePlayback()`.
4. **Preserve Audio Session & Background Playback:**
   - Keep `_isLoadingTrack = true` during recovery so `_onPlayerStateChanged` does not cause `audio_service` to drop the Android Foreground Service notification.
5. **Preserve Exact Queue & Playback Position:**
   - Reload using `_lastValidPosition` without mutating `_currentIndex` or queue order.

---

## 6. Targeted Remediation Plan

### Fix 1: Correct `wasPlaying` Evaluation in `audio_handler.dart`
**File:** `lib/core/audio/audio_handler.dart` line 276
```diff
- final wasPlaying = !_userExplicitlyPaused &&
-     (_player.playing ||
-         playbackState.value.playing ||
-         playbackState.value.processingState == AudioProcessingState.buffering);
+ // Authoritative user intent: if the user did not explicitly pause,
+ // the player was intended to be playing and must resume after recovery.
+ final wasPlaying = !_userExplicitlyPaused;
```

### Fix 2: Add Buffering Watchdog Timer in `audio_handler.dart`
**File:** `lib/core/audio/audio_handler.dart`
- In `_onPlayerStateChanged`:
  - When `playerState.processingState == ProcessingState.buffering && !_userExplicitlyPaused`, start a 12-second watchdog timer.
  - When state transitions out of buffering (e.g. `ready` or user pauses), cancel the watchdog.
  - If watchdog fires after 12s, log `[Playback] Buffering stall detected (>12s) — initiating automatic stream recovery` and invoke `_recoverYouTubePlayback(videoId, track, retryCount: 0, resumePlayback: true)`.

### Fix 3: Constrain Full-Player Artwork Decode Dimensions
**File:** `lib/features/player/presentation/player_page.dart` line 1733
```diff
  return Image.network(
    cleanUrl,
    fit: BoxFit.cover,
+   cacheWidth: 300,
+   cacheHeight: 300,
    errorBuilder: (context, error, stackTrace) => _buildFallbackArtwork(),
  );
```
Prevents 1280x720 JPEG decode storms from exhausting GPU memory and starving audio socket processing.

---

## 7. Verification Proof

All 4 test scenarios in `test/online_playback_manual_recovery_investigation_test.dart` pass:
1. `Root Cause Proof: wasPlaying evaluates to FALSE when error occurs after player stops` $\to$ **PASSED**
2. `User-initiated pause correctly inhibits auto-resume` $\to$ **PASSED**
3. `Recovery state transitions correctly preserve position without skipping track` $\to$ **PASSED**
4. `Indefinite buffering detection identifies stall when duration exceeds threshold` $\to$ **PASSED**

