import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// Service wrapping the [AudioPlayer] instance from just_audio.
/// Exposes streams for position, duration, and buffering, and abstract playback actions.
class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayerService() {
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  /// Stream of current player position.
  Stream<Duration> get positionStream => _player.positionStream;

  /// Stream of current track duration.
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Stream of current buffered position.
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  /// Stream of processing and play states.
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Returns if player is currently playing.
  bool get isPlaying => _player.playing;

  /// Play current track source.
  Future<void> play() async => await _player.play();

  /// Pause current track playback.
  Future<void> pause() async => await _player.pause();

  /// Stop current playback.
  Future<void> stop() async => await _player.stop();

  /// Seek to target offset.
  Future<void> seek(Duration position) async => await _player.seek(position);

  /// Load track from either a web URL or a local file path source.
  Future<void> setSource(String path) async {
    try {
      if (path.startsWith('http')) {
        await _player.setUrl(path);
      } else {
        await _player.setAudioSource(AudioSource.file(path));
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Clean up player resources.
  Future<void> dispose() async => await _player.dispose();
}
