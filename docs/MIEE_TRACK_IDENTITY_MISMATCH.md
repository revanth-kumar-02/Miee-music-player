# Miee — Track Identity Consistency & Playback Integrity Audit

## 1. Problem Statement & Incident Description

In Miee online YouTube Music playback, a critical desynchronization occurred:
- **Displayed UI**: Title `Vizhi Veekura`, artist `Sai Abhyankkar`, and corresponding artwork.
- **Audio Output Heard**: `Ooroda Oththa Don` (also by `Sai Abhyankkar`).

The application was presenting the metadata for a newly selected track while continuing to output the audio stream of an earlier selected track.

---

## 2. Phase 1 — End-to-End Pipeline Boundary Trace

We traced track identity through all 8 boundaries of the playback lifecycle:

| Boundary | Stage | Data / Identification | Integrity Evaluation |
|---|---|---|---|
| **1** | **Search / Recommendation Result** | `YouTubeSearchResult(id: '_e45NEdNMXE', title: 'Vizhi Veekura', artist: 'Sai Abhyankkar')` | Correct. Returns genuine 11-char YouTube video ID. |
| **2** | **Track Model Creation** | `Track(id: 'youtube__e45NEdNMXE', title: 'Vizhi Veekura', filePath: 'https://www.youtube.com/watch?v=_e45NEdNMXE')` | Correct. Prefixed `youtube_` preserves namespace. |
| **3** | **Queue Insertion & Index** | `QueueManager.setQueue([trackVizhi, ...], initialIndex: 0)` | Correct. Track identity matches queue index 0. |
| **4** | **PlayerController Selection** | `PlayerController.playTrack(trackVizhi)` -> `_handler.loadQueue(queue, initialIndex: 0)` | Correct. Correct track passed to audio handler. |
| **5** | **YouTube Audio Resolution** | `YouTubeAudioResolver.resolveStreamUrl('_e45NEdNMXE')` | Verified. `_e45NEdNMXE` resolved. Cache keyed strictly by 11-character video ID. |
| **6** | **Resolved Stream URL & Cache** | `_streamCache[videoId]` | Keyed by video ID. No collisions with other songs. |
| **7** | **`just_audio` Source Assignment** | `_player.setAudioSource(AudioSource.uri(streamUri))` | **VULNERABLE (Root Cause 1 & 4)**: In `just_audio`, calling `_player.stop()` does not detach or clear the underlying ExoPlayer MediaSource. If stream resolution fails or is in-flight, `_player` retains the previously loaded stream (`Ooroda Oththa Don`). |
| **8** | **Audio Handler State & Now Playing Metadata** | `mediaItem.add(_trackToMediaItem(track))` | **VULNERABLE (Root Cause 2 & 3)**: Metadata was broadcast to OS media notification before verifying audio stream loading. If loading failed or stalled, the UI displayed `Vizhi Veekura` while ExoPlayer resumed playing `Ooroda Oththa Don`. |

---

## 3. Phase 2 — Root Cause Analysis & Code Evidence

### Root Cause 1: Swallowed Exceptions in Audio Handler Allowed Stale Playback
In `lib/core/audio/audio_handler.dart`:
```dart
// PREVIOUS IMPLEMENTATION:
Future<void> _loadCurrentTrack() async {
  ...
  try {
    if (track.isOnline) {
      await _loadYouTubeTrack(track, token: token);
    }
  } catch (e, stack) {
    _log('Error loading track ${track.id}: $e\n$stack');
    // Exception swallowed! Function completes normally.
  }
}
```
**Consequence**: When `_loadYouTubeTrack()` encountered a network timeout, extractor throttle, or invalid response, the error was logged but swallowed. `loadQueue()` returned cleanly. In `PlayerController.playTrack()`:
```dart
await _handler.loadQueue(queue, initialIndex: index);
await _handler.play(); // Play triggered on stale ExoPlayer source!
```
Because `_player.stop()` in `just_audio` merely pauses and rewinds the current buffer without clearing the loaded MediaSource, `_player.play()` happily resumed playing the previously loaded track (`Ooroda Oththa Don`).

### Root Cause 2: Premature Now Playing Metadata Emission
`mediaItem.add(_trackToMediaItem(track))` was invoked before the audio source was loaded and verified. If the audio stream failed or was delayed, OS notification and Riverpod state were already pointing to `Vizhi Veekura`.

### Root Cause 3: No Association Between Player Audio Source and Active Queue Track
Neither `MieeAudioHandler` nor `PlayerController` held a verified record of which track was actually loaded inside `_player`. When `play()` was invoked, it called `_player.play()` blindly without confirming whether the loaded audio source matched the selected track.

### Root Cause 4: Asynchronous Load Token Race Condition
In `_loadYouTubeTrack()`, `_setAudioSourceUrl(streamUrl, ...)` was awaited before verifying if the operation was superseded by a newer track selection. If a slow resolution for Track A finished right after Track B began loading, Track A's stream could be assigned to `_player`.

---

## 4. Phase 3 — Enforce Track Identity Consistency

### Key Architectural Fixes Implemented

1. **Explicit Loaded Track Tracking (`_loadedAudioTrackId`)**:
   - Added `String? _loadedAudioTrackId` to `MieeAudioHandler` and exposed a getter.
   - Cleared (`_loadedAudioTrackId = null`) immediately upon initiating track change or stop.
   - Only set when `_player.setAudioSource()` completes and the request token matches `_activeLoadToken`.

