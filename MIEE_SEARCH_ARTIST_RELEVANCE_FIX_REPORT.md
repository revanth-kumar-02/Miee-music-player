# MIEE — Search Result Artist Relevance & False-Positive Fix Report

- **Package:** `com.example.miee` (`Miee`, `2.0.0+2`)
- **Scope:** Full search pipeline (`SearchNotifier`, `SearchRepository`, `QueryRelevanceEvaluator`, `CanonicalMusicRanker`, autocomplete suggestions, album bridging, and MusicBrainz/iTunes/YouTube merging).

---

## 1. Confirmed Root Causes

1. **Substring & Single-Token Artist Collisions (`QueryRelevanceEvaluator`):**
   - `isArtistRelevant` accepted `.contains()` substring matches (`"Aria"` matched `"Ariana Grande"`) and single-token overlaps on multi-word names (`"Lana Del Rey"` matched `"Rey Mysterio"`).
   - `isCandidateRelevant` allowed 50% partial-token matches and title-only matches even when the query targeted a specific artist, and lacked `expectedArtist` enforcement.
2. **Unrestricted Album Bridging & Uncorroborated `canonicalArtist` (`SearchRepository._executeYouTubeSearch`):**
   - iTunes album discovery matched albums via `clean.toLowerCase().contains(albTitle)` without artist verification and merged every track from `Various Artists` / compilation albums into `itunesSongs`.
   - When MusicBrainz/iTunes/YouTube candidates were filtered, `expectedArtist` was not enforced, and Stage B fallback only checked `isCandidateRelevant` without `MusicResultClassifier` on the secondary branch.
3. **Uploaders vs Recording Artists & Unpenalized Wrong-Artist Title Matches (`CanonicalMusicRanker`):**
   - `calculateScore` checked only exact equality/substring on raw `canonicalArtist ?? channelTitle`, failing on multi-artist credits (`feat.`, `&`, `,`), missing artist aliases (`A. R. Rahman` ↔ `AR Rahman`, `Sai Abhyankar` ↔ `Sai Abhyankkar`), and allowing unrelated artists with exact title matches + MusicBrainz/iTunes bonuses to outrank relevant tracks.
4. **Unfiltered Suggestions & Uploader Promotion (`SearchRepository.getLiveMusicSuggestions`, `SearchNotifier._enrichArtistsFromSongs`):**
   - `getLiveMusicSuggestions` returned raw `youtubeRepository.search` videos and `onlineAlbums` without `MusicResultClassifier` or `QueryRelevanceEvaluator` checks, and had no `CancelToken` support for stale typing bursts.
   - `_enrichArtistsFromSongs` promoted arbitrary YouTube channel names (`channelTitle`) into `onlineArtists` even when `canonicalArtist` was absent.

---

## 2. Implemented Fixes

1. **`lib/features/search/domain/query_relevance_evaluator.dart`:**
   - Added `expandArtistAliases`, `extractCreditedArtists`, `matchesCreditedArtist` (supporting exact, normalized, alias, featured/collaborating artists, and structured title credits like `Music: Anirudh Ravichander`), and `detectTargetedArtist`.
   - Added `expectedArtist` gating in `isCandidateRelevant`, tightened multi-token & language-token coverage (`>= 65%` instead of `50%`), and removed substring/single-word false positives in `isArtistRelevant`.
2. **`lib/features/search/domain/canonical_music_ranker.dart`:**
   - Updated `calculateScore` to evaluate main artist (`+420.0`), featured/collaborating artist (`+340.0`), and alias matches cleanly; heavily penalized exact/strong title matches attributed to unrelated artists (`-420.0`), weak partial matches (`-100.0`), and unverified uploader-only channels (`-80.0`).
3. **`lib/features/search/data/search_repository.dart`:**
   - Detected `targetedArtist` in `_executeYouTubeSearch`, guarded album-track bridging against compilation tracks by unrelated artists, enforced `expectedArtist` across MusicBrainz, iTunes, and YouTube results, and applied `MusicResultClassifier` consistently on Stage B fallback.
   - Filtered `onlineVideos` and `onlineAlbums` in `getLiveMusicSuggestions` using `MusicResultClassifier` and `QueryRelevanceEvaluator`, and added `CancelToken` cancellation checks before caching/returning.
4. **`lib/features/search/providers/search_providers.dart`:**
   - Wired `_activeSuggestionCancelToken` into `SearchNotifier.updateQuery`, `searchNow`, and `dispose`.
   - Hardened `_enrichArtistsFromSongs` to ignore unverified random uploaders and validate promoted artists with `ArtistClassifier.isLegitimateMusicArtist`.

---

## 3. Verification Status

- **Analyzer (`flutter analyze --no-fatal-infos`):** **0 errors, 0 warnings** on all 4 modified `lib/` files and `test/search_artist_relevance_regression_test.dart`.
- **Automated Search Tests:** **66 / 66 passed** across all 8 suites (see `MIEE_SEARCH_RELEVANCE_REGRESSION_TESTS.md`).
- **Real-Device Runtime Verification:** **Pending** (automated deterministic tests ran against stubbed providers; live Android device queries against YouTube/iTunes/MusicBrainz should be spot-checked after rebuilding).
