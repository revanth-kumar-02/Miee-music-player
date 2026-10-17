# Miee — Home Recommendation Quality & Song Title Normalization

## Overview

This document describes the root causes, architecture, classification rules, title-normalization logic, files changed, and verification results for resolving **Discover More recommendations** (removing 29-minute jukebox compilations, playlists, and generic collections) and **Song Title Normalization** (cleaning concatenated YouTube video metadata while preserving genuine punctuation and separate credits).

---

## 1. Root Causes

### 1.1 Discover More Video Quality & Long-Form Compilations
1. **Compounding Search Query**: `RecommendationService` previously formulated YouTube discovery queries as `"${rel.name} top hits"`. Querying YouTube for `"top hits"` directly instructs YouTube's ranking algorithm to prioritize 20–50 minute playlist mixes, mega jukeboxes, and compilations rather than individual tracks.
2. **Permissive Duration Cutoff**: The duration cutoff in `isLegitimateSong` was set at 35 minutes (2100 seconds). A typical 29-minute playlist compilation (~1740 seconds) bypassed the duration check unless it explicitly contained the exact string `"all songs jukebox"`.
3. **Flat Priority & Lack of Fallback**: Recommendations only queried the top two related artists without a multi-tier fallback pipeline. When compilations were encountered, either bad results were shown or the shelf was left starved.

### 1.2 Concatenated YouTube Video Titles
1. **Label Title Conventions**: Indian music labels (Sony Music South, Saregama, Think Music, Lahari, etc.) upload individual songs with concatenated multi-credit titles containing pipe (`|`) or hyphen separators:
   - `"Radhimaa | Bhagyashri Borse | Dulquer Salmaan | GV Prakash Kumar | Official Video"`
   - `"Pavazha Malli | Kayadu Lohar | Shruti Haasan | Santhosh Narayanan | Lyric Video"`
   - `"@SaiAbhyankkar - Pavazha Malli | ..."`
2. **Destructive or Incomplete Parsing**: Previously, title parsing either split naively on the first hyphen (corrupting legitimate subtitles like `"Breathe - In the Air"` or `"Shine On You Crazy Diamond - Part 1"`), or failed to extract the pure song title from multi-clause pipe structures, causing concatenated strings to leak into Home shelves, the mini-player, the queue, and Now Playing.
3. **Loss of Diagnostic Context**: When titles were altered, the original raw YouTube title was lost, hindering debugging and parser refinement.

---

## 2. Architecture & Classification Rules

### 2.1 Candidate Filtering Layer (`RecommendationService.isLegitimateSong`)
The candidate filter evaluates structured video metadata (duration, title, channel) through multi-stage classification:

| Category | Rules & Patterns | Classification |
| :--- | :--- | :--- |
| **Spoken-Word & Non-Music** | `podcast`, `episode #`, `\bep\.?\s*\d+\b`, `interview with`, `exclusive interview`, `press meet`, `trailer`, `teaser`, `audio launch`, `making of`, `behind the scenes`, `audio commentary` | **Rejected** |
| **Full Movies & Scene Packs** | `full movie`, `tamil movie`, `telugu movie`, `hindi movie`, `malayalam movie`, `kannada movie`, `comedy scene`, `best scenes`, `movie scenes`, `scene collection` | **Rejected** |
| **Jukeboxes & Continuous Mixes** | `jukebox`, `continuous mix`, `non stop`, `nonstop`, `mashup mix`, `mega mix`, `megamix`, `audio jukebox`, `video jukebox`, `all songs jukebox`, `back to back`, `b2b songs`, `songs jukebox` | **Rejected** |
| **Collections & Template Playlists** | Regex `(\btop\s*\d+\b\|\bbest\s+of\b\|\bhit\s+songs\s+collection\b\|\ball\s+songs\b\|\bfull\s+album\b\|\bfull\s+playlist\b\|\bplaylist\b\|\bcompilation\b\|\bsongs\s+collection\b)` | **Rejected** |
| **25+ Minute Compilations** | `durationSec >= 1500` (e.g. 29-minute videos) unless containing classical markers (`raga`, `alapana`, `symphony`, `carnatic`, `kriti`, `varnam`) | **Rejected** |
| **15–25 Minute Multi-Track Markers**| `durationSec >= 900` AND contains `hits`, `songs`, `album`, `collection`, `mix`, `vol`, `part 1 & 2`, `medley` | **Rejected** |
| **Hard Ceiling** | `durationSec > 2100` (> 35 mins) | **Rejected** |
| **Genuine Standalone Tracks** | Ordinary songs (e.g. 3–5 min), even if containing `"official video"`, `"hits"`, or `"audio"`, and legitimate long individual pieces (e.g. 14–18 min progressive rock, Carnatic alapana) | **Preserved** |

### 2.2 Recommendation Ranking & Fallback Pipeline
In `RecommendationService.getPersonalizedSections`:
1. **Clean Search Queries**: Switched search queries from `"${rel.name} top hits"` to clean queries: `"${artist.name} song"`.
2. **Priority 1 (Favourite Artists)**: Top individual tracks from the user's selected favourite artists.
3. **Priority 2 (Verified Related Artists)**: Clean individual tracks from verified related artists.
4. **Priority 3 (Curated Regional Catalog)**: If filtering leaves fewer than 6 candidates, dynamic fallback queries the curated regional catalog (`DeezerArtistRepository.staticCuratedArtists`) across Tamil, Telugu, Hindi, Malayalam, and International artists.
5. **Relevance Scoring**: Candidates are scored by channel confidence (`- Topic`, `VEVO`, `Official`) and penalized for ambiguous terms (`hits`, `remix`), ranking the cleanest tracks first.

---

## 3. Song Title Normalization Logic (`YouTubeMetadataCleaner`)

