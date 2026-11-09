/// Strongly-typed domain representation of a song entry returned by
/// the Apple iTunes Search API (`https://itunes.apple.com/search`).
class ItunesSong {
  /// Unique persistent iTunes track identifier.
  final int trackId;

  /// Canonical song title according to Apple Music / iTunes catalogue.
  final String trackName;

  /// Primary artist or performing artist name.
  final String artistName;

  /// Album / Collection name if present.
  final String? collectionName;

  /// Original 100x100 thumbnail URL provided by iTunes.
  final String artworkUrl100;

  /// Track duration in milliseconds if known.
  final int? trackTimeMillis;

  /// Primary genre category (e.g. "Tamil", "Pop", "Soundtrack").
  final String? primaryGenreName;

  /// ISO-8601 release date string.
  final String? releaseDate;

  /// International Standard Recording Code if present.
  final String? isrc;

  const ItunesSong({
    required this.trackId,
    required this.trackName,
    required this.artistName,
    this.collectionName,
    required this.artworkUrl100,
    this.trackTimeMillis,
    this.primaryGenreName,
    this.releaseDate,
    this.isrc,
  });

  /// Factory deserializer resilient to nulls, missing keys, and varied types.
  factory ItunesSong.fromJson(Map<String, dynamic> json) {
    final rawTrackId = json['trackId'];
    final int parsedId;
    if (rawTrackId is int) {
      parsedId = rawTrackId;
    } else if (rawTrackId is String) {
      parsedId = int.tryParse(rawTrackId) ?? 0;
    } else {
      parsedId = 0;
    }

    final rawDuration = json['trackTimeMillis'];
    final int? parsedDuration = rawDuration is int
        ? rawDuration
        : (rawDuration is num ? rawDuration.toInt() : null);

    return ItunesSong(
      trackId: parsedId,
      trackName: (json['trackName'] ?? json['trackCensoredName'] ?? '').toString().trim(),
      artistName: (json['artistName'] ?? '').toString().trim(),
      collectionName: json['collectionName']?.toString().trim(),
      artworkUrl100: (json['artworkUrl100'] ?? json['artworkUrl60'] ?? '').toString().trim(),
      trackTimeMillis: parsedDuration,
      primaryGenreName: json['primaryGenreName']?.toString().trim(),
      releaseDate: json['releaseDate']?.toString().trim(),
      isrc: json['isrc']?.toString().trim(),
    );
  }

  /// Upgraded high-resolution studio artwork URL (`600x600bb.jpg`).
  ///
  /// Replaces the default `100x100bb` dimension with `600x600bb` on Apple's
  /// mzstatic CDN to deliver crisp album art on high-DPI displays.
  String get highResArtworkUrl {
    if (artworkUrl100.isEmpty) return '';
    return artworkUrl100
        .replaceAll('100x100bb', '600x600bb')
        .replaceAll('60x60bb', '600x600bb');
  }

  /// Upgraded ultra-high-resolution studio artwork URL (`1000x1000bb.jpg`).
  String get ultraResArtworkUrl {
    if (artworkUrl100.isEmpty) return '';
    return artworkUrl100
        .replaceAll('100x100bb', '1000x1000bb')
        .replaceAll('60x60bb', '1000x1000bb');
  }

  /// Duration converted to standard Dart [Duration] object.
  Duration? get duration =>
      trackTimeMillis != null ? Duration(milliseconds: trackTimeMillis!) : null;

  /// Clean display duration in "mm:ss" format.
  String get formattedDuration {
    if (trackTimeMillis == null) return '0:00';
    final totalSeconds = trackTimeMillis! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'trackName': trackName,
        'artistName': artistName,
        'collectionName': collectionName,
        'artworkUrl100': artworkUrl100,
        'trackTimeMillis': trackTimeMillis,
        'primaryGenreName': primaryGenreName,
        'releaseDate': releaseDate,
        'isrc': isrc,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItunesSong &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId;

  @override
  int get hashCode => trackId.hashCode;

  @override
  String toString() =>
      'ItunesSong(id: $trackId, name: "$trackName", artist: "$artistName", album: "$collectionName")';
}

