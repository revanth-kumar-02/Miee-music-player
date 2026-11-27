# MIEE — Playing Queue Regression Test Report

## 1. Static Analysis Results

- **Command:** `flutter analyze --no-fatal-infos lib/core/audio/playback_state.dart lib/core/audio/player_controller.dart lib/core/audio/audio_handler.dart lib/features/queue/presentation/queue_page.dart lib/features/youtube/domain/music_result_classifier.dart lib/features/recommendations/data/recommendation_service.dart lib/features/search/domain/search_deduplicator.dart lib/features/artwork/domain/artwork_query.dart test/playing_queue_root_cause_regression_test.dart`
- **Result:** **0 errors** (`21` pre-existing style/deprecation `info` items).

---

## 2. Automated Test Suites Executed (After Final Edit)

| Test Suite | Scope | Result |
|---|---|---|
| `test/playing_queue_root_cause_regression_test.dart` | `Q-01`..`Q-06` unit & widget regression tests (reactive `QueuePage`, editorial clip rejection, cross-language dedup, `maxTracksPerArtist = 2`, artwork identity, playback source validation) | **PASS (10 / 10)** |
| `test/automatic_queue_advancement_test.dart` | Automatic queue advancement & failure recovery | **PASS (9 / 9)** |
| `test/youtube_search_queue_unrelated_videos_test.dart` | Non-music / scene / vlog / meme channel rejection & regional music preservation | **PASS (10 / 10)** |
| `test/queue_generation_and_deduplication_test.dart` | Queue generation, homonym rejection, album/playlist preservation | **PASS** |
| `test/queue_relevance_and_deduplication_test.dart` | Queue relevance, duplicate upload collapsing, version preservation | **PASS** |
| `test/veezha_veera_validation_and_deduplication_test.dart` | Multilingual search/dedup & regional track validation | **PASS** |
| `test/artwork_priority_and_display_test.dart` | Artwork priority, cache overwrite protection, `MieeArtworkImage` rendering | **PASS** |
| `test/artwork_resolver_test.dart` | Artwork resolver cascade, deduplication, fallback & widget states | **PASS** |
| **Combined 8-Suite Run** | Total across all 8 executed suites | **PASS (82 / 82)** |

---

## 3. Pre-Existing Unrelated Test Compilation Failures

- `test/language_personalized_recommendations_test.dart` — **Failed to compile** (pre-existing `MockYouTubeRepo` missing `explodeCircuitCooldown` / `isExplodeCircuitOpen` and updated `search`/`getArtistTracks` named parameters).
- `test/queue_extension_and_deduplication_test.dart` — **Failed to compile** (pre-existing stale `MockYouTubeRepo` stub).

---

## 4. Real-Device Verification Status

- **Real-Device Verification:** **STILL REQUIRED** — deterministic unit and widget tests are passing (`82 / 82`), but live YouTube InnerTube stream resolution, background recommendation network latency, and lockscreen/notification artwork on `vivo I2404` (`10BF5809GA0029L`) have not yet been re-tested after these Phase 1–6 edits.