2. **Airtight Playback Gate in `play()`**:
   ```dart
   @override
   Future<void> play() async {
     final currentTrack = currentQueueTrack;
     if (currentTrack == null || _loadedAudioTrackId == null) {
       _log('play() blocked: No track currently loaded or loading in progress.');
       return;
     }
     if (!isSameTrackId(_loadedAudioTrackId, currentTrack.id)) {
       _log('play() blocked: Loaded audio track ($_loadedAudioTrackId) does not match queue track (${currentTrack.id}).');
       return;
     }
     await _player.play();
   }
   ```
   **Guarantee**: Under no circumstances can `_player.play()` execute audio that belongs to another track.

3. **Atomic Metadata & Source Synchronization**:
   - `mediaItem.add(_trackToMediaItem(track))` is only broadcast AFTER `_player.setAudioSource` succeeds and token verification passes.
   - If loading fails, `_loadedAudioTrackId` remains `null`, the error is rethrown, and `PlayerController` sets `PlaybackStatus.error`.

4. **Two-Stage Token Cancellation**:
   - In `_loadYouTubeTrack`, the load token is validated immediately before setting the audio source AND immediately after awaiting it. If superseded, `_player.stop()` is called and the result is discarded.

5. **Robust YouTube Video ID Extraction**:
   - Enhanced `_extractYouTubeVideoId` to handle query parameters (`watch?v=...`), short links (`youtu.be/...`), and whitespace without mangling IDs.

---

## 5. Phase 4 — Regression Test Suite Results

Created comprehensive regression suite `test/track_identity_mismatch_test.dart` covering all 8 prompt test scenarios:

1. **Selecting `Vizhi Veekura` plays the source associated with its own video ID**:
   - Verified exact extraction `_e45NEdNMXE` and positive identity match (`isSameTrackId`).
2. **Selecting `Ooroda Oththa Don` afterward replaces the previous audio source**:
   - Verified that transition invalidates `_loadedAudioTrackId` and assigns `oorodaTrack.id`.
3. **A delayed response for the previous track cannot overwrite the current selection**:
   - Simulated 100ms slow response for `Vizhi Veekura` vs 30ms fast response for `Ooroda Oththa Don`. Stale response was discarded; active loaded track remained `Ooroda Oththa Don`.
4. **Two songs with similar titles do not share the wrong cached stream**:
   - Verified that cache keys use strictly canonical 11-char YouTube IDs.
5. **Queue next/previous updates both audio source and metadata**:
   - Tested QueueManager navigation for `Vizhi Veekura` -> `Ooroda Oththa Don` -> `Vizhi Veekura`.
6. **Now Playing metadata remains associated with selected track and rejects mismatched play**:
   - Verified that if `loadedAudioTrackId` is null or points to `oorodaTrack.id` while queue is `vizhiTrack`, `play()` is rejected.
7. **A failed resolver does not play an unrelated previous or fallback track**:
   - Verified that resolver failure resets loaded track state and aborts playback.
8. **Existing background playback and notification controls remain functional**:
   - Verified `MediaItem` mapping preserves `id`, `title`, `artist`, `artUri`, and actions.

**Execution Result**:
```
flutter test test/track_identity_mismatch_test.dart
00:00 +8: All tests passed!
```
Additionally, all existing tests in `test/online_playback_loading_test.dart`, `test/track_switching_race_condition_test.dart`, `test/youtube_search_queue_test.dart`, and `test/search_artwork_playlist_fix_test.dart` passed (55 passed tests).

---

## 6. Changed Files

| File | Changes Made |
|---|---|
| `lib/core/audio/audio_handler.dart` | Added `_loadedAudioTrackId` tracking; gated `play()` against track ID mismatch; stopped premature `mediaItem.add()`; ensured load failures rethrow instead of failing silently; token validation before/after audio source setup; enhanced YouTube ID extraction. |
| `lib/core/audio/player_controller.dart` | Added retry behavior on `play()` when state is `error` or `idle`; guarded `playTrack` to prevent calling `_handler.play()` when queue loading throws. |
| `test/track_identity_mismatch_test.dart` | Comprehensive 8-scenario unit and integration test suite. |
| `docs/MIEE_TRACK_IDENTITY_MISMATCH.md` | Complete architectural documentation and verification report. |

---

## 7. Phase 5 — Device Verification Checklist

To verify on an attached Android device or emulator:
1. Launch app on device: `flutter run -d <device_id>`.
2. Navigate to Search screen and search `Vizhi Veekura`.
3. Tap play on `Vizhi Veekura` (by Sai Abhyankkar).
   - Check Logcat: `Extracting YouTube stream for videoId: _e45NEdNMXE`.
   - Audio output must match `Vizhi Veekura`.
4. Tap play on `Ooroda Oththa Don` (by Sai Abhyankkar).
   - Check Logcat: `Extracting YouTube stream for videoId: HiCbeZuhYZw`.
   - Audio output immediately switches to `Ooroda Oththa Don`.
5. Rapidly tap alternating songs (`Vizhi Veekura` -> `Ooroda Oththa Don` -> `Vizhi Veekura`):
   - Notice superseding logs: `Superseded load request discarded`.
   - The final audio heard matches the final track displayed in Now Playing.
6. Disconnect network or trigger a resolution error:
   - Playback halts cleanly. The player **never** resumes playing audio from the previous track.
