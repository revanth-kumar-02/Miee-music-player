/// Intelligent domain classifier to distinguish genuine music artists, bands,
/// and ensembles from non-music entities (schools, colleges, sports clubs,
/// businesses, radio stations, and hobby alliances).
class ArtistClassifier {
  /// Regular expressions identifying non-artist entity categories.

  // 1. Educational and academic institutions
  static final _educationalPattern = RegExp(
    r'\b(college|university|school|academy|institute|seminary|campus|highschool|kindergarten|faculty|alumni)\b',
    caseSensitive: false,
  );

  // Musical exception keywords that rescue legitimate institutional ensembles / choirs / orchestras
  static final _musicalEnsembleExceptionPattern = RegExp(
    r'\b(choir|chorus|chorale|orchestra|symphony|philharmonic|band|ensemble|quartet|trio|quintet|consort|gospel|singers|brass)\b',
    caseSensitive: false,
  );

  // 2. Sports clubs, athletic teams, and leagues
  static final _sportsPattern = RegExp(
    r'\b(football\s+club|f\.?c\.?|soccer\s+club|sports\s+club|athletic\s+club|athletics|cricket\s+club|rugby\s+club|motorsports|racing\s+team|basketball\s+team|baseball\s+club)\b',
    caseSensitive: false,
  );

  // 3. Commercial businesses, vocational training, trade, and corporate services
  static final _commercialPattern = RegExp(
    r'\b(dealing\s+school|dealers(hip)?|motors|realty|real\s+estate|consulting|solutions|pharmacy|hospital|clinic|law\s+firm|llc|inc\.?|ltd\.?|corporation|dealership|automotive|repairs?)\b',
    caseSensitive: false,
  );

  // 4. Radio stations, 24/7 livestreams, and broadcast aggregators
  static final _radioBroadcastPattern = RegExp(
    r'\b(radio(\s+station)?|fm|broadcast(ing)?|podcasts?|news\s+channel|tv\s+channel|livestream|24/7)\b',
    caseSensitive: false,
  );

  // 5. Gaming, toy/hobby groups, and community alliances
  static final _hobbyAlliancePattern = RegExp(
    r'\b(gunpla(\s+alliance)?|alliance|esports|gaming\s+clan|clan|fanpage|fan\s+club|fans\s+club|fanbase)\b',
    caseSensitive: false,
  );

  // 6. Generic vibe aggregators or playlist channels (unless part of a known artist band name)
  static final _vibeAggregatorPattern = RegExp(
    r'(\b\w+\s+(vibes|chill\s+beats|status\s+channel|records\s+channel)\b|\bvibes\b$)',
    caseSensitive: false,
  );

  /// Determines whether the given candidate represents a legitimate music artist entity.
  static bool isLegitimateMusicArtist(
    String rawName, {
    int fanCount = 0,
    String? query,
    bool isCurated = false,
  }) {
    if (isCurated) return true;

    final name = rawName.trim();
    if (name.isEmpty) return false;

    final lower = name.toLowerCase();

    // Check if rescued by explicit musical ensemble terms
    final hasEnsembleRescue = _musicalEnsembleExceptionPattern.hasMatch(lower);

    // 1. Educational institutions check
    if (_educationalPattern.hasMatch(lower) && !hasEnsembleRescue) {
      return false;
    }

    // 2. Sports clubs and teams check
    if (_sportsPattern.hasMatch(lower)) {
      return false;
    }

    // 3. Commercial businesses and vocational training check
    if (_commercialPattern.hasMatch(lower)) {
      return false;
    }

    // 4. Radio and broadcast aggregators check
    if (_radioBroadcastPattern.hasMatch(lower)) {
      return false;
    }

    // 5. Hobby / gaming / fan alliances check
    if (_hobbyAlliancePattern.hasMatch(lower) && !hasEnsembleRescue) {
      return false;
    }

    // 6. Vibe aggregator channels check
    if (_vibeAggregatorPattern.hasMatch(lower) && !hasEnsembleRescue) {
      return false;
    }

    return true;
  }
}

