# MIEE — Search Artist Relevance Changed Files

| File | Why It Was Modified |
|---|---|
| `lib/features/search/domain/query_relevance_evaluator.dart` | Added `expandArtistAliases`, `extractCreditedArtists`, `matchesCreditedArtist`, and `detectTargetedArtist`; added `expectedArtist` enforcement and tighter token thresholds in `isCandidateRelevant`; fixed substring and single-word false positives in `isArtistRelevant`. |
| `lib/features/search/domain/canonical_music_ranker.dart` | Updated `calculateScore` to score main artist, featured/collaborating credits, and aliases consistently while heavily penalizing unrelated-artist title matches, weak partial matches, and unverified channel-only results. |
| `lib/features/search/data/search_repository.dart` | Wired `targetedArtist` detection into `_executeYouTubeSearch`, restricted iTunes album-track bridging against unrelated compilation tracks, enforced `expectedArtist` across MusicBrainz/iTunes/YouTube merging and Stage B fallback, and added `CancelToken` + `MusicResultClassifier`/`QueryRelevanceEvaluator` filtering in `getLiveMusicSuggestions`. |
| `lib/features/search/providers/search_providers.dart` | Added `_activeSuggestionCancelToken` cancellation across `updateQuery`, `searchNow`, and `dispose`, and restricted `_enrichArtistsFromSongs` from promoting raw unverified YouTube uploaders into `onlineArtists`. |
| `test/search_artist_relevance_regression_test.dart` | Added deterministic unit & Riverpod regression tests covering artist relevance, aliases, collaborators, compilation filtering, provider merging, suggestions, and rapid query cancellation. |