### 3.1 Clause Extraction with Separator Preservation
1. **Pipe (`|`) Separation**:
   - Parses multi-segment strings: `[Song Title, Star Cast, Music Director, Video Noise]`.
   - Strips purely promotional noise clauses (`"Official Video"`, `"Lyrical Video"`, `"Trailer"`, `"Visualizer"`).
   - Extracts the core song clause (e.g. `"Radhimaa"`, `"Pavazha Malli"`).
   - Strips YouTube channel handles (e.g. `"@SaiAbhyankkar - Pavazha Malli"` -> `"Pavazha Malli"`).
2. **Hyphen (` - `, ` – `, ` — `) Conservative Parsing**:
   - Checks if the right side is a legitimate title modifier using `_isTitleModifier`:
     - Subtitles / Continuations: `"In the Air"`, `"A Love Story"`, `"Interlude"`
     - Parts / Chapters: `"Part 1"`, `"Pt. 1"`, `"Vol. 1"`, `"Side A"`
     - Versions: `"Acoustic"`, `"Live"`, `"Reprise"`, `"Orchestral"`, `"Lofi"`, `"Extended"`
   - If recognized as a modifier, the separator is **preserved** (e.g. `"Breathe - In the Air"`).
3. **Artist Credit Separation**:
   - If `reliableArtist` is provided (from Deezer or curated catalog), it is strictly preserved.
   - If missing, credit clauses are checked against `DeezerArtistRepository.findCuratedByName`.
   - Never fabricates unknown credits; falls back cleanly to the source channel without inventing performers.
4. **Raw Metadata Diagnostics**:
   - Added `Track.rawTitle` and `Track.rawArtist` fields to preserve original upstream strings for telemetry and diagnostics without altering stream resolution or playback IDs (`youtube_$id`).

---

## 4. Files Changed

| File | Changes Made |
| :--- | :--- |
| `lib/shared/models/track.dart` | Added optional `rawTitle` and `rawArtist` fields to `Track` model. |
| `lib/features/youtube/domain/youtube_model.dart` | Updated `toTrack({String? reliableArtist, String? reliableTitle})` to use `YouTubeMetadataCleaner` and populate raw fields. |
| `lib/features/youtube/domain/youtube_metadata_cleaner.dart` | Rewrote into intelligent, conservative normalizer with pipe clause parsing, handle stripping (`@channel - `), legitimate modifier preservation, and reliable metadata prioritization. |
| `lib/features/onboarding/data/artist_discovery_repository.dart` | Added alphanumeric normalization in `findCuratedByName` and exposed `staticCuratedArtists` getter. |
| `lib/features/recommendations/data/recommendation_service.dart` | Implemented multi-stage `isLegitimateSong` candidate filtering, candidate ranking, clean song queries, and 3-tier fallback fetching. |
| `lib/features/library/presentation/artist_detail_page.dart` | Migrated track mapping to `v.toTrack(reliableArtist: artist.name)` and fixed lints. |
| `test/recommendation_and_title_normalization_test.dart` | Created 11 comprehensive automated tests covering all required filtering and title scenarios. |

---

## 5. Verification Results

### 5.1 Automated Unit & Integration Tests
Ran `flutter test test/recommendation_and_title_normalization_test.dart`:
```
00:00 +0: Issue 1 & 2: Discover More Candidate Filtering & Classification 1. Rejects a 29-minute playlist compilation
00:00 +1: Issue 1 & 2: Discover More Candidate Filtering & Classification 2. Rejects Top 10 and Top 20 collections
00:00 +2: Issue 1 & 2: Discover More Candidate Filtering & Classification 3. Rejects Jukeboxes and continuous mixes
00:00 +3: Issue 1 & 2: Discover More Candidate Filtering & Classification 4. Preserves a genuine long individual song (e.g. 14-18 minute piece or classical)
00:00 +4: Issue 1 & 2: Discover More Candidate Filtering & Classification 5. Rejects podcast episodes and spoken-word videos
00:00 +5: Issue 1 & 2: Discover More Candidate Filtering & Classification 6. Preserves an ordinary standalone song, even with ambiguous terms like "hits" or "official video"
00:00 +6: Issue 3: Song Title Normalization & Credit Extraction 7. Normalizes "Radhimaa | Bhagyashri Borse | ..." with reliable metadata
00:00 +7: Issue 3: Song Title Normalization & Credit Extraction 8. Normalizes "Pavazha Malli | Kayadu | Shruti ..." with reliable metadata
00:00 +8: Issue 3: Song Title Normalization & Credit Extraction 9. Preserves titles containing legitimate separators without destructive splitting
00:00 +9: Issue 3: Song Title Normalization & Credit Extraction 10. Handles missing or ambiguous artist metadata without fabricating artist credits
00:00 +10: Discover More Fallback & Multi-Tier Resolution 11. Discover More falls back when filtering eliminates non-songs and leaves too few results
00:00 +11: All tests passed!
```

### 5.2 Regression Tests
Ran `flutter test test/unified_search_and_artist_profile_test.dart test/artist_discovery_and_images_test.dart test/auth_onboarding_recommendations_test.dart`:
- **All 28 tests passed.**

### 5.3 Static Code Analysis
Ran `flutter analyze lib/features/recommendations lib/features/youtube lib/features/onboarding lib/shared/models lib/features/library/presentation/artist_detail_page.dart`:
- **No issues found (0 errors, 0 warnings).**

### 5.4 Physical Android Device Verification
- Target device: `10BF5809GA0029L` (Vivo Android device).
- APK built via `flutter build apk --debug` (74.3s).
- Streamed install completed: `Success`.
- Gradle and Kotlin daemons killed post-install to conserve host memory.
- App launched and verified running.
