import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/music_drop_models.dart';
import '../../providers/music_drop_providers.dart';
import 'music_drop_sheet.dart';

/// Unobtrusive floating banner alerting the receiver of an incoming Music Drop or connection request.
class IncomingDropBanner extends ConsumerWidget {
  const IncomingDropBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicDropControllerProvider);
    final activeConnection = state.activeConnection;

    // Check for incoming connection initiating
    final isIncomingConnection = activeConnection != null &&
        activeConnection.isIncoming &&
        activeConnection.status == MusicDropConnectionStatus.initiating;

    // Check for incoming transfer awaiting consent
    final awaitingConsentTransfer = state.activeTransfers.values.where((t) =>
        t.direction == MusicDropTransferDirection.incoming &&
        t.status == MusicDropTransferStatus.completed &&
        !t.isCommitted).firstOrNull;

    // Check for incoming transfer in progress
    final incomingInProgress = state.activeTransfers.values.where((t) =>
        t.direction == MusicDropTransferDirection.incoming &&
        (t.status == MusicDropTransferStatus.inProgress ||
            t.status == MusicDropTransferStatus.receiving ||
            t.status == MusicDropTransferStatus.verifying)).firstOrNull;

    if (!isIncomingConnection && awaitingConsentTransfer == null && incomingInProgress == null) {
      return const SizedBox.shrink();
    }

    String title = 'Music Drop';
    String subtitle = 'Tap to view';
    IconData icon = Icons.sensors_rounded;
    Color accentColor = AppColors.dustyRose;

    if (awaitingConsentTransfer != null) {
      title = 'Song Ready to Add';
      subtitle = '"${awaitingConsentTransfer.metadata.title}" by ${awaitingConsentTransfer.metadata.artist}';
      icon = Icons.verified_rounded;
      accentColor = const Color(0xFF4A7C59);
    } else if (incomingInProgress != null) {
      final pct = (incomingInProgress.progress * 100).toInt();
      title = 'Receiving Music Drop';
      subtitle = '"${incomingInProgress.metadata.title}" ($pct%)';
      icon = Icons.download_rounded;
    } else if (isIncomingConnection) {
      title = 'Incoming Drop Request';
      subtitle = 'From ${activeConnection.endpointName} • Code ${activeConnection.authDigits ?? ""}';
      icon = Icons.phonelink_ring_rounded;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.vanillaCream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x223A252B),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => MusicDropSheet.show(context),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 11.5,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: AppColors.white,
                elevation: 0,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => MusicDropSheet.show(context),
              child: Text(
                'Open',
                style: GoogleFonts.geist(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
