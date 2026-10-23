# Miee — Multilingual Lyrics Support Architecture & REA Documentation

## 1. Executive Summary & Problem Analysis
In Miee, English songs frequently displayed synchronized lyrics via LRCLIB, but Tamil, Telugu, Malayalam, Hindi, Kannada, and other non-English songs consistently failed to display lyrics or returned empty results.

Through mandatory REA (Reasoning, Exploration, and Analysis), we traced the complete pipeline:
- Track metadata ingestion (`MusicItem`, `Track`).
- Video title and artist extraction from YouTube/local sources.
- Lyrics query construction and API endpoints (`https://lrclib.net/api/get` and `/api/search`).
- Response parsing, candidate validation, and error states.
- Caching and UI synchronization.

---

## 2. Evidence-Based Root Causes

### Root Cause 1: LRCLIB Indian Music Indexing vs Native Script Queries
- **Evidence:** Querying LRCLIB with native script (e.g. `ஊ சொல்றியா`, `கண்ணான கண்ணே`, `केसरिया`, `నాటు నాటు`) returned 0 results. However, querying LRCLIB with the romanized names (`Oo Solriya`, `Kannaana Kanney`, `Kesariya`, `Naatu Naatu`) returned rich results with **authentic native-script synchronized lyrics** (e.g. `[00:35.54] கண்ணான கண்ணே`).
- **Cause:** LRCLIB indexes Indian tracks primarily by their standardized Romanized/Latin track names from Spotify and Apple Music metadata, while the lyrics content itself is in native script. Without romanized candidate fallbacks or Indic transliteration, queries sent in native script consistently missed the index.

### Root Cause 2: Destruction of Romanized Titles in Bilingual Parentheses
- **Evidence:** YouTube tracks for Indian music frequently include bilingual names: e.g. `Kannaana Kanney (கண்ணான கண்ணே)` or `கண்ணான கண்ணே (Kannaana Kanney)`.
- **Cause:** The previous `_cleanTitle` implementation used `t.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '')`. This indiscriminately erased all parenthetical content, throwing away the romanized title and leaving only the native script that LRCLIB's index failed to match.

### Root Cause 3: YouTube Uploader and Video Noise Pollution
- **Evidence:** Indian YouTube music releases are heavily polluted with video metadata: `Arabic Kuthu - Video Song | Beast | Thalapathy Vijay | Sun Pictures | Anirudh` with artist `Sun TV` or `Sony Music South`.
- **Cause:** Previously, `_cleanTitle` only stripped bracketed words and phrases like `official audio`. It left `| Beast | Thalapathy Vijay | Sun Pictures | Anirudh` in the title and passed `Sun TV` as `artist_name`. LRCLIB `/api/get` returned 404, and `/api/search` with `Sun TV` returned 0 results.

### Root Cause 4: Strict Duration Rejection in `/api/get`
- **Evidence:** LRCLIB `/api/get` strictly requires `duration` to match within ±2 seconds.
- **Cause:** YouTube tracks often include intro dialogues, title cards, or outro credits (10–20 seconds duration difference). When `duration` was sent, `/api/get` rejected valid songs.

### Root Cause 5: Missing Candidate Result Validation (False Positive Risk)
- **Evidence:** In `lyrics_providers.dart`, the fallback search loop took `results[0]` unconditionally as long as `syncedLyrics` was not null.
- **Cause:** Without string similarity and duration validation, loose search queries could return an unrelated song with similar words.

### Root Cause 6: Missing Value Equality and Transient Error Caching
- **Evidence:** `Track` did not implement `operator ==` or `hashCode`, causing Riverpod family providers to re-instantiate on state updates. Additionally, transient network errors (HTTP 429/503) were not retried with backoff.

---

## 3. Implementation Details

1. **`lib/features/lyrics/domain/indic_transliterator.dart`**:
   - Zero-dependency, deterministic Indic transliterator covering Tamil (`\u0B80-\u0BFF`), Telugu (`\u0C00-\u0C7F`), Malayalam (`\u0D00-\u0D7F`), Kannada (`\u0C80-\u0CFF`), Devanagari (`\u0900-\u097F`), Bengali, Gujarati, Gurmukhi, and Odia.
   - Handles viramas/halants (inherent vowel suppression), matras, and phonetic stemming (`\p{L}\p{M}\p{N}\s`).

2. **`lib/features/lyrics/domain/lyrics_search_query_builder.dart`**:
   - Preserves track identity while generating a prioritized list of search candidates:
     1. Primary: Clean song title + verified artist.
     2. Clean song title only (strips record labels like `Sony Music South`, `Sun TV`, `T-Series`, `Saregama`, etc.).
     3. Parenthetical bilingual candidate (extracts inner Latin or native script title).
     4. Transliterated candidate (for Indic scripts).
     5. Multi-clause delimited candidate (extracts pure song title from `Song - Video | Movie | Cast`).

3. **`lib/features/lyrics/domain/lyrics_validator.dart`**:
   - Multi-metric candidate validation:
     - Exact normalized match.
     - Subtitle/version strip match.
     - Indic transliteration and phonetic stem matching (`IndicTransliterator.phoneticStem`).
     - Substring/token overlap protection (prevents `"Yellow"` matching `"Black and Yellow"` or `"Starboy"` matching `"Stargirl"`).
     - Duration check tolerance (±45s to accommodate YouTube intro/outro dialogue while rejecting different songs).

4. **`lib/features/lyrics/data/lyrics_repository.dart`**:
   - `LrclibLyricsRepository`:
     - In-memory cache isolated by track ID and normalized key.
     - In-flight request deduplication (prevents concurrent duplicate requests).
     - Retry with backoff for HTTP 429/503 rate limits.
     - Does not permanently cache transient failures.
     - Supports local `.lrc` files, LRCLIB `/api/get`, and controlled search fallback `/api/search`.
     - Preserves authentic timestamps for synced lyrics; plain lyrics fallback uses `Duration.zero` (no fabricated timestamps).

5. **`lib/features/lyrics/providers/lyrics_providers.dart`**:
   - Clean Riverpod architecture: `lyricsRepositoryProvider` and `lyricsProvider(track)`.

6. **`lib/shared/models/track.dart`**:
   - Added `operator ==` and `hashCode` based on `id` for stable identity and cache isolation.

7. **`lib/features/lyrics/presentation/widgets/lyrics_overlay.dart`**:
   - Styled with `height: 1.35` and `maxLines: 4` for clean rendering of Indic combining vowel signs without clipping.

8. **`test/multilingual_lyrics_test.dart`**:
   - 16 automated tests covering all 11 required scenarios using deterministic mock Dio interceptors.

---

## 4. Test Verification
All automated suites pass with zero regressions:
- `test/multilingual_lyrics_test.dart` (16/16 passed)
- `test/lyrics_sync_test.dart` (8/8 passed)
- `test/lyrics_and_queue_persistence_test.dart` (4/4 passed)
- `test/track_identity_mismatch_test.dart` (8/8 passed)
- `test/settings_cleanup_and_miniplayer_visibility_test.dart` (36/36 passed)
