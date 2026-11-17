library;

/// Strongly-typed domain representations of entities returned by the
/// MusicBrainz Web Service v2 API (`https://musicbrainz.org/ws/2/`).

class MusicBrainzRecording {
  /// Canonical Recording MBID (UUID).
  final String mbid;

  /// Canonical recording title.
  final String title;

  /// Full artist credit formatted with join phrases (e.g. "Kendrick Lamar & SZA").
  final String artistCredit;

  /// Name of the primary performing artist.
  final String primaryArtist;

  /// MBID of the primary performing artist.
  final String? primaryArtistMbid;

  /// Featured or collaborating artists if present.
  final List<String> featuredArtists;

  /// Primary release / album title if present.
  final String? albumTitle;

  /// Release MBID of the primary release.
  final String? releaseMbid;

  /// Release Group MBID of the primary release group.
  final String? releaseGroupMbid;

  /// Track length in milliseconds if known.
  final int? durationMs;

  /// International Standard Recording Code (ISRC) if present.
  final String? isrc;

  /// Lucene match score (0-100).
  final int score;

  /// Resolved Cover Art Archive URL if retrieved.
  final String? frontCoverUrl;

  /// Associated releases.
  final List<MusicBrainzRelease> releases;

  const MusicBrainzRecording({
    required this.mbid,
    required this.title,
    required this.artistCredit,
    required this.primaryArtist,
    this.primaryArtistMbid,
    this.featuredArtists = const [],
    this.albumTitle,
    this.releaseMbid,
    this.releaseGroupMbid,
    this.durationMs,
    this.isrc,
    this.score = 0,
    this.frontCoverUrl,
    this.releases = const [],
  });

  /// Factory deserializer from MusicBrainz JSON recording object.
  factory MusicBrainzRecording.fromJson(Map<String, dynamic> json) {
    final mbid = (json['id'] ?? '').toString();
    final title = (json['title'] ?? '').toString().trim();
    final score = (json['score'] is num) ? (json['score'] as num).toInt() : 0;
    final length = (json['length'] is num) ? (json['length'] as num).toInt() : null;

    // Parse artist-credit array
    final rawCredits = json['artist-credit'] as List<dynamic>? ?? const [];
    final creditBuffer = StringBuffer();
    String primaryArtist = '';
    String? primaryArtistMbid;
    final featuredArtists = <String>[];

    for (var i = 0; i < rawCredits.length; i++) {
      final c = rawCredits[i];
      if (c is Map) {
        final artistName = (c['name'] ?? '').toString().trim();
        final joinPhrase = (c['joinphrase'] ?? '').toString();
        final artistObj = c['artist'] as Map<String, dynamic>?;
        final aId = (artistObj != null ? artistObj['id'] : null)?.toString();

        if (i == 0) {
          primaryArtist = artistName;
          primaryArtistMbid = aId;
        } else if (artistName.isNotEmpty && artistName != primaryArtist) {
          featuredArtists.add(artistName);
        }

        creditBuffer.write(artistName);
        creditBuffer.write(joinPhrase);
      } else if (c is String) {
        creditBuffer.write(c);
      }
    }

    final fullCredit = creditBuffer.toString().trim();
    final resolvedCredit = fullCredit.isNotEmpty ? fullCredit : (primaryArtist.isNotEmpty ? primaryArtist : 'Unknown Artist');

    // Parse releases
    final rawReleases = json['releases'] as List<dynamic>? ?? const [];
    final releases = <MusicBrainzRelease>[];
    String? albumTitle;
    String? releaseMbid;
    String? releaseGroupMbid;

    for (final r in rawReleases) {
      if (r is Map) {
        final release = MusicBrainzRelease.fromJson(Map<String, dynamic>.from(r));
        releases.add(release);
        if (albumTitle == null && release.title.isNotEmpty) {
          albumTitle = release.title;
          releaseMbid = release.mbid;
          releaseGroupMbid = release.releaseGroupMbid;
        }
      }
    }

    // Parse ISRCs
    String? isrc;
    final rawIsrcs = json['isrcs'] as List<dynamic>?;
    if (rawIsrcs != null && rawIsrcs.isNotEmpty) {
      isrc = rawIsrcs.first.toString().trim();
    }

    return MusicBrainzRecording(
      mbid: mbid,
      title: title,
      artistCredit: resolvedCredit,
      primaryArtist: primaryArtist.isNotEmpty ? primaryArtist : resolvedCredit,
      primaryArtistMbid: primaryArtistMbid,
      featuredArtists: featuredArtists,
      albumTitle: albumTitle,
      releaseMbid: releaseMbid,
      releaseGroupMbid: releaseGroupMbid,
      durationMs: length,
      isrc: isrc,
      score: score,
      releases: releases,
    );
  }

