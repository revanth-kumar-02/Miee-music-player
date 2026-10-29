import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/models/music_item.dart';
import '../../domain/music_drop_models.dart';
import '../../providers/music_drop_providers.dart';
import 'music_drop_sheet.dart';

/// Contextual Music Drop pill button displayed in Now Playing and track action bars.
/// Reflected from real Nearby Connections discovery, connection, and transfer states.
class MusicDropPill extends ConsumerWidget {
  final MusicItem? track;
  final bool compact;

  const MusicDropPill({
    super.key,
    this.track,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicDropControllerProvider);
    final activeConnection = state.activeConnection;
    final endpoints = state.discoveredEndpoints;
    final transfers = state.activeTransfers.values.toList();

    // Determine active transfer in progress if any
    final inProgressTransfer = transfers.where((t) =>
        t.status == MusicDropTransferStatus.inProgress ||
        t.status == MusicDropTransferStatus.receiving ||
        t.status == MusicDropTransferStatus.verifying).firstOrNull;

    final completedTransfer = transfers.where((t) =>
        t.status == MusicDropTransferStatus.completed &&
        !t.isCommitted).firstOrNull;

    final isTransferActive = inProgressTransfer != null;
    final isDeviceFound = endpoints.isNotEmpty || activeConnection?.status == MusicDropConnectionStatus.connected;

    // Label and icon logic
    String label = 'Drop';
    IconData icon = Icons.sensors_rounded;
    Color iconColor = AppColors.vanillaCream;
    Color textColor = AppColors.vanillaCream;
    Color bgColor = AppColors.white.withValues(alpha: 0.08);
    Border? border;

    if (inProgressTransfer != null) {
      final pct = (inProgressTransfer.progress * 100).toInt();
      label = inProgressTransfer.direction == MusicDropTransferDirection.outgoing
          ? 'Sending $pct%'
          : 'Receiving $pct%';
      icon = Icons.sync_rounded;
      iconColor = AppColors.dustyRose;
      textColor = AppColors.dustyRose;
      bgColor = AppColors.dustyRose.withValues(alpha: 0.15);
      border = Border.all(color: AppColors.dustyRose.withValues(alpha: 0.4));
    } else if (completedTransfer != null) {
      label = completedTransfer.direction == MusicDropTransferDirection.incoming
          ? 'Song Ready!'
          : 'Sent!';
      icon = Icons.check_circle_outline_rounded;
      iconColor = const Color(0xFF4A7C59);
      textColor = const Color(0xFF4A7C59);
      bgColor = const Color(0xFF4A7C59).withValues(alpha: 0.15);
      border = Border.all(color: const Color(0xFF4A7C59).withValues(alpha: 0.4));
    } else if (activeConnection?.status == MusicDropConnectionStatus.connected) {
      label = activeConnection!.endpointName.length > 12
          ? '${activeConnection.endpointName.substring(0, 10)}...'
          : activeConnection.endpointName;
      icon = Icons.devices_rounded;
      iconColor = AppColors.dustyRose;
      textColor = AppColors.dustyRose;
      bgColor = AppColors.dustyRose.withValues(alpha: 0.12);
      border = Border.all(color: AppColors.dustyRose.withValues(alpha: 0.35));
    } else if (endpoints.isNotEmpty) {
      final firstName = endpoints.first.endpointName;
      label = endpoints.length == 1
          ? (firstName.length > 10 ? '${firstName.substring(0, 8)}...' : firstName)
          : 'Drop (${endpoints.length})';
      icon = Icons.sensors_rounded;
      iconColor = AppColors.vanillaCream;
      textColor = AppColors.vanillaCream;
      bgColor = AppColors.white.withValues(alpha: 0.14);
      border = Border.all(color: AppColors.vanillaCream.withValues(alpha: 0.25));
    }

    return InkWell(
      onTap: () {
        MusicDropSheet.show(context, track: track);
      },
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: border,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 14 : 16,
              color: iconColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.geist(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: isDeviceFound || isTransferActive
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

