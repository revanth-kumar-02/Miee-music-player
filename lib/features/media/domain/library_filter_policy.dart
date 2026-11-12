/// User-configurable folder and category preferences for local audio scanning.
class LibraryFolderPreferences {
  final Set<String> includedFolders;
  final Set<String> excludedFolders;
  final bool excludeCallRecordings;
  final bool excludeVoiceRecordings;
  final bool excludeTempAndCache;

  const LibraryFolderPreferences({
    this.includedFolders = const {},
    this.excludedFolders = const {},
    this.excludeCallRecordings = true,
    this.excludeVoiceRecordings = true,
    this.excludeTempAndCache = true,
  });

  LibraryFolderPreferences copyWith({
    Set<String>? includedFolders,
    Set<String>? excludedFolders,
    bool? excludeCallRecordings,
    bool? excludeVoiceRecordings,
    bool? excludeTempAndCache,
  }) {
    return LibraryFolderPreferences(
      includedFolders: includedFolders ?? this.includedFolders,
      excludedFolders: excludedFolders ?? this.excludedFolders,
      excludeCallRecordings:
          excludeCallRecordings ?? this.excludeCallRecordings,
      excludeVoiceRecordings:
          excludeVoiceRecordings ?? this.excludeVoiceRecordings,
      excludeTempAndCache: excludeTempAndCache ?? this.excludeTempAndCache,
    );
  }

  Map<String, dynamic> toJson() => {
        'includedFolders': includedFolders.toList(),
        'excludedFolders': excludedFolders.toList(),
        'excludeCallRecordings': excludeCallRecordings,
        'excludeVoiceRecordings': excludeVoiceRecordings,
        'excludeTempAndCache': excludeTempAndCache,
      };

  factory LibraryFolderPreferences.fromJson(Map<dynamic, dynamic> json) {
    final included = (json['includedFolders'] as List?)
            ?.map((e) => normalizeFolderPath(e.toString()))
            .where((e) => e.isNotEmpty)
            .toSet() ??
        const <String>{};
    final excluded = (json['excludedFolders'] as List?)
            ?.map((e) => normalizeFolderPath(e.toString()))
            .where((e) => e.isNotEmpty)
            .toSet() ??
        const <String>{};
    return LibraryFolderPreferences(
      includedFolders: included,
      excludedFolders: excluded,
      excludeCallRecordings: json['excludeCallRecordings'] as bool? ?? true,
      excludeVoiceRecordings: json['excludeVoiceRecordings'] as bool? ?? true,
      excludeTempAndCache: json['excludeTempAndCache'] as bool? ?? true,
    );
  }

