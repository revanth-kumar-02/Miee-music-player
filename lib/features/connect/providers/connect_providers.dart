import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/track.dart';
import '../data/connect_service.dart';
import '../domain/connect_device.dart';

class ConnectState {
  final ConnectDevice currentDevice;
  final ConnectDevice activeDevice;
  final List<ConnectDevice> availableDevices;
  final bool isScanning;
  final double remoteVolume;

  const ConnectState({
    required this.currentDevice,
    required this.activeDevice,
    this.availableDevices = const [],
    this.isScanning = false,
    this.remoteVolume = 1.0,
  });

  bool get isRemote => activeDevice.id != currentDevice.id;

  ConnectState copyWith({
    ConnectDevice? currentDevice,
    ConnectDevice? activeDevice,
    List<ConnectDevice>? availableDevices,
    bool? isScanning,
    double? remoteVolume,
  }) {
    return ConnectState(
      currentDevice: currentDevice ?? this.currentDevice,
      activeDevice: activeDevice ?? this.activeDevice,
      availableDevices: availableDevices ?? this.availableDevices,
      isScanning: isScanning ?? this.isScanning,
      remoteVolume: remoteVolume ?? this.remoteVolume,
    );
  }
}

class ConnectNotifier extends StateNotifier<ConnectState> {
  final Ref _ref;
  final ConnectService _service = ConnectService();

  ConnectNotifier(this._ref)
      : super(
          ConnectState(
            currentDevice: ConnectService().currentDevice,
            activeDevice: ConnectService().currentDevice,
          ),
        ) {
    _init();
  }

  Future<void> _init() async {
    await _service.initialize();
    state = state.copyWith(
      currentDevice: _service.currentDevice,
      activeDevice: _service.currentDevice,
      availableDevices: [_service.currentDevice],
    );

    _service.devicesStream.listen((devices) {
      state = state.copyWith(availableDevices: devices);
    });

    _service.onCommandReceived = _handleIncomingCommand;
  }

  void _handleIncomingCommand(ConnectCommand cmd) {
    final player = _ref.read(playerControllerProvider.notifier);
    switch (cmd.action) {
      case 'play':
        if (cmd.trackData != null) {
          final track = Track(
            id: cmd.trackData!['id'] as String? ?? 'track',
            title: cmd.trackData!['title'] as String? ?? 'Song',
            artist: cmd.trackData!['artist'] as String? ?? 'Artist',
            imageUrl: cmd.trackData!['image_url'] as String? ?? '',
            duration: cmd.trackData!['duration'] as String? ?? '03:00',
            filePath: cmd.trackData!['file_path'] as String?,
          );
          final pos = cmd.positionMs != null
              ? Duration(milliseconds: cmd.positionMs!)
              : null;
          player.playTrack(track, initialPosition: pos);
        } else {
          player.play();
        }
        break;
      case 'pause':
        player.pause();
        break;
      case 'seek':
        if (cmd.positionMs != null) {
          player.seek(Duration(milliseconds: cmd.positionMs!));
        }
        break;
      case 'volume':
        if (cmd.volume != null) {
          _ref.read(audioHandlerProvider).setVolume(cmd.volume!);
        }
        break;
      case 'next':
        player.next();
        break;
      case 'previous':
        player.previous();
        break;
    }
  }

  Future<void> selectDevice(ConnectDevice device) async {
    if (device.id == state.currentDevice.id) {
      // Return to playing on this local device
      state = state.copyWith(activeDevice: state.currentDevice);
      return;
    }

    // Switch active target to the remote device
    final playback = _ref.read(playerControllerProvider);
    final curTrack = playback.currentTrack;
    final curPos = playback.position;

    // Pause audio on this local phone
    await _ref.read(playerControllerProvider.notifier).pause();

    state = state.copyWith(
      activeDevice: device,
      remoteVolume: device.volume,
    );

    // Send transfer command to the remote device
    if (curTrack != null) {
      await _service.sendCommand(
        ConnectCommand(
          action: 'play',
          targetDeviceId: device.id,
          senderDeviceId: state.currentDevice.id,
          trackData: {
            'id': curTrack.id,
            'title': curTrack.title,
            'artist': curTrack.artist,
            'image_url': curTrack.imageUrl,
            'duration': curTrack.duration,
            'file_path': curTrack.filePath,
          },
          positionMs: curPos.inMilliseconds,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> remotePlay() async {
    if (!state.isRemote) return;
    await _service.sendCommand(
      ConnectCommand(
        action: 'play',
        targetDeviceId: state.activeDevice.id,
        senderDeviceId: state.currentDevice.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> remotePause() async {
    if (!state.isRemote) return;
    await _service.sendCommand(
      ConnectCommand(
        action: 'pause',
        targetDeviceId: state.activeDevice.id,
        senderDeviceId: state.currentDevice.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> remoteSeek(Duration position) async {
    if (!state.isRemote) return;
    await _service.sendCommand(
      ConnectCommand(
        action: 'seek',
        targetDeviceId: state.activeDevice.id,
        senderDeviceId: state.currentDevice.id,
        positionMs: position.inMilliseconds,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> remoteSetVolume(double volume) async {
    state = state.copyWith(remoteVolume: volume.clamp(0.0, 1.0));
    if (!state.isRemote) return;
    await _service.sendCommand(
      ConnectCommand(
        action: 'volume',
        targetDeviceId: state.activeDevice.id,
        senderDeviceId: state.currentDevice.id,
        volume: volume,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> remoteNext() async {
    if (!state.isRemote) return;
    await _service.sendCommand(
      ConnectCommand(
        action: 'next',
        targetDeviceId: state.activeDevice.id,
        senderDeviceId: state.currentDevice.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> remotePrevious() async {
    if (!state.isRemote) return;
    await _service.sendCommand(
      ConnectCommand(
        action: 'previous',
        targetDeviceId: state.activeDevice.id,
        senderDeviceId: state.currentDevice.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> disconnectToThisDevice() async {
    final curActive = state.activeDevice;
    if (state.isRemote) {
      await _service.sendCommand(
        ConnectCommand(
          action: 'pause',
          targetDeviceId: curActive.id,
          senderDeviceId: state.currentDevice.id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    state = state.copyWith(activeDevice: state.currentDevice);
    await _ref.read(playerControllerProvider.notifier).play();
  }
}

final connectControllerProvider =
    StateNotifierProvider<ConnectNotifier, ConnectState>((ref) {
  return ConnectNotifier(ref);
});
