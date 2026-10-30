import 'package:flutter/foundation.dart';
import 'music_item.dart';

/// Model representing a music track.
class Track implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String imageUrl;
  @override
  final String duration;
  
  final String? localFilePath;
  final double progress;
  final bool isPlaying;
  final bool isFavorited;

  /// Original source title preserved for diagnostics and parser debugging.
  final String? rawTitle;

  /// Original source artist / author preserved for diagnostics.
  final String? rawArtist;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.duration,
    String? filePath,
    this.progress = 0.0,
    this.isPlaying = false,
    this.isFavorited = false,
    this.rawTitle,
    this.rawArtist,
  }) : localFilePath = filePath;

  @override
  String get filePath => localFilePath ?? '';

  @override
  bool get isYoutube =>
      kIsWeb ||
      id.startsWith('youtube_') ||
      id.startsWith('wm_') ||
      RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id) ||
      (localFilePath?.contains('youtube.com') ?? false) ||
      (localFilePath?.startsWith('http') ?? false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

