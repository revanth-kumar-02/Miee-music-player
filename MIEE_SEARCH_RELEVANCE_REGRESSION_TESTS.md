# MIEE — Search Relevance Regression Test Report

## 1. Static Analysis

- **Command:** `flutter analyze --no-fatal-infos lib/features/search/domain/query_relevance_evaluator.dart lib/features/search/domain/canonical_music_ranker.dart lib/features/search/data/search_repository.dart lib/features/search/providers/search_providers.dart test/search_artist_relevance_regression_test.dart`
- **Result:** **0 errors, 0 warnings** (`6` pre-existing `info` hints in `search_repository.dart`).

---

## 2. Automated Test Suites Executed (After Final Edit)

| Test Suite | Coverage | Result |
|---|---|---|
| `test/search_artist_relevance_regression_test.dart` | Exact artist/song, unrelated exact-title rejection, featured/multi-artist credits, aliases (`AR Rahman`, `Sai Abhyankkar`, `YSR`), soundtrack credits, Tamil/Telugu/Remix/Live preservation, compilation album filtering, uploader vs artist protection, MB/iTunes duplicate merging, filtered autocomplete + `CancelToken`, rapid `SearchNotifier.searchNow` stale isolation | **PASS (9 / 9)** |
| `test/canonical_music_ranking_test.dart` | Ranking original recordings vs tribute covers (`Shape of You`, `Brooklyn Baby`, `We On Go`, `Ed Sheeran`) | **PASS** |
| `test/artist_resolution_and_search_filter_test.dart` | `ArtistClassifier` entity filtering & `ArtistResolutionService` | **PASS** |
| `test/om_first_strike_search_relevance_test.dart` | Multi-token regional soundtrack query relevance | **PASS** |
| `test/official_search_prioritization_test.dart` | Official channel & audio prioritization | **PASS** |
| `test/music_first_search_test.dart` | Music-first search architecture & playback resolution | **PASS** |
| `test/search_deduplication_test.dart` | Canonical song deduplication & version preservation | **PASS** |
| `test/all_the_stars_search_and_playback_test.dart` | Original artist ranking vs covers | **PASS** |
| **Combined 8-Suite Run** | Total across all 8 executed suites | **PASS (66 / 66)** |

---

## 3. Automated vs Real-Device Distinction

- **Automated Verification:** **66 / 66 passed** using deterministic provider stubs (`_StubYouTubeRepo`, `_StubItunesService`, `_StubMusicBrainzService`, `_StubArtistRepo`) and isolated Hive temp directories.
- **Real-Device Live Verification:** **Not executed in this run** (requires installing an updated build and testing live queries such as artist names, Tamil/Telugu tracks, and rapid typing on `vivo I2404`).