  static String normalizeFolderPath(String path) {
    var normalized = path.trim().replaceAll('\\', '/').toLowerCase();
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

/// Configurable filtering policy that separates legitimate music tracks from
/// call recordings, voice recorder memos, and temporary/cache audio files.
class AudioLibraryFilter {
  /// Directory segment or relative path patterns commonly used by OEM dialers
  /// and third-party call recorders across Android manufacturers.
  final List<String> callRecordingDirectoryPatterns;

  /// Directory segment or relative path patterns commonly used by built-in
  /// voice recorders and messaging apps' audio/voice-note folders.
  final List<String> voiceRecordingDirectoryPatterns;

  /// Temporary, cache, and app-internal directories that should never be
  /// indexed as user music.
  final List<String> tempAndCacheDirectoryPatterns;

  final int minDurationMs;

  const AudioLibraryFilter({
    this.callRecordingDirectoryPatterns = defaultCallRecordingPatterns,
    this.voiceRecordingDirectoryPatterns = defaultVoiceRecordingPatterns,
    this.tempAndCacheDirectoryPatterns = defaultTempAndCachePatterns,
    this.minDurationMs = 30000,
  });

  static const List<String> defaultCallRecordingPatterns = [
    'callrecordings',
    'call recording',
    'call recordings',
    'call_recordings',
    'call_recording',
    'callrec',
    'call_rec',
    'callrecord',
    'call_record',
    'phonerecord',
    'phone_record',
    'phone record',
    'sounds/callrecordings',
    'recordings/call',
    'miui/sound_recorder/call_rec',
    'record/call',
    'cube_call_recorder',
    'boldbeast',
    'acr',
  ];

  static const List<String> defaultVoiceRecordingPatterns = [
    'voicerecorder',
    'voice recorder',
    'voice_recorder',
    'soundrecorder',
    'sound_recorder',
    'sound recorder',
    'recordings',
    'sounds/recordings',
    'audiorecorder',
    'audio_recorder',
    'audio recorder',
    'voicenotes',
    'voice notes',
    'voice_notes',
    'whatsapp voice notes',
    'whatsapp audio',
    'telegram audio',
  ];

  static const List<String> defaultTempAndCachePatterns = [
    'cache',
    '.cache',
    'temp',
    'tmp',
    '.thumbnails',
    'android/data',
    'android/obb',
    'miee_preload_cache',
  ];

  /// Evaluates whether an audio item should appear in the user's music library.
  bool shouldIncludeAudio({
    required String filePath,
    bool? isMusic,
    bool? isNotification,
    bool? isAlarm,
    bool? isRingtone,
    int? durationMs,
    String? artist,
    LibraryFolderPreferences preferences = const LibraryFolderPreferences(),
  }) {
    if (filePath.trim().isEmpty) return false;
    if (isNotification == true || isAlarm == true || isRingtone == true) {
      return false;
    }
    if (durationMs != null && durationMs < minDurationMs) {
      return false;
    }
    if (artist != null && isUnknownArtist(artist)) {
      return false;
    }

    final normalizedFile =
        filePath.trim().replaceAll('\\', '/').toLowerCase();
    final parentFolder = _extractParentFolder(normalizedFile);

    // 1. User-excluded folders always win.
    if (_matchesAnyConfiguredFolder(parentFolder, preferences.excludedFolders)) {
      return false;
    }

    // 2. User-included folders explicitly override default recording exclusions.
    if (_matchesAnyConfiguredFolder(parentFolder, preferences.includedFolders)) {
      return true;
    }

    // 3. Exclude temp and cache directories.
    if (preferences.excludeTempAndCache &&
        _matchesAnyDirectoryPattern(
            parentFolder, tempAndCacheDirectoryPatterns)) {
      return false;
    }

    // 4. Exclude call-recording directories.
    if (preferences.excludeCallRecordings &&
        _matchesAnyDirectoryPattern(
            parentFolder, callRecordingDirectoryPatterns)) {
      return false;
    }

    // 5. Exclude voice-recorder and messaging recording directories.
    if (preferences.excludeVoiceRecordings &&
        _matchesAnyDirectoryPattern(
            parentFolder, voiceRecordingDirectoryPatterns)) {
      return false;
    }

    // 6. If Android MediaStore explicitly flagged isMusic == false AND the file
    // lives in a generic system sound folder (notifications/alarms/ringtones),
    // exclude it while preserving legitimate songs in custom folders where
    // MediaStore's isMusic flag can be unreliable/null.
    if (isMusic == false &&
        _matchesAnyDirectoryPattern(parentFolder, const [
          'notifications',
          'alarms',
          'ringtones',
        ])) {
      return false;
    }

    return true;
  }

  static bool isUnknownArtist(String? artist) {
    if (artist == null) return true;
    final trimmed = artist.trim().toLowerCase();
    return trimmed.isEmpty || trimmed == '<unknown>' || trimmed == 'unknown';
  }

  static String _extractParentFolder(String normalizedFilePath) {
    final idx = normalizedFilePath.lastIndexOf('/');
    if (idx <= 0) return '';
    return normalizedFilePath.substring(0, idx);
  }

  static bool _matchesAnyConfiguredFolder(
    String parentFolder,
    Set<String> configuredFolders,
  ) {
    if (parentFolder.isEmpty || configuredFolders.isEmpty) return false;
    for (final raw in configuredFolders) {
      final folder = LibraryFolderPreferences.normalizeFolderPath(raw);
      if (folder.isEmpty) continue;
      if (parentFolder == folder || parentFolder.startsWith('$folder/')) {
        return true;
      }
    }
    return false;
  }

  static bool _matchesAnyDirectoryPattern(
    String parentFolder,
    List<String> patterns,
  ) {
    if (parentFolder.isEmpty) return false;
    final segments =
        parentFolder.split('/').where((s) => s.isNotEmpty).toList();

    for (final rawPattern in patterns) {
      final pattern = rawPattern.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      if (pattern.contains('/')) {
        if (parentFolder.endsWith('/$pattern') ||
            parentFolder == pattern ||
            parentFolder.contains('/$pattern/')) {
          return true;
        }
      } else {
        if (segments.contains(pattern)) {
          return true;
        }
      }
    }
    return false;
  }
}

