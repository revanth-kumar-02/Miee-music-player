import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../domain/room_models.dart';
import '../providers/room_providers.dart';
import 'widgets/in_room_song_search_sheet.dart';
import 'widgets/room_chat_view.dart';

class ActiveRoomPage extends ConsumerStatefulWidget {
  const ActiveRoomPage({super.key});

  @override
  ConsumerState<ActiveRoomPage> createState() => _ActiveRoomPageState();
}

class _ActiveRoomPageState extends ConsumerState<ActiveRoomPage> {
  int _selectedTab = 0; // 0: Chat & Requests, 1: Queue, 2: Listeners

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
  Widget build(BuildContext context) {
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
          // Host Search & Play Quick Action in AppBar
          if (isHost)
            IconButton(
              icon: const Icon(Icons.search_rounded, color: AppColors.cocoaPlum),
              tooltip: 'Search & Play in Room',
              onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: false),
            ),
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
            tooltip: isHost ? 'End Room' : 'Leave Room',
            onPressed: () => _handleLeave(context, ref, isHost),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Join Code Card
              Container(
                padding: const EdgeInsets.all(14),
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
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 5,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: AppColors.dustyRose, size: 20),
                      tooltip: 'Copy Code',
                      onPressed: () => _copyJoinCode(context, activeRoom.joinCode),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: AppColors.cocoaPlum, size: 20),
                      tooltip: 'Share Invite',
                      onPressed: () => _shareJoinCode(activeRoom.joinCode, activeRoom.name),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

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
                            width: 64,
                            height: 64,
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

                    const SizedBox(height: 14),

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
                                size: 28,
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
                        padding: const EdgeInsets.symmetric(vertical: 6),
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

              // Host "Search & Play in Room" Action Button
              if (isHost) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: false),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search & Play Song in Room'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dustyRose,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: GoogleFonts.geist(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // 3. Segmented Tab Selector (Chat & Requests / Queue / Listeners)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.softClay.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _buildTabPill(
                      index: 0,
                      label: 'Chat & Requests',
                      countBadge: roomState.messages.isNotEmpty ? '${roomState.messages.length}' : null,
                      icon: Icons.chat_bubble_outline_rounded,
                    ),
                    _buildTabPill(
                      index: 1,
                      label: 'Up Next',
                      countBadge: playbackState?.queue.isNotEmpty == true ? '${playbackState!.queue.length}' : null,
                      icon: Icons.queue_music_rounded,
                    ),
                    _buildTabPill(
                      index: 2,
                      label: 'Listeners',
                      countBadge: '${roomState.members.length}/${activeRoom.capacity}',
                      icon: Icons.people_outline_rounded,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 4. Tab Content Section
              if (_selectedTab == 0)
                // Tab 0: Chat & Song Requests
                const SizedBox(
                  height: 420,
                  child: RoomChatView(),
                )
              else if (_selectedTab == 1)
                // Tab 1: Queue Section
                _buildQueueSection(playbackState, isHost)
              else
                // Tab 2: Listeners List Section
                _buildListenersSection(roomState, activeRoom),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String label,
    required IconData icon,
    String? countBadge,
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.cocoaPlum.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.cocoaPlum : AppColors.cocoaPlum.withOpacity(0.55),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.cocoaPlum : AppColors.cocoaPlum.withOpacity(0.65),
                  ),
                ),
              ),
              if (countBadge != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.dustyRose : AppColors.cocoaPlum.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    countBadge,
                    style: GoogleFonts.geist(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppColors.cocoaPlum,
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

  Widget _buildQueueSection(RoomPlaybackState? playbackState, bool isHost) {
    final queue = playbackState?.queue ?? [];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.cocoaPlum.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'UP NEXT IN ROOM',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                if (isHost)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (queue.isNotEmpty) ...[
                        TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.vanillaCream,
                                title: Text(
                                  'Clear Room Queue?',
                                  style: GoogleFonts.playfairDisplay(
                                    color: AppColors.cocoaPlum,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: Text(
                                  'This will remove all upcoming tracks from the room queue.',
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
                                    child: const Text('Clear All'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(roomControllerProvider.notifier).hostClearQueue();
                            }
                          },
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: Text(
                            'Clear',
                            style: GoogleFonts.geist(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      TextButton.icon(
                        onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: false),
                        icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.dustyRose),
                        label: Text(
                          'Add Songs',
                          style: GoogleFonts.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dustyRose,
                          ),
                        ),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (queue.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.queue_music_rounded, size: 36, color: AppColors.cocoaPlum.withOpacity(0.2)),
                    const SizedBox(height: 8),
                    Text(
                      'No tracks in queue',
                      style: GoogleFonts.geist(fontSize: 13, color: AppColors.cocoaPlum.withOpacity(0.6)),
                    ),
                    if (isHost) ...[
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cocoaPlum,
                          foregroundColor: AppColors.vanillaCream,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        child: const Text('Add Songs to Queue'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: queue.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.cocoaPlum.withOpacity(0.06)),
              itemBuilder: (context, idx) {
                final item = queue[idx];
                final title = item['title'] as String? ?? 'Track';
                final artist = item['artist'] as String? ?? '';
                final imageUrl = item['imageUrl'] as String?;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${idx + 1}',
                          style: GoogleFonts.geist(
                            fontWeight: FontWeight.bold,
                            color: AppColors.cocoaPlum.withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: (imageUrl != null && imageUrl.isNotEmpty)
                            ? Image.network(
                                imageUrl,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 40,
                                  height: 40,
                                  color: AppColors.cocoaPlum.withOpacity(0.1),
                                  child: const Icon(Icons.music_note_rounded, size: 20, color: AppColors.cocoaPlum),
                                ),
                              )
                            : Container(
                                width: 40,
                                height: 40,
                                color: AppColors.cocoaPlum.withOpacity(0.1),
                                child: const Icon(Icons.music_note_rounded, size: 20, color: AppColors.cocoaPlum),
                              ),
                      ),
                    ],
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                  ),
                  subtitle: Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(fontSize: 11, color: AppColors.cocoaPlum.withOpacity(0.6)),
                  ),
                  trailing: isHost
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline_rounded, size: 22, color: AppColors.dustyRose),
                              tooltip: 'Play Now in Room',
                              onPressed: () => ref.read(roomControllerProvider.notifier).hostPlayQueueTrack(idx),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.cocoaPlum),
                              tooltip: 'Remove from Queue',
                              onPressed: () async {
                                await ref.read(roomControllerProvider.notifier).hostRemoveQueueTrack(idx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Removed "$title" from room queue'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildListenersSection(RoomState roomState, ListeningRoom activeRoom) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.cocoaPlum.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ROOM PARTICIPANTS',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: AppColors.cocoaPlum,
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
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: roomState.members.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.cocoaPlum.withOpacity(0.06)),
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
        ],
      ),
    );
  }
}
