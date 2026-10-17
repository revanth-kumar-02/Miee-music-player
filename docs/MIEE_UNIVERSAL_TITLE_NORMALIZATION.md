# Miee — Universal Song Title Normalization Across All Artists and Languages

## 1. Executive Summary

This document details the audit, root cause discovery, universal normalization engine, test suite, and architectural integration implemented to resolve lingering YouTube uploader names and channel handles (e.g. `@SaiAbhyankkar - Vizhi Veekura`, `@SaiAbhyankkar - Pavazha Malli`) in song titles across all screens in Miee.

The solution is completely universal, script-agnostic, and rules-based. It does **not** rely on hardcoded artist name blacklists or screen-specific regex replacements. It works across Tamil, Telugu, Hindi, Malayalam, Kannada, English, and international tracks while strictly preserving legitimate hyphenated subtitles, version tags, and video playback URLs.

---

## 2. Root Cause Analysis

An in-depth byte inspection of live YouTube search results and audio track titles identified why previous cleanup attempts were incomplete:

1. **Zero-Width and Formatting Unicode Characters**:
   - YouTube video titles frequently prepend invisible characters before channel handles.
   - For example, `@SaiAbhyankkar - Vizhi Veekura` begins with Unicode codepoint `\u200B` (Zero-Width Space, dec `8203`).
   - Standard Dart `trim()` only strips ASCII and standard whitespace; it does **not** remove zero-width spaces (`\u200B-\u200D`), byte order marks (`\uFEFF`), or directional formatting marks (`\u200E\u200F\u202A-\u202E`).
   - Consequently, regular expressions matching `^@` failed to match at index 0 because index 0 was occupied by `\u200B`.

2. **ASCII-Only Comparison Stripping Indian Scripts**:
   - Similarity comparisons in earlier helpers utilized `[^a-z0-9]`.
   - When evaluating non-Latin scripts (Tamil, Hindi, Telugu, Malayalam), all native characters were wiped out, reducing words to empty strings and causing similarity detection to fail for regional artists.

3. **Multi-Clause Delimiters (`|`, `•`, `//`) and Repeated Handles**:
   - Indian film music and independent releases often format titles with multiple pipe or bullet clauses (e.g. `Song Title | Cast | Music Director | Label`).
   - Additionally, some uploaders include duplicate handles (e.g. `@Handle - @Handle - Song Name`) or bracketed handles (`[@Handle]`).

---

## 3. Universal Normalization Rules

The shared metadata engine in [YouTubeMetadataCleaner](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/lib/features/youtube/domain/youtube_metadata_cleaner.dart) executes the following sequence:

1. **Invisible Character Stripping**:
   - Strips `\u200B-\u200D` (zero-width spaces/joiners), `\uFEFF` (BOM), `\u200E\u200F\u202A-\u202E` (directional marks), and `\u2060` (word joiner), and normalizes non-breaking spaces `\u00A0` to standard spaces.

2. **Structured & Reliable Metadata Preference**:
   - If a verified structured song title is provided (e.g. from Deezer catalog or user selection) and matches the video title content, it is preferred directly.

3. **Multi-Clause Separation (`|`, `•`, `//`)**:
   - Splits into semantic clauses. Pure video noise clauses (e.g. "Official Music Video", "Lyrical Video", "Trailer") are discarded.
   - The primary clause is extracted as the candidate song title, and trailing clauses are evaluated for artist and contributor credits.
   - Any leading `@handle` prefix (or duplicate handles) on the song clause is stripped.

4. **Hyphen Separator Handling (` - `, ` – `, ` — `)**:
   - When no multi-clause separator is present, hyphen separators are parsed.
   - **Conservative Subtitle Preservation**: If the right-hand side represents a legitimate title modifier (e.g. `"Part 1"`, `"Pt. 2"`, `"Vol. 1"`, `"Acoustic"`, `"Live"`, `"In the Air"`, `"Taylor's Version"`), the full hyphenated title is preserved without destructive splitting.
   - **Leading Handle Detection**: If the left segment starts with `@`, it is identified as a channel/uploader handle and stripped.
   - **Similarity Matching**: If either side matches the uploader channel or known artist using Unicode letter matching (`\p{L}\p{N}`), the artist side is separated and the title side is retained.
   - **Ambiguity Guard**: If neither side has evidence of being an artist or uploader, the title is preserved intact (e.g. `"Catch-22"`).

5. **Universal Handle Extraction**:
   - Uses regex `^[\(\[]?\s*@([a-zA-Z0-9_\.\-]+)\s*[\)\]]?\s*[\-\–\—\:\/\|\•\s]\s*` to detect and strip handles regardless of whether they are separated by dashes, colons, slashes, or bullets, or enclosed in brackets.
   - Preserves legitimate `@` symbols when used as internal song words (e.g. `"Look @ Me"`).

