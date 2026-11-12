import 'package:flutter_test/flutter_test.dart';

import 'package:Miee/features/media/domain/library_filter_policy.dart';
import 'package:Miee/features/media/domain/media_repository.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';

class _FakeMediaRepository implements MediaRepository {
  LibraryFolderPreferences prefs = const LibraryFolderPreferences();
  final List<({MediaSong song, bool? isMusic})> deviceAudio;

  int scanCalls = 0;

  _FakeMediaRepository({
    required this.deviceAudio,
  });

  final AudioLibraryFilter _filter = const AudioLibraryFilter();

  @override
  Future<bool> checkAndRequestPermissions() async => true;

  @override
  Future<LibraryFolderPreferences> getFolderPreferences() async => prefs;

  @override
  Future<void> saveFolderPreferences(
      LibraryFolderPreferences preferences) async {
    prefs = preferences;
  }

  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async {
    scanCalls++;
    return deviceAudio
        .where((item) => _filter.shouldIncludeAudio(
              filePath: item.song.filePath,
              isMusic: item.isMusic,
              durationMs: item.song.durationMs,
              artist: item.song.artist,
              preferences: prefs,
            ))
        .map((e) => e.song)
        .toList();
  }

  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async =>
      const [];
}

void main() {
  const filter = AudioLibraryFilter();

  group('AudioLibraryFilter & Folder Preferences', () {
    test('1. Ordinary music in Music/ is included', () {
      expect(
        filter.shouldIncludeAudio(
          filePath: '/storage/emulated/0/Music/Adele/Hello.mp3',
          isMusic: true,
          durationMs: 295000,
          artist: 'Adele',
        ),
        isTrue,
      );
    });

    test('2. Legitimate music in custom folder is preserved (even when isMusic is null)',
        () {
      expect(
        filter.shouldIncludeAudio(
          filePath: '/storage/emulated/0/MyFLACs/PinkFloyd/Time.flac',
          isMusic: null,
          durationMs: 413000,
          artist: 'Pink Floyd',
        ),
        isTrue,
      );
    });

    test('3. MP3 call recording in OEM call-recording folders is excluded by default',
        () {
      for (final path in [
        '/storage/emulated/0/CallRecordings/Mom_1234.mp3',
        '/storage/emulated/0/Recordings/Call/Call_2026.mp3',
        '/storage/emulated/0/MIUI/sound_recorder/call_rec/call_101.mp3',
        '/storage/emulated/0/PhoneRecord/20261112.mp3',
        '/storage/emulated/0/Sounds/CallRecordings/work_call.mp3',
      ]) {
        expect(
          filter.shouldIncludeAudio(
            filePath: path,
            isMusic: true,
            durationMs: 180000,
            artist: 'Phone Call',
          ),
          isFalse,
          reason: 'Expected call recording path to be excluded: $path',
        );
      }
    });

    test('4. M4A call recording is excluded by default', () {
      expect(
        filter.shouldIncludeAudio(
          filePath: '/storage/emulated/0/Recordings/CallRecordings/client.m4a',
          isMusic: false,
          durationMs: 240000,
          artist: 'Unknown Caller',
        ),
        isFalse,
      );
    });

    test('5. Voice recordings and messaging audio notes are excluded by default',
        () {
      for (final path in [
        '/storage/emulated/0/Voice Recorder/Memo_01.m4a',
        '/storage/emulated/0/Recordings/Voice_002.wav',
        '/storage/emulated/0/Sounds/Recordings/Lecture.aac',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/PTT-001.opus',
        '/storage/emulated/0/Android/data/com.example/cache/temp_clip.mp3',
      ]) {
        expect(
          filter.shouldIncludeAudio(
            filePath: path,
            isMusic: true,
            durationMs: 120000,
            artist: 'Recorder',
          ),
          isFalse,
          reason: 'Expected voice/cache path to be excluded: $path',
        );
      }
    });

    test('6. Manually included folder overrides default recording exclusion', () {
      const prefs = LibraryFolderPreferences(
        includedFolders: {'/storage/emulated/0/recordings'},
      );
      expect(
        filter.shouldIncludeAudio(
          filePath: '/storage/emulated/0/Recordings/AcousticJam.mp3',
          durationMs: 200000,
          artist: 'Me',
          preferences: prefs,
        ),
        isTrue,
      );
    });

    test('7. Manually excluded folder hides tracks even in Music/', () {
      const prefs = LibraryFolderPreferences(
        excludedFolders: {'/storage/emulated/0/music/podcasts'},
      );
      expect(
        filter.shouldIncludeAudio(
          filePath: '/storage/emulated/0/Music/Podcasts/Episode1.mp3',
          isMusic: true,
          durationMs: 1800000,
          artist: 'Host',
          preferences: prefs,
        ),
        isFalse,
      );
    });

    test('8 & 9. MediaLibraryService rescans after folder preference changes while preserving music',
        () async {
      final repo = _FakeMediaRepository(
        deviceAudio: [
          (
            song: const MediaSong(
              id: '1',
              title: 'Real Song',
              artist: 'Artist',
              album: 'Album',
              duration: '3:30',
              durationMs: 210000,
              filePath: '/storage/emulated/0/Music/RealSong.mp3',
              artworkPath: '',
            ),
            isMusic: true,
          ),
          (
            song: const MediaSong(
              id: '2',
              title: 'Custom Folder Song',
              artist: 'Indie',
              album: 'Custom',
              duration: '4:00',
              durationMs: 240000,
              filePath: '/storage/emulated/0/CustomMusic/Track.mp3',
              artworkPath: '',
            ),
            isMusic: null,
          ),
          (
            song: const MediaSong(
              id: '3',
              title: 'Call Recording',
              artist: 'Dialer',
              album: 'Calls',
              duration: '2:00',
              durationMs: 120000,
              filePath: '/storage/emulated/0/Recordings/CallRec.m4a',
              artworkPath: '',
            ),
            isMusic: false,
          ),
        ],
      );

      final service = MediaLibraryService(repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Initially: Real Song + Custom Folder Song included; Call Recording excluded.
      expect(service.state.songs.map((s) => s.id).toList(), ['1', '2']);

      // User manually includes Recordings -> rescan includes track 3.
      await service.includeFolder('/storage/emulated/0/Recordings');
      expect(service.state.songs.map((s) => s.id).toList(), ['1', '2', '3']);

      // User manually excludes CustomMusic -> rescan excludes track 2 while keeping 1 & 3.
      await service.excludeFolder('/storage/emulated/0/CustomMusic');
      expect(service.state.songs.map((s) => s.id).toList(), ['1', '3']);

      service.dispose();
    });
  });
}
