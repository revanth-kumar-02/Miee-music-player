/// Summary of an artist stored inside the user's profile and preferences.
class ArtistSummary {
  final String id;
  final String name;
  final String imageUrl;
  final List<String> languages;

  const ArtistSummary({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.languages = const [],
  });

  factory ArtistSummary.fromMap(Map<String, dynamic> map) {
    final rawLangs = map['languages'] as List<dynamic>? ?? [];
    return ArtistSummary(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown Artist',
      imageUrl: map['imageUrl'] as String? ?? '',
      languages: rawLangs.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      if (languages.isNotEmpty) 'languages': languages,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistSummary && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Detailed artist entity returned by discovery and search.
class ArtistModel {
  final String id;
  final String name;
  final String imageUrl;
  final int fanCount;
  final List<String> genres;
  final List<String> languages;

  const ArtistModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.fanCount = 0,
    this.genres = const [],
    this.languages = const [],
  });

  ArtistModel copyWith({
    String? id,
    String? name,
    String? imageUrl,
    int? fanCount,
    List<String>? genres,
    List<String>? languages,
  }) {
    return ArtistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      fanCount: fanCount ?? this.fanCount,
      genres: genres ?? this.genres,
      languages: languages ?? this.languages,
    );
  }

  bool matchesLanguage(String language) {
    if (language.toLowerCase() == 'all') return true;
    return languages.any((l) => l.toLowerCase() == language.toLowerCase());
  }

  bool get hasValidImage {
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) return false;
    if (imageUrl.contains('d41d8cd98f00b204e9800998ecf8427e')) return false;
    if (imageUrl.contains('/artist//')) return false;
    return true;
  }

  ArtistSummary toSummary() => ArtistSummary(
        id: id,
        name: name,
        imageUrl: imageUrl,
        languages: languages,
      );

  factory ArtistModel.fromDeezer(
    Map<String, dynamic> json, {
    List<String> languages = const [],
  }) {
    final id = (json['id'] ?? '').toString();
    final name = json['name'] as String? ?? 'Unknown Artist';
    String img = json['picture_big'] as String? ?? '';
    if (img.isEmpty) img = json['picture_medium'] as String? ?? '';
    if (img.isEmpty) img = json['picture'] as String? ?? '';

    if (img.contains('d41d8cd98f00b204e9800998ecf8427e') || img.contains('/artist//')) {
      img = '';
    }

    return ArtistModel(
      id: id,
      name: name,
      imageUrl: img,
      fanCount: (json['nb_fan'] as num?)?.toInt() ?? 0,
      languages: languages,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
