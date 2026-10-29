import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/models/music_item.dart';
import '../../domain/music_drop_models.dart';
import '../../presentation/music_drop_controller.dart';
import '../../providers/music_drop_providers.dart';

/// Modal bottom sheet providing a contextual, unobtrusive interface for Miee Music Drop.
/// Adheres strictly to Miee's warm ivory, sage green, and cocoa plum design language.
class MusicDropSheet extends ConsumerStatefulWidget {
  final MusicItem? track;

  const MusicDropSheet({
    super.key,
    this.track,
  });

  /// Displays the Music Drop contextual sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context, {MusicItem? track}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicDropSheet(track: track),
    );
  }

  @override
  ConsumerState<MusicDropSheet> createState() => _MusicDropSheetState();
}

class _MusicDropSheetState extends ConsumerState<MusicDropSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(musicDropControllerProvider);
      if (state.isPermissionsGranted && !state.isDiscovering) {
        ref.read(musicDropControllerProvider.notifier).startDiscovery();
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicDropControllerProvider);
    final controller = ref.read(musicDropControllerProvider.notifier);

    // Fall back to active track provider if none provided explicitly
    final activeTrack = widget.track ?? ref.watch(musicDropActiveTrackProvider);

    final endpoints = state.discoveredEndpoints;
    final activeConnection = state.activeConnection;
    final transfers = state.activeTransfers.values.toList();

    // Check for in-flight transfer
    final inProgressTransfer = transfers.where((t) =>
        t.status == MusicDropTransferStatus.inProgress ||
        t.status == MusicDropTransferStatus.receiving ||
        t.status == MusicDropTransferStatus.verifying).firstOrNull;

    // Check for incoming transfer awaiting consent
    final awaitingConsentTransfer = transfers.where((t) =>
        t.direction == MusicDropTransferDirection.incoming &&
        t.status == MusicDropTransferStatus.completed &&
        !t.isCommitted).firstOrNull;

    final isConnected = activeConnection?.status == MusicDropConnectionStatus.connected;
    final subtitleText = state.isDiscovering
        ? 'Scanning for nearby Miee devices...'
        : (isConnected
            ? 'Connected to ${activeConnection?.endpointName ?? "peer"}'
            : 'Bring two devices close together');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppColors.vanillaCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x333A252B),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.oatBeige,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Sheet Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.dustyRose.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sensors_rounded,
                      color: AppColors.dustyRose,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Music Drop',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.cocoaPlum,
                          ),
                        ),
                        Text(
                          subtitleText,
                          style: GoogleFonts.geist(
                            fontSize: 12.5,
                            color: AppColors.mutedMauve,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.mutedMauve,
                    splashRadius: 20,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.oatBeige, height: 1),

            // Scrollable Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Error Banner (if any)
                    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) ...[
                      _buildErrorBanner(state.errorMessage!),
                      const SizedBox(height: 12),
                    ],

                    // 2. Permission Missing Banner (if permissions needed)
                    if (!state.isPermissionsGranted) ...[
                      _buildPermissionPrompt(controller),
                      const SizedBox(height: 14),
                    ],

                    // 3. Incoming Transfer Consent Prompt (Top Priority)
                    if (awaitingConsentTransfer != null) ...[
                      _buildIncomingConsentCard(awaitingConsentTransfer, controller),
                      const SizedBox(height: 14),
                    ],

                    // 4. In-Flight Transfer Progress Card
                    if (inProgressTransfer != null) ...[
                      _buildTransferProgressCard(inProgressTransfer, controller),
                      const SizedBox(height: 14),
                    ],

                    // 5. Authentication SAS Confirmation
                    if (activeConnection != null &&
                        activeConnection.status == MusicDropConnectionStatus.initiating &&
                        activeConnection.authDigits != null) ...[
                      _buildAuthConfirmationCard(activeConnection, controller),
                      const SizedBox(height: 14),
                    ],

                    // 6. Selected Track Card
                    if (activeTrack != null) ...[
                      _buildTrackCard(activeTrack),
                      const SizedBox(height: 16),
                    ],

                    // 7. Nearby Devices Header & List
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Nearby Devices',
                          style: GoogleFonts.geist(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.cocoaPlum,
                          ),
                        ),
                        if (state.isPermissionsGranted)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.dustyRose,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: Icon(
                              state.isDiscovering ? Icons.stop_circle_outlined : Icons.radar_rounded,
                              size: 16,
                            ),
                            label: Text(
                              state.isDiscovering ? 'Stop Scan' : 'Scan',
                              style: GoogleFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () {
                              if (state.isDiscovering) {
                                controller.stopDiscovery();
                              } else {
                                controller.startDiscovery();
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (endpoints.isEmpty) ...[
                      _buildEmptyDevicesView(state.isDiscovering, controller),
                    ] else ...[
                      ...endpoints.map((endpoint) => _buildDeviceTile(
                            endpoint,
                            activeConnection,
                            activeTrack,
                            controller,
                          )),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────────────

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.geist(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionPrompt(MusicDropController controller) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.oatBeige),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_searching_rounded, color: AppColors.dustyRose, size: 20),
              const SizedBox(width: 8),
              Text(
                'Nearby Permissions Required',
                style: GoogleFonts.geist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cocoaPlum,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'To discover nearby friends without internet, Miee needs Bluetooth and Nearby permissions.',
            style: GoogleFonts.geist(
              fontSize: 12,
              color: AppColors.mutedMauve,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dustyRose,
              foregroundColor: AppColors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => controller.requestPermissions(),
            child: Text(
              'Grant Permissions',
              style: GoogleFonts.geist(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackCard(MusicItem track) {
    final isYt = track.isYoutube;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          // Album Art / Placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: AppColors.surfaceContainerHighest,
              child: track.imageUrl.isNotEmpty
                  ? Image.network(
                      track.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.mutedMauve,
                        size: 24,
                      ),
                    )
                  : const Icon(
                      Icons.music_note_rounded,
                      color: AppColors.mutedMauve,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    color: AppColors.mutedMauve,
                  ),
                ),
                const SizedBox(height: 4),
                // Restriction Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isYt
                        ? const Color(0xFFE07A5F).withValues(alpha: 0.15)
                        : const Color(0xFF4A7C59).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isYt
                        ? 'YouTube Music • Metadata Reference'
                        : 'Local Audio File • Full Transfer',
                    style: GoogleFonts.geist(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isYt ? const Color(0xFFC0583E) : const Color(0xFF336340),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDevicesView(bool isDiscovering, MusicDropController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            isDiscovering ? Icons.radar_rounded : Icons.sensors_off_rounded,
            size: 36,
            color: isDiscovering ? AppColors.dustyRose : AppColors.mutedMauve,
          ),
          const SizedBox(height: 10),
          Text(
            isDiscovering
                ? 'Looking for nearby Miee devices...'
                : 'No nearby devices found',
            style: GoogleFonts.geist(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.cocoaPlum,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isDiscovering
                ? 'Make sure the other phone has Miee open.'
                : 'Ensure both devices have Bluetooth turned on.',
            textAlign: TextAlign.center,
            style: GoogleFonts.geist(
              fontSize: 12,
              color: AppColors.mutedMauve,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(
    MusicDropEndpoint endpoint,
    MusicDropConnection? activeConnection,
    MusicItem? activeTrack,
    MusicDropController controller,
  ) {
    final isTarget = activeConnection?.endpointId == endpoint.endpointId;
    final isConnected = isTarget && activeConnection?.status == MusicDropConnectionStatus.connected;
    final isConnecting = isTarget && activeConnection?.status == MusicDropConnectionStatus.initiating;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConnected
            ? const Color(0xFF4A7C59).withValues(alpha: 0.08)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF4A7C59).withValues(alpha: 0.3)
              : AppColors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isConnected
                  ? const Color(0xFF4A7C59).withValues(alpha: 0.15)
                  : AppColors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.phone_android_rounded,
              color: isConnected ? const Color(0xFF4A7C59) : AppColors.cocoaPlum,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  endpoint.endpointName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isConnected
                      ? 'Connected • Ready'
                      : (isConnecting ? 'Negotiating connection...' : 'Nearby • Ready to Connect'),
                  style: GoogleFonts.geist(
                    fontSize: 11.5,
                    color: isConnected ? const Color(0xFF4A7C59) : AppColors.mutedMauve,
                    fontWeight: isConnected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isConnected) ...[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dustyRose,
                foregroundColor: AppColors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: activeTrack != null
                  ? () => _sendTrackToEndpoint(endpoint.endpointId, activeTrack, controller)
                  : null,
              child: Text(
                activeTrack?.isYoutube == true ? 'Send Ref' : 'Send Song',
                style: GoogleFonts.geist(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (isConnecting) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.dustyRose,
              ),
            ),
          ] else ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cocoaPlum,
                side: const BorderSide(color: AppColors.oatBeige),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => controller.connect(endpoint.endpointId),
              child: Text(
                'Connect',
                style: GoogleFonts.geist(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthConfirmationCard(MusicDropConnection connection, MusicDropController controller) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dustyRose.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security_rounded, color: AppColors.dustyRose, size: 20),
              const SizedBox(width: 8),
              Text(
                'Confirm Security Code',
                style: GoogleFonts.geist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cocoaPlum,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ensure the matching 4-digit code is shown on ${connection.endpointName}:',
            style: GoogleFonts.geist(fontSize: 12, color: AppColors.mutedMauve),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.oatBeige),
              ),
              child: Text(
                connection.authDigits ?? '••••',
                style: GoogleFonts.geist(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: AppColors.cocoaPlum,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.mutedMauve),
                onPressed: () => controller.rejectConnection(connection.endpointId),
                child: const Text('Decline'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dustyRose,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => controller.acceptConnection(connection.endpointId),
                child: const Text('Accept & Pair'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransferProgressCard(MusicDropTransfer transfer, MusicDropController controller) {
    final isOutgoing = transfer.direction == MusicDropTransferDirection.outgoing;
    final progress = transfer.progress;
    final isVerifying = transfer.status == MusicDropTransferStatus.verifying;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dustyRose.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOutgoing ? Icons.upload_rounded : Icons.download_rounded,
                color: AppColors.dustyRose,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isVerifying
                      ? 'Verifying integrity (SHA-256)...'
                      : (isOutgoing
                          ? 'Sending to nearby peer...'
                          : 'Receiving track...'),
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cocoaPlum,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cancel_rounded, size: 20, color: AppColors.mutedMauve),
                onPressed: () => controller.cancelTransfer(transfer.transferId),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: isVerifying ? null : progress,
            backgroundColor: AppColors.oatBeige,
            color: AppColors.dustyRose,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatBytes(transfer.bytesTransferred)} of ${_formatBytes(transfer.totalBytes)}',
                style: GoogleFonts.geist(fontSize: 11.5, color: AppColors.mutedMauve),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: GoogleFonts.geist(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cocoaPlum,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingConsentCard(MusicDropTransfer transfer, MusicDropController controller) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF4A7C59).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4A7C59).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: Color(0xFF4A7C59), size: 20),
              const SizedBox(width: 8),
              Text(
                'Received Music Drop',
                style: GoogleFonts.geist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF336340),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${transfer.metadata.title}" by ${transfer.metadata.artist}',
            style: GoogleFonts.geist(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.cocoaPlum,
            ),
          ),
          if (transfer.metadata.fileSize != null) ...[
            const SizedBox(height: 2),
            Text(
              'Size: ${_formatBytes(transfer.metadata.fileSize!)} • SHA-256 Verified',
              style: GoogleFonts.geist(fontSize: 11.5, color: AppColors.mutedMauve),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Would you like to accept and add this track to your Miee library?',
            style: GoogleFonts.geist(fontSize: 12, color: AppColors.cocoaPlum),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.mutedMauve),
                onPressed: () {
                  controller.rejectOrDiscardTransfer(transfer.transferId);
                },
                child: const Text('Decline'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A7C59),
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final savedPath = await controller.commitTransfer(transfer.transferId);
                  if (savedPath != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Saved "${transfer.metadata.title}" to library!'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: const Color(0xFF336340),
                      ),
                    );
                  }
                },
                child: const Text('Accept & Add to Library'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _sendTrackToEndpoint(String endpointId, MusicItem track, MusicDropController controller) {
    if (track.isYoutube) {
      controller.sendMetadataOnly(
        endpointId: endpointId,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.imageUrl,
        sourceId: track.id,
      );
    } else {
      controller.sendAudioFile(
        endpointId: endpointId,
        filePath: track.filePath,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.imageUrl,
        sourceId: track.id,
      );
    }
  }
}
