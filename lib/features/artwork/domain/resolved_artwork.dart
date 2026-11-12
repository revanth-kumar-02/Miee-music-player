import 'artwork_source.dart';

/// Represents a validated, deterministic artwork resolution outcome in Miee.
class ResolvedArtwork {
  /// The local file path or remote HTTP(S) image URL.
  final String imageUrl;

  /// The provider or source that supplied this artwork.
  final ArtworkSource source;

  /// Match confidence score from 0.0 (no confidence / fallback) to 1.0 (exact match / local).
  final double confidence;

  /// Source attribution string (e.g. "Cover Art Archive / MusicBrainz", "Deezer").
  final String? attribution;

  /// Image dimensions if known.
  final int? width;
  final int? height;

  /// Indicates whether the artwork refers to a local file on device storage.
  final bool isLocal;

  /// Validated local disk cache file path for remote artwork (when downloaded).
  final String? localCachedPath;

  /// MusicBrainz Release MBID if resolved via MB / Cover Art Archive.
  final String? mbid;

  /// Timestamp when this artwork was resolved.
  final DateTime? resolvedAt;

  const ResolvedArtwork({
    required this.imageUrl,
    required this.source,
    required this.confidence,
    this.attribution,
    this.width,
    this.height,
    this.isLocal = false,
    this.localCachedPath,
    this.mbid,
    this.resolvedAt,
  });

  ResolvedArtwork copyWith({
    String? imageUrl,
    ArtworkSource? source,
    double? confidence,
    String? attribution,
    int? width,
    int? height,
    bool? isLocal,
    String? localCachedPath,
    String? mbid,
    DateTime? resolvedAt,
  }) {
    return ResolvedArtwork(
      imageUrl: imageUrl ?? this.imageUrl,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      attribution: attribution ?? this.attribution,
      width: width ?? this.width,
      height: height ?? this.height,
      isLocal: isLocal ?? this.isLocal,
      localCachedPath: localCachedPath ?? this.localCachedPath,
      mbid: mbid ?? this.mbid,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  /// Convenient factory for neutral fallback when resolution fails across all providers.
  factory ResolvedArtwork.neutralFallback({String? fallbackUrl}) {
    return ResolvedArtwork(
      imageUrl: fallbackUrl ?? '',
      source: ArtworkSource.neutralFallback,
      confidence: 0.0,
      attribution: 'Miee System',
      isLocal: false,
      resolvedAt: DateTime.now(),
    );
  }

  bool get isNeutralFallback => source == ArtworkSource.neutralFallback || imageUrl.isEmpty;

  Map<String, dynamic> toJson() => {
        'imageUrl': imageUrl,
        'source': source.name,
        'confidence': confidence,
        'attribution': attribution,
        'width': width,
        'height': height,
        'isLocal': isLocal,
        'localCachedPath': localCachedPath,
        'mbid': mbid,
        'resolvedAt': resolvedAt?.millisecondsSinceEpoch,
      };

  factory ResolvedArtwork.fromJson(Map<String, dynamic> json) {
    return ResolvedArtwork(
      imageUrl: json['imageUrl'] as String? ?? '',
      source: ArtworkSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => ArtworkSource.neutralFallback,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      attribution: json['attribution'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      isLocal: json['isLocal'] as bool? ?? false,
      localCachedPath: json['localCachedPath'] as String?,
      mbid: json['mbid'] as String?,
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['resolvedAt'] as int)
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedArtwork &&
          runtimeType == other.runtimeType &&
          imageUrl == other.imageUrl &&
          source == other.source &&
          confidence == other.confidence;

  @override
  int get hashCode => imageUrl.hashCode ^ source.hashCode ^ confidence.hashCode;

  @override
  String toString() =>
      'ResolvedArtwork(url: $imageUrl, source: ${source.name}, confidence: $confidence)';
}
