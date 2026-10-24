import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../providers/room_providers.dart';

class ActiveRoomPage extends ConsumerWidget {
  const ActiveRoomPage({super.key});

  void _copyJoinCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room code $code copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.cocoaPlum,
      ),
    );
  }

  void _shareJoinCode(String code, String roomName) {
    Share.share(
      'Join my listening room "$roomName" on Miee! Enter room code: $code',
      subject: 'Listen Together on Miee',
    );
  }

  Future<void> _handleLeave(BuildContext context, WidgetRef ref, bool isHost) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.vanillaCream,
        title: Text(
          isHost ? 'End Listening Room?' : 'Leave Room?',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: AppColors.cocoaPlum),
        ),
        content: Text(
          isHost
              ? 'As host, ending this room will disconnect all listeners and close the session.'
              : 'You will stop receiving synchronized audio from the host.',
          style: GoogleFonts.geist(color: AppColors.cocoaPlum.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.cocoaPlum)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(isHost ? 'End Room' : 'Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (isHost) {
        await ref.read(roomControllerProvider.notifier).endRoom();
      } else {
        await ref.read(roomControllerProvider.notifier).leaveRoom();
      }
      if (context.mounted) {
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomState = ref.watch(roomControllerProvider);
    final activeRoom = roomState.activeRoom;
    final playbackState = roomState.playbackState;
    final isHost = roomState.isHost;
    final playerState = ref.watch(playerControllerProvider);
    final playerCtrl = ref.read(playerControllerProvider.notifier);

    // If room has ended, show overlay / notification and direct to home
    if (roomState.roomEnded) {
      return Scaffold(
        backgroundColor: AppColors.vanillaCream,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.meeting_room_outlined, size: 64, color: AppColors.dustyRose),
                const SizedBox(height: 20),
                Text(
                  'Room Has Ended',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'The host has ended this listening session. Your local player is now back to individual mode.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.geist(
                    fontSize: 14,
                    color: AppColors.cocoaPlum.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    ref.read(roomControllerProvider.notifier).leaveRoom();
                    context.go('/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cocoaPlum,
                    foregroundColor: AppColors.vanillaCream,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Return to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (activeRoom == null) {
      return Scaffold(
        backgroundColor: AppColors.vanillaCream,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No active room.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.go('/rooms'),
                child: const Text('Go to Rooms'),
              ),
            ],
          ),
        ),
      );
    }

    final currentTitle = isHost
        ? (playerState.currentTrack?.title ?? 'No track playing')
        : (playbackState?.title ?? 'Waiting for host to play music...');
    final currentArtist = isHost
        ? (playerState.currentTrack?.artist ?? '')
        : (playbackState?.artist ?? '');
    final currentImageUrl = isHost
        ? playerState.currentTrack?.imageUrl
        : playbackState?.imageUrl;

    final isPlaying = isHost
        ? playerState.status == PlaybackStatus.playing
        : playbackState?.playbackStatus == 'playing';

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: AppColors.cocoaPlum),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text(
              activeRoom.name,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.cocoaPlum,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isPlaying ? Colors.green : Colors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  roomState.syncStatusText ?? (isHost ? 'Hosting' : 'In Sync'),
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cocoaPlum.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
            tooltip: isHost ? 'End Room' : 'Leave Room',
            onPressed: () => _handleLeave(context, ref, isHost),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Join Code Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cocoaPlum.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ROOM JOIN CODE',
                            style: GoogleFonts.geist(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AppColors.cocoaPlum.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeRoom.joinCode,
                            style: GoogleFonts.geistMono(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: AppColors.dustyRose),
                      tooltip: 'Copy Code',
                      onPressed: () => _copyJoinCode(context, activeRoom.joinCode),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: AppColors.cocoaPlum),
                      tooltip: 'Share Invite',
                      onPressed: () => _shareJoinCode(activeRoom.joinCode, activeRoom.name),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Currently Playing Synchronized Track Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cocoaPlum,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cocoaPlum.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 68,
                            height: 68,
                            color: AppColors.cocoaPlum,
                            child: currentImageUrl != null && currentImageUrl.isNotEmpty
                                ? Image.network(
                                    currentImageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.music_note_rounded,
                                      color: AppColors.vanillaCream,
                                    ),
                                  )
                                : const Icon(
                                    Icons.music_note_rounded,
                                    color: AppColors.vanillaCream,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.vanillaCream,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentArtist.isNotEmpty ? currentArtist : 'Miee Synchronized Stream',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.geist(
                                  fontSize: 12,
                                  color: AppColors.vanillaCream.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.dustyRose.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isHost ? 'HOST CONTROLS' : 'SYNCHRONIZED WITH HOST',
                                  style: GoogleFonts.geist(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                    color: AppColors.dustyRose,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Playback Controls (Host Only)
                    if (isHost)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: AppColors.vanillaCream, size: 28),
                            onPressed: () => playerCtrl.previous(),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: const BoxDecoration(
                              color: AppColors.dustyRose,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: () => playerCtrl.togglePlayPause(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: AppColors.vanillaCream, size: 28),
                            onPressed: () => playerCtrl.next(),
                          ),
                        ],
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Playback is controlled authoritatively by the host.',
                          style: GoogleFonts.geist(
                            fontSize: 12,
                            color: AppColors.vanillaCream.withOpacity(0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 3. Participants List Section (Capacity 1-5 locked requirement)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LISTENERS',
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: AppColors.cocoaPlum.withOpacity(0.6),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: roomState.members.length >= activeRoom.capacity
                          ? Colors.red.shade100
                          : AppColors.softClay.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${roomState.members.length} / ${activeRoom.capacity} seats',
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: roomState.members.length >= activeRoom.capacity
                            ? Colors.red.shade800
                            : AppColors.cocoaPlum,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: roomState.members.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: AppColors.cocoaPlum.withOpacity(0.06),
                  ),
                  itemBuilder: (context, index) {
                    final member = roomState.members[index];
                    final isMemberHost = member.role == 'host';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isMemberHost
                            ? AppColors.dustyRose.withOpacity(0.2)
                            : AppColors.cocoaPlum.withOpacity(0.1),
                        child: isMemberHost
                            ? const Icon(Icons.star_rounded, color: AppColors.dustyRose, size: 20)
                            : const Icon(Icons.person_rounded, color: AppColors.cocoaPlum, size: 20),
                      ),
                      title: Text(
                        member.displayName ?? (isMemberHost ? 'Room Host' : 'Listener ${index + 1}'),
                        style: GoogleFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cocoaPlum,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isMemberHost
                              ? AppColors.dustyRose.withOpacity(0.15)
                              : Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isMemberHost ? 'HOST' : 'LISTENING',
                          style: GoogleFonts.geist(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: isMemberHost ? AppColors.dustyRose : Colors.green.shade800,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // 4. Shared Queue Section
              if (playbackState?.queue != null && playbackState!.queue.isNotEmpty) ...[
                Text(
                  'UP NEXT IN ROOM',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: AppColors.cocoaPlum.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: playbackState.queue.length > 5 ? 5 : playbackState.queue.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: AppColors.cocoaPlum.withOpacity(0.06),
                    ),
                    itemBuilder: (context, idx) {
                      final item = playbackState.queue[idx];
                      return ListTile(
                        leading: Text(
                          '${idx + 1}',
                          style: GoogleFonts.geist(
                            fontWeight: FontWeight.bold,
                            color: AppColors.cocoaPlum.withOpacity(0.4),
                          ),
                        ),
                        title: Text(
                          item['title'] as String? ?? 'Track',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.cocoaPlum,
                          ),
                        ),
                        subtitle: Text(
                          item['artist'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.geist(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