6. **Decoupled Playback Identification**:
   - The raw source title (`rawTitle`) and channel (`rawArtist`) are retained in the [Track](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/lib/shared/models/music_item.dart) model for diagnostics.
   - The track identity (`id`), audio stream URLs, and YouTube video IDs remain 100% untouched, ensuring background playback, queue management, and stream resolution are never interrupted.

---

## 4. Pipeline Integration & Consistency

Universal normalization is applied at the central mapping layer:

- **Search Results**: [YouTubeRepository.search()](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/lib/features/youtube/data/youtube_repository.dart) cleans all search results at ingestion.
- **Track Conversions**: [YouTubeVideo.toTrack()](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/lib/features/youtube/domain/youtube_model.dart) ensures any YouTube video converted to a playable track receives normalized title and artist metadata.
- **Home Recommendations**: [RecommendationService](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/lib/features/recommendations/data/recommendation_service.dart) builds on clean candidate tracks.
- **Artist Profiles**: Artist top tracks and singles utilize the same unified mapping.
- **Playback UI**: Mini-player, Now Playing screen, and Playing Queue read directly from `Track.title` and `Track.artist`, guaranteeing visual consistency without duplicated UI string manipulation.

---

## 5. Verification & Test Suite

### Regression Tests

All 15 regression test scenarios in [universal_title_normalization_test.dart](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/universal_title_normalization_test.dart) passed:

1. `@SaiAbhyankkar - Vizhi Veekura` with zero-width space in pipe-delimited title -> Normalized to `Vizhi Veekura`.
2. `@SaiAbhyankkar - Vizhi Veekura` with zero-width space in hyphen-only title -> Normalized to `Vizhi Veekura`.
3. `@SaiAbhyankkar - Pavazha Malli` in pipe format -> Normalized to `Pavazha Malli`.
4. `Look @ Me` -> Preserves internal `@` symbol as `Look @ Me`.
5. `Pink Floyd - Breathe - In the Air` -> Preserves legitimate subtitle modifier as `Breathe - In the Air`.
6. `Shine On You Crazy Diamond - Part 1` -> Preserves version/part modifier as `Shine On You Crazy Diamond - Part 1`.
7. `Sony Music South - Aalaporaan Thamizhan | Mersal` -> Strips uploader channel prefix cleanly.
8. `ஹாரிஸ் ஜெயராஜ் - வசீகரா` (Tamil) -> Strips uploader prefix script-agnostically without hardcoded lists.
9. `Catch-22` -> Preserves hyphenated title without space.
10. `   ` -> Safely handles empty/whitespace titles without crashing.
11. `ए. आर. रहमान - जय हो` (Hindi) -> Strips Hindi uploader prefix cleanly.
12. `ఆదిత్య మ్యూజిక్ - సామజవరగమన` (Telugu) -> Separates Telugu uploader channel cleanly.
13. `@SaiAbhyankkar - @SaiAbhyankkar - Vizhi Veekura` -> Strips duplicate/repeated handles.
14. `Justin Bieber ft. Ludacris - Baby` -> Separates artist and featured credit cleanly.
15. `Random Uploader Studio - Beautiful Sunrise` -> Preserves channel rather than fabricating non-existent artists.

### Existing Tests Passing
- All 11 tests in [recommendation_and_title_normalization_test.dart](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/recommendation_and_title_normalization_test.dart) pass with 0 regressions.
- Static analysis (`flutter analyze lib/features/youtube test/universal_title_normalization_test.dart`): **0 issues found**.

---

## 6. Changed Files

| File | Change Description |
|---|---|
| [lib/features/youtube/domain/youtube_metadata_cleaner.dart](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/lib/features/youtube/domain/youtube_metadata_cleaner.dart) | Integrated zero-width character stripping, universal `@handle` regex extractor, script-agnostic `\p{L}\p{N}` matching, and conservative subtitle protection. |
| [test/universal_title_normalization_test.dart](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/test/universal_title_normalization_test.dart) | Created 15-case regression test suite covering handles, zero-width chars, non-Latin scripts, modifiers, and edge cases. |
| [docs/MIEE_UNIVERSAL_TITLE_NORMALIZATION.md](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/docs/MIEE_UNIVERSAL_TITLE_NORMALIZATION.md) | Technical audit, root cause documentation, architecture rules, and verification log. |
| [.vscode/settings.json](file:///home/rev/My_Personal_Space/Projects/Unfinished/Miee/.vscode/settings.json) | Disabled automatic Gradle daemon spawning to protect laptop memory. |
| `~/.gradle/gradle.properties` | Configured `org.gradle.daemon=false` and memory limits to prevent runaway background daemons. |

---

## 7. Remaining Limitations

- Videos titled exclusively with arbitrary emojis or non-standard punctuation that contain no text will retain their original raw title to prevent empty titles.
- Uploader titles that lack any separator or handle marker (e.g. `SaiAbhyankkarVizhiVeekura`) without spaces cannot be safely segmented without natural language tokenizers, and are preserved safely to avoid destructive truncation.
