import '../utils/display_title_normalizer.dart';

/// Unified abstraction representing a playable track/music item in Miee.
/// Both local offline songs and online YouTube tracks inherit from this interface.
abstract class MusicItem {
  String get id;
  String get title;
  String get artist;
  String get imageUrl;
  String get duration;
  String get filePath;
  bool get isYoutube;

  /// Optional album name if known.
  String? get album => null;

  /// Clean, human-friendly song display title for user interfaces.
  String get displayTitle => DisplayTitleNormalizer.normalize(title);

  /// Returns the prioritized artwork source for this item.
  String get effectiveArtworkUrl => imageUrl;
}
