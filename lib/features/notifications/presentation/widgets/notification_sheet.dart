import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../connect/domain/connect_device.dart';
import '../../../connect/presentation/connect_sheet.dart';
import '../../../connect/providers/connect_providers.dart';

/// Modal bottom sheet representing Miee's unified Notification View.
///
/// Houses:
/// 1. Prominent "Devices to Connect" option displaying all available $n$ devices.
/// 2. Live audio device switching (Miee Connect / Cast / DLNA / Local).
/// 3. Recent notifications and system status updates.
class NotificationSheet extends ConsumerWidget {
  const NotificationSheet({super.key});

  /// Presents the [NotificationSheet] as a styled modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectState = ref.watch(connectControllerProvider);
    final connectNotifier = ref.read(connectControllerProvider.notifier);
    final availableDevices = connectState.availableDevices;
    final activeDevice = connectState.activeDevice;
    final isRemote = connectState.isRemote;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF141218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Connected devices & activity',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),

            // Scrollable Content
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // ── 1. DEVICES SECTION ──
                  _buildDevicesSection(
                    context: context,
                    ref: ref,
                    availableDevices: availableDevices,
                    activeDevice: activeDevice,
                    isRemote: isRemote,
                    notifier: connectNotifier,
                  ),

                  const SizedBox(height: 24),

                  // ── 2. RECENT ACTIVITY & SYSTEM ALERTS ──
                  _buildActivitySection(
                    isRemote: isRemote,
                    activeDeviceName: activeDevice.name,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection({
    required BuildContext context,
    required WidgetRef ref,
    required List<ConnectDevice> availableDevices,
    required ConnectDevice activeDevice,
    required bool isRemote,
    required ConnectNotifier notifier,
  }) {
    final count = availableDevices.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRemote
              ? const Color(0xFF1DB954).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Devices Header & Count Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isRemote
                      ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.devices_rounded,
                  color: isRemote ? const Color(0xFF1DB954) : Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Devices',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isRemote
                          ? 'Playing on ${activeDevice.name}'
                          : '$count ${count == 1 ? "device" : "devices"} to connect with',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isRemote ? const Color(0xFF1DB954) : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isRemote
                      ? const Color(0xFF1DB954).withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count Available',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isRemote ? const Color(0xFF1DB954) : Colors.white70,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),

          // Device items list
          if (availableDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Searching for nearby devices...',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
              ),
            )
          else
            ...availableDevices.map((device) {
              final isSelected = device.id == activeDevice.id;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? const Color(0xFF1DB954).withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () {
                      notifier.selectDevice(device);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            _getDeviceIcon(device.type),
                            size: 20,
                            color: isSelected ? const Color(0xFF1DB954) : Colors.white70,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF1DB954) : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _getProtocolLabel(device.protocol),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: isSelected
                                        ? const Color(0xFF1DB954).withValues(alpha: 0.8)
                                        : Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DB954),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check, size: 12, color: Colors.black),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              'Connect',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white60,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

          const SizedBox(height: 8),

          // Open detailed Connect Sheet with volume & advanced controls
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                ConnectSheet.show(context);
              },
              icon: const Icon(Icons.tune_rounded, size: 15, color: Colors.white70),
              label: Text(
                'Volume & Device Controls',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection({
    required bool isRemote,
    required String activeDeviceName,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'System Activity',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
        _buildNotificationCard(
          icon: Icons.wifi_tethering_rounded,
          iconColor: const Color(0xFF1DB954),
          title: 'Miee Connect Active',
          subtitle: isRemote
              ? 'Streaming to $activeDeviceName'
              : 'Local & network audio presence broadcast running',
          time: 'Active now',
        ),
        const SizedBox(height: 10),
        _buildNotificationCard(
          icon: Icons.graphic_eq_rounded,
          iconColor: const Color(0xFFC48E9B),
          title: 'Direct Master Audio',
          subtitle: 'Pure 32-bit floating-point audio engine operational',
          time: 'Ready',
        ),
        const SizedBox(height: 10),
        _buildNotificationCard(
          icon: Icons.cloud_done_outlined,
          iconColor: Colors.lightBlueAccent,
          title: 'Cloud Library Sync',
          subtitle: 'All playlists, likes, and profile settings in sync',
          time: 'Just now',
        ),
      ],
    );
  }

  Widget _buildNotificationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String time,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1720),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      time,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.speaker:
        return Icons.speaker_rounded;
      case DeviceType.tv:
        return Icons.tv_rounded;
      case DeviceType.web:
        return Icons.laptop_rounded;
      case DeviceType.desktop:
        return Icons.computer_rounded;
      case DeviceType.phone:
        return Icons.smartphone_rounded;
    }
  }

  String _getProtocolLabel(DeviceProtocol protocol) {
    switch (protocol) {
      case DeviceProtocol.thisDevice:
        return 'This Device • Direct Output';
      case DeviceProtocol.mieeConnect:
        return 'Miee Connect • Low Latency';
      case DeviceProtocol.googleCast:
        return 'Google Cast • Network Audio';
      case DeviceProtocol.dlna:
        return 'DLNA / UPnP • Hi-Res Stream';
    }
  }
}
