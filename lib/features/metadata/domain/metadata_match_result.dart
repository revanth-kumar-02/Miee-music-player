import 'itunes_song.dart';

/// Represents the evaluated outcome of matching a music track candidate against
/// the Apple iTunes catalogue.
class MetadataMatchResult {
  /// Whether the match surpasses the strict confidence threshold (>= 0.80)
  /// and can safely replace raw video metadata.
  final bool isConfident;

  /// Confidence score between 0.0 (no confidence / incompatible version) and 1.0 (exact match).
  final double confidence;

  /// The matched iTunes song entry if confident or candidate exists.
  final ItunesSong? itunesSong;

  /// Descriptive diagnostic reason if match was rejected or fell back.
  final String? diagnosticReason;

  const MetadataMatchResult({
    required this.isConfident,
    required this.confidence,
    this.itunesSong,
    this.diagnosticReason,
  });

  /// Factory for a rejected or unconfident candidate match.
  factory MetadataMatchResult.unconfident({
    double confidence = 0.0,
    String? reason,
    ItunesSong? candidate,
  }) {
    return MetadataMatchResult(
      isConfident: false,
      confidence: confidence,
      itunesSong: candidate,
      diagnosticReason: reason ?? 'Confidence score below threshold (0.80)',
    );
  }

  /// Factory for an empty result (no candidates returned by provider).
  factory MetadataMatchResult.noMatch([String reason = 'No candidates returned from iTunes']) {
    return MetadataMatchResult(
      isConfident: false,
      confidence: 0.0,
      itunesSong: null,
      diagnosticReason: reason,
    );
  }

  /// Canonical song title if confidently matched.
  String? get canonicalTitle => isConfident ? itunesSong?.trackName : null;

  /// Canonical artist name if confidently matched.
  String? get canonicalArtist => isConfident ? itunesSong?.artistName : null;

  /// Canonical album collection name if confidently matched.
  String? get albumName => isConfident ? itunesSong?.collectionName : null;

  /// High-resolution artwork URL (`600x600bb.jpg`) if confidently matched.
  String? get highResArtworkUrl => isConfident ? itunesSong?.highResArtworkUrl : null;

  /// Ultra-resolution artwork URL (`1000x1000bb.jpg`) if confidently matched.
  String? get ultraResArtworkUrl => isConfident ? itunesSong?.ultraResArtworkUrl : null;

  /// Canonical iTunes track ID string.
  String? get trackId => itunesSong?.trackId.toString();

  @override
  String toString() =>
      'MetadataMatchResult(confident: $isConfident, score: ${confidence.toStringAsFixed(2)}, song: ${itunesSong?.trackName}, reason: $diagnosticReason)';
}
