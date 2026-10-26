import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:Miee/core/audio/audio_handler.dart';

class FakeAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  double _vol = 1.0;
  final List<double> volumeSteps = [];
  bool pauseCalled = false;

  FakeAudioPlayer({bool playing = true, double initialVolume = 1.0})
      : _isPlaying = playing,
        _vol = initialVolume,
        super(handleInterruptions: false);

  @override
  bool get playing => _isPlaying;

  @override
  double get volume => _vol;

  @override
  Future<void> setVolume(double volume) async {
    _vol = volume;
    volumeSteps.add(volume);
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    pauseCalled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio Fade-Out Tests', () {
    test('fadeOutAndPause steps volume down and pauses player', () async {
      final fakePlayer = FakeAudioPlayer(playing: true, initialVolume: 1.0);
      final handler = MieeAudioHandler(player: fakePlayer);

      expect(handler.isPlaying, isTrue);

      await handler.fadeOutAndPause(
        duration: const Duration(milliseconds: 60),
      );

      // Volume was stepped down
      expect(fakePlayer.volumeSteps, isNotEmpty);
      expect(fakePlayer.volumeSteps.first, lessThan(1.0));
      expect(fakePlayer.volumeSteps.contains(0.0), isTrue);

      // Pause was called
      expect(fakePlayer.pauseCalled, isTrue);

      // Volume restored to original volume so next track plays at full volume
      expect(fakePlayer.volume, equals(1.0));
    });

    test('fadeOutAndPause does nothing if player already paused', () async {
      final fakePlayer = FakeAudioPlayer(playing: false, initialVolume: 1.0);
      final handler = MieeAudioHandler(player: fakePlayer);

      await handler.fadeOutAndPause(
        duration: const Duration(milliseconds: 60),
      );

      expect(fakePlayer.volumeSteps, isEmpty);
    });
  });
}