  /// Clean display duration in "m:ss" format.
  String get formattedDuration {
    if (durationMs == null || durationMs! <= 0) return '0:00';
    final totalSeconds = durationMs! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Front cover art URL candidates from Cover Art Archive.
  String? get coverArtArchiveUrl {
    if (releaseMbid != null && releaseMbid!.isNotEmpty) {
      return 'https://coverartarchive.org/release/$releaseMbid/front-500';
    }
    if (releaseGroupMbid != null && releaseGroupMbid!.isNotEmpty) {
      return 'https://coverartarchive.org/release-group/$releaseGroupMbid/front-500';
    }
    return null;
  }

  MusicBrainzRecording copyWith({
    String? mbid,
    String? title,
    String? artistCredit,
    String? primaryArtist,
    String? primaryArtistMbid,
    List<String>? featuredArtists,
    String? albumTitle,
    String? releaseMbid,
    String? releaseGroupMbid,
    int? durationMs,
    String? isrc,
    int? score,
    String? frontCoverUrl,
    List<MusicBrainzRelease>? releases,
  }) {
    return MusicBrainzRecording(
      mbid: mbid ?? this.mbid,
      title: title ?? this.title,
      artistCredit: artistCredit ?? this.artistCredit,
      primaryArtist: primaryArtist ?? this.primaryArtist,
      primaryArtistMbid: primaryArtistMbid ?? this.primaryArtistMbid,
      featuredArtists: featuredArtists ?? this.featuredArtists,
      albumTitle: albumTitle ?? this.albumTitle,
      releaseMbid: releaseMbid ?? this.releaseMbid,
      releaseGroupMbid: releaseGroupMbid ?? this.releaseGroupMbid,
      durationMs: durationMs ?? this.durationMs,
      isrc: isrc ?? this.isrc,
      score: score ?? this.score,
      frontCoverUrl: frontCoverUrl ?? this.frontCoverUrl,
      releases: releases ?? this.releases,
    );
  }
}

class MusicBrainzRelease {
  final String mbid;
  final String title;
  final String? releaseGroupMbid;
  final String? releaseDate;
  final String? country;
  final String? status;

  const MusicBrainzRelease({
    required this.mbid,
    required this.title,
    this.releaseGroupMbid,
    this.releaseDate,
    this.country,
    this.status,
  });

  factory MusicBrainzRelease.fromJson(Map<String, dynamic> json) {
    final mbid = (json['id'] ?? '').toString();
    final title = (json['title'] ?? '').toString().trim();
    final date = json['date']?.toString().trim();
    final country = json['country']?.toString().trim();
    final status = json['status']?.toString().trim();

    String? rgId;
    final rg = json['release-group'] as Map<String, dynamic>?;
    if (rg != null) {
      rgId = rg['id']?.toString().trim();
    }

    return MusicBrainzRelease(
      mbid: mbid,
      title: title,
      releaseGroupMbid: rgId,
      releaseDate: date,
      country: country,
      status: status,
    );
  }
}

class MusicBrainzArtist {
  final String mbid;
  final String name;
  final String? sortName;
  final String? type;
  final String? country;
  final String? disambiguation;
  final List<String> genres;
  final int score;

  const MusicBrainzArtist({
    required this.mbid,
    required this.name,
    this.sortName,
    this.type,
    this.country,
    this.disambiguation,
    this.genres = const [],
    this.score = 0,
  });

  factory MusicBrainzArtist.fromJson(Map<String, dynamic> json) {
    final mbid = (json['id'] ?? '').toString();
    final name = (json['name'] ?? '').toString().trim();
    final sortName = json['sort-name']?.toString().trim();
    final type = json['type']?.toString().trim();
    final country = json['country']?.toString().trim();
    final disambiguation = json['disambiguation']?.toString().trim();
    final score = (json['score'] is num) ? (json['score'] as num).toInt() : 0;

    final genres = <String>[];
    final tags = json['tags'] as List<dynamic>? ?? const [];
    for (final t in tags) {
      if (t is Map && t['name'] != null) {
        genres.add(t['name'].toString().trim());
      }
    }

    return MusicBrainzArtist(
      mbid: mbid,
      name: name,
      sortName: sortName,
      type: type,
      country: country,
      disambiguation: disambiguation,
      genres: genres,
      score: score,
    );
  }
}
