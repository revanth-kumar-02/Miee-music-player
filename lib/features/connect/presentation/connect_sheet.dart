import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/connect_device.dart';
import '../providers/connect_providers.dart';

class ConnectSheet extends ConsumerWidget {
  const ConnectSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ConnectSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectState = ref.watch(connectControllerProvider);
    final notifier = ref.read(connectControllerProvider.notifier);
    final isRemote = connectState.isRemote;
    final activeDev = connectState.activeDevice;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12161F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.devices_rounded,
                      color: Color(0xFF1DB954),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect to a device',
                        style: GoogleFonts.outfit(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        isRemote ? 'Playing through ${activeDev.name}' : 'Listening on this device',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isRemote ? const Color(0xFF1DB954) : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Active device volume slider if controlling remote speaker
              if (isRemote) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A202C),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Speaker Volume',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            '${(connectState.remoteVolume * 100).round()}%',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1DB954),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF1DB954),
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          overlayColor: const Color(0xFF1DB954).withValues(alpha: 0.2),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: connectState.remoteVolume,
                          onChanged: (v) => notifier.remoteSetVolume(v),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Section Label
              Text(
                'AVAILABLE DEVICES',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 12),

              // Devices List
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: connectState.availableDevices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final dev = connectState.availableDevices[index];
                    final isDevActive = dev.id == activeDev.id;

                    return _DeviceTile(
                      device: dev,
                      isActive: isDevActive,
                      onTap: () {
                        notifier.selectDevice(dev);
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Switch back to this phone button (if remote)
              if (isRemote) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      notifier.disconnectToThisDevice();
                    },
                    icon: const Icon(Icons.smartphone_rounded, size: 18),
                    label: const Text('Play on this phone'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final ConnectDevice device;
  final bool isActive;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = _getDeviceIcon(device.type);
    final badgeLabel = _getProtocolLabel(device.protocol);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1DB954).withValues(alpha: 0.12) : const Color(0xFF181D27),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? const Color(0xFF1DB954).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              // Device Icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF1DB954) : Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconData,
                  color: isActive ? Colors.black : Colors.white70,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Device Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                        color: isActive ? const Color(0xFF1DB954) : Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          badgeLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white54,
                          ),
                        ),
                        if (device.isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'CURRENT',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Active Indicator
              if (isActive)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF1DB954),
                  size: 22,
                )
              else
                const Icon(
                  Icons.radio_button_unchecked_rounded,
                  color: Colors.white24,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.desktop:
        return Icons.laptop_chromebook_rounded;
      case DeviceType.web:
        return Icons.public_rounded;
      case DeviceType.speaker:
        return Icons.speaker_group_rounded;
      case DeviceType.tv:
        return Icons.tv_rounded;
      case DeviceType.phone:
        return Icons.smartphone_rounded;
    }
  }

  String _getProtocolLabel(DeviceProtocol proto) {
    switch (proto) {
      case DeviceProtocol.mieeConnect:
        return 'Miee Connect';
      case DeviceProtocol.googleCast:
        return 'Google Cast';
      case DeviceProtocol.dlna:
        return 'AirPlay / Smart TV';
      case DeviceProtocol.thisDevice:
        return 'Local Speaker';
    }
  }
}
