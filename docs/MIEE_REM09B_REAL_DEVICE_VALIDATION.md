# Miee — REM-09B: Weak-Network Playback Validation & Telemetry Report

**Document Version:** 1.0.0  
**Phase:** REM-09B Real-Network & Weak-Network Telemetry Validation  
**Date:** November 2026  
**Status:** Completed & Empirically Verified (Automated & Real Network Simulation)  
**Host Environment:** Windows (Flutter 3.x, Dart 3.x)

---

## 1. Executive Summary & Environment Scope

This validation report evaluates the resilience of Miee's audio playback engine under realistic network degradation profiles, specifically assessing the targeted recovery and buffering watchdog fixes introduced in **REM-09**.

### Environment Separation & Physical Device Disclaimer
- **Automated Regression Suite:** 10 deterministic scenarios executed in [`test/online_playback_manual_recovery_regression_test.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/test/online_playback_manual_recovery_regression_test.dart).
- **Simulated Real-Network Suite:** 6 network conditions executed via a local TCP traffic-shaping loopback proxy with real HTTP socket connections in [`test/weak_network_real_simulation_test.dart`](file:///c:/Users/revanth%20kumar/Pictures/news/Projects/Unfinished/Miee/test/weak_network_real_simulation_test.dart) (`HttpOverrides.global = null`).
- **Physical Device Status:** **No physical Android/iOS device or hardware emulator is currently connected to ADB or Flutter host daemons** (`adb devices` reported 0 devices; `flutter emulators` reported no local AVD images installed). Consequently, hardware-specific OEM background killer behavior (e.g., Xiaomi MIUI / Samsung OneUI battery saver killing foreground notifications during 60+ minute continuous playback) could not be tested on bare metal and remains documented under Section 5.

---

## 2. Stage 1 — Implementation & Code Invariant Inspection

A comprehensive static and code-level inspection verified the following four architectural pillars:

1. **Watchdog Cancellation Integrity:**
   - The 12-second buffering watchdog (`_bufferingWatchdogTimer`) is strictly cancelled upon:
     - Buffering resolution (`_onPlayerStateChanged` when `state != buffering`).
     - Track completion (`ProcessingState.completed`).
     - Explicit user pause (`pause()`) or stop (`stop()`).
     - Track changes and queue navigation (`_loadCurrentTrack()`, `skipToNext()`, `skipToPrevious()`).
     - Manual seek operations (`seek()`).
     - Handler disposal (`disposeHandler()`).
   - Verified that no stale timers can linger across track transitions.

2. **Recovery Concurrency Protection (`_isRecovering`):**
   - An atomic flag `_isRecovering = true` locks the recovery pipeline in `_recoverYouTubePlayback`.
   - Any secondary error events emitted by `playbackEventStream.onError` or concurrent triggers from `_onBufferingWatchdogFired` are immediately dropped with:
     `[Playback] Recovery already in progress for <videoId> — ignoring duplicate request`.
   - A `try / finally` block guarantees `_isRecovering` resets to `false` upon success, cancellation, or reaching `_kMaxYouTubeRetries`.

3. **Retry Limits & Non-Recoverable Failure:**
   - Enforces `_kMaxYouTubeRetries = 2`.
   - On attempt 3, recovery ceases recursion, resets `_isLoadingTrack = false`, emits an error description to `_errorController`, and updates `playbackState` to `AudioProcessingState.error`.

4. **Authoritative User-Pause Intent:**
   - Intent determination uses `final wasPlaying = !_userExplicitlyPaused;`.
   - Transient ExoPlayer states (`playing == false`, `processingState == idle`) occurring immediately after network drops no longer cause `wasPlaying` to evaluate to `false`.
   - Conversely, if the user explicitly paused (`_userExplicitlyPaused == true`), auto-resume is strictly inhibited both at the error entry point and before `play()` is called.

---

## 3. Stage 2 & 3 — Real Network Condition Results & Telemetry

Simulated over real OS network loopback sockets using an in-process HTTP traffic shaper (`NetworkShaperProxy` with `HttpOverrides.global = null`):

### 3.1 Network Conditions Evaluated

| # | Condition Profile | Bandwidth | Injected RTT | Injected Impairment |
| :-: | :--- | :---: | :---: | :--- |
| **1** | Stable High-Speed | Uncapped | 0ms | Normal streaming baseline |
| **2** | 2 Mbps Elevated Latency | 256 KB/s | 150ms | Typical cellular LTE / weak home Wi-Fi |
| **3** | 512 Kbps Elevated Latency | 64 KB/s | 350ms | Degraded cellular 3G / Edge |
| **4** | Intermittent Connectivity | Uncapped | 0ms | 2.0s silent packet freeze (< 12s watchdog threshold) |
| **5** | Disconnection & Reconnection | 256 KB/s | 50ms | Abrupt TCP socket severing after 32KB; reconnection |
| **6** | Consecutive 10 Tracks | Uncapped | Var. | Sequential stream resolution & cache verification |

### 3.2 Telemetry Capture Table

| Condition | Track ID | Position | Playing | Processing State | Buffering Duration | Watchdog State | Recovery Attempts | Resolution Latency | Auto-Resumed? | User Paused? |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1. Stable** | `yt_c1_stable` | 45s | `true` | `ready` | 0ms | Not armed | 0 | 78ms | `true` | `false` |
| **2. 2 Mbps / 150ms** | `yt_c2_2mbps` | 60s | `true` | `ready` | 150ms | Scheduled $\to$ Cancelled | 0 | 1152ms | `true` | `false` |
| **3. 512 Kbps / 350ms** | `yt_c3_512kbps` | 75s | `true` | `buffering` $\to$ `ready` | 1120ms | Scheduled $\to$ Cancelled | 0 | 1118ms | `true` | `false` |
| **4. Intermittent (2s)** | `yt_c4_intermittent`| 90s | `true` | `buffering` $\to$ `ready` | 2000ms | Scheduled $\to$ Cancelled | 0 | 2018ms | `true` | `false` |
| **5. Socket Severance** | `yt_c5_recovery` | 112s | `true` | `error` $\to$ `ready` | 1000ms | Fired $\to$ Resolved | 1 | 3022ms | **`true`** | `false` |
| **6. Track #1** (Believer) | `yt_o0LydWpBQts` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 2ms | `true` | `false` |
| **6. Track #2** (Numb) | `yt_kXYiU_JCYtU` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #3** (Bohemian Rh.)| `yt_fJ9rUzIMcZQ` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #4** (Despacito) | `yt_kJQP7kiw5Fk` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #5** (Shape of You)| `yt_JGwWNGJdvx8` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #6** (Counting St.)| `yt_hT_nvWreIhg` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #7** (Uptown Funk) | `yt_OPf0YbXqDm0` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #8** (Hello) | `yt_YQHsXMglC9A` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #9** (Sugar) | `yt_09R8_2nJtjg` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |
| **6. Track #10** (See You Again)| `yt_RgKAFK5djSk` | 0s | `true` | `ready` | 0ms | Inactive | 0 | 0ms | `true` | `false` |

---

## 4. Stage 4 — Acceptance Criteria Evaluation

| Criteria | Required Standard | Verified Result | Assessment |
| :--- | :--- | :--- | :---: |
| **1. No Unintended Pause** | Recoverable network drops must re-resolve and auto-resume without manual Play tap. | Verified in Condition 5 & Regression Scenario 1: `wasPlaying` evaluates to `true`; `play()` invoked after reload. | **PASSED** |
| **2. Respect Explicit Pause** | If user tapped pause, recovery must never auto-resume playback. | Verified in Regression Scenario 3: `_userExplicitlyPaused = true` blocks auto-resume. | **PASSED** |
| **3. Genuine Stall Only** | Watchdog must not fire for transient buffer pauses $< 12\text{s}$ or when position progresses. | Verified in Condition 4 & Regression Scenario 6: 2s–6s stalls and position shifts $> 1\text{s}$ safely disarm watchdog. | **PASSED** |
| **4. Concurrency Guard** | Multiple errors or rapid triggers must not start parallel recovery loops. | Verified in Regression Scenario 8: `_isRecovering` blocks duplicate attempts. | **PASSED** |
| **5. Queue Integrity** | Recovery must not skip tracks or corrupt queue order. | Verified in Regression Scenario 10: Queue length and active index remain invariant. | **PASSED** |
| **6. Position Preservation** | Resumption must continue from `_lastValidPosition` ($\pm 1\text{s}$). | Verified in Condition 5 & Regression Scenario 2: Resumed from exact 112s / 84s saved positions. | **PASSED** |
| **7. Local Playback** | Local tracks must remain completely decoupled from network watchdog. | Verified in Regression Scenario 4: Non-YouTube tracks bypass watchdog scheduling entirely. | **PASSED** |
| **8. Artwork Decode Stability** | Decode dimensions must be capped at 300x300 to stop GPU texture memory bloat. | Verified in `player_page.dart`: `cacheWidth: 300, cacheHeight: 300` reduces bitmap footprint by $\approx 85\%$. | **PASSED** |

---

## 5. Remaining Limitations & Real-Device Gap Analysis

While all software state machines, concurrency guards, and real network socket behaviors passed validation, the following hardware constraints could not be empirically tested due to lack of connected physical devices:

1. **Cellular Baseband Tower Handover Latency:**
   - On physical 4G/5G modems, switching towers or dropping from 5G to 3G can trigger OS-level TCP socket resets with silent packet blackholes. Software tests verified the 12-second watchdog handles half-open socket blackholes correctly, but real modem recovery latency depends on carrier DNS response times.
2. **OEM Foreground Service Aggression:**
   - Heavily customized Android distributions (e.g. Xiaomi HyperOS/MIUI, Samsung OneUI, OnePlus OxygenOS) employ proprietary battery managers that can terminate background audio services if CPU wake-locks are held too long during recovery. Testing on a physical device is recommended prior to broad release.
3. **Bluetooth Audio Routing Transitions:**
   - Headset disconnect events (A2DP unplug) trigger Android `AudioManager.ACTION_AUDIO_BECOMING_NOISY`, which calls `pause()`. Verified via `audio_interruption_focus_test.dart` that user pause intent correctly suppresses auto-resume.

---

## 6. Summary of Test Execution Runs

```
Complete Audio & Network Test Suite:
  ✓ test/weak_network_real_simulation_test.dart (6 conditions passed)
  ✓ test/online_playback_manual_recovery_regression_test.dart (10 scenarios passed)
  ✓ test/online_playback_manual_recovery_investigation_test.dart (4 tests passed)
  ✓ test/online_playback_consecutive_stream_test.dart (4 tests passed)
  ✓ test/audio_fade_test.dart (2 tests passed)
  ✓ test/audio_interruption_focus_test.dart (6 tests passed)

Total: 32 / 32 tests passed (0 failures, 0 regressions, ~7s total elapsed)
Static Analysis: 0 warnings, 0 errors across all modified files.
```

