import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/sync/supabase_config.dart';
import '../../domain/room_models.dart';
import '../../providers/room_providers.dart';
import 'in_room_song_search_sheet.dart';

class RoomChatView extends ConsumerStatefulWidget {
  const RoomChatView({super.key});

  @override
  ConsumerState<RoomChatView> createState() => _RoomChatViewState();
}

class _RoomChatViewState extends ConsumerState<RoomChatView> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await ref.read(roomControllerProvider.notifier).sendChatMessage(text);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomControllerProvider);
    final messages = roomState.messages;
    final isHost = roomState.isHost;
    final currentUserId = SupabaseConfig.hasActiveSupabase
        ? Supabase.instance.client.auth.currentUser?.id
        : null;

    // Trigger scroll when message count changes
    ref.listen(roomControllerProvider.select((s) => s.messages.length), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        children: [
          // Header / Suggest Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.softClay.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(color: AppColors.cocoaPlum.withOpacity(0.06)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 16, color: AppColors.dustyRose),
                    const SizedBox(width: 8),
                    Text(
                      'ROOM CHAT & REQUESTS',
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: AppColors.cocoaPlum,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: true),
                  icon: const Icon(Icons.music_note_rounded, size: 16, color: AppColors.dustyRose),
                  label: Text(
                    'Suggest Song',
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dustyRose,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          // Message List
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 38,
                            color: AppColors.cocoaPlum.withOpacity(0.2),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No messages yet',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Suggest your favourite track or chat with everyone in the room!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.geist(
                              fontSize: 12,
                              color: AppColors.cocoaPlum.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: true),
                            icon: const Icon(Icons.queue_music_rounded, size: 16),
                            label: const Text('Suggest a Song'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cocoaPlum,
                              foregroundColor: AppColors.vanillaCream,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: GoogleFonts.geist(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = currentUserId != null && msg.userId == currentUserId;
                      return _buildMessageTile(context, msg, isMe, isHost);
                    },
                  ),
          ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              border: Border(
                top: BorderSide(color: AppColors.cocoaPlum.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                // Quick Suggest Shortcut Button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.dustyRose, size: 24),
                  tooltip: 'Suggest a Song',
                  onPressed: () => InRoomSongSearchSheet.show(context, isSuggestionMode: true),
                ),

                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.vanillaCream.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: _messageController,
                      style: GoogleFonts.geist(fontSize: 13, color: AppColors.cocoaPlum),
                      decoration: InputDecoration(
                        hintText: 'Suggest a song or say something...',
                        hintStyle: GoogleFonts.geist(fontSize: 12, color: AppColors.cocoaPlum.withOpacity(0.4)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _handleSendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send Button
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cocoaPlum,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: AppColors.vanillaCream,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded, color: AppColors.vanillaCream, size: 18),
                    onPressed: _isSending ? null : _handleSendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(BuildContext context, RoomMessage msg, bool isMe, bool isHost) {
    if (msg.isSongSuggestion) {
      return _buildSongSuggestionCard(context, msg, isMe, isHost);
    }
    return _buildTextMessage(msg, isMe);
  }

  Widget _buildTextMessage(RoomMessage msg, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.cocoaPlum.withOpacity(0.12),
              backgroundImage: (msg.userAvatar != null && msg.userAvatar!.isNotEmpty)
                  ? NetworkImage(msg.userAvatar!)
                  : null,
              child: (msg.userAvatar == null || msg.userAvatar!.isEmpty)
                  ? Text(
                      (msg.userName?.isNotEmpty == true ? msg.userName![0] : 'L').toUpperCase(),
                      style: GoogleFonts.geist(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.cocoaPlum),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isMe ? AppColors.cocoaPlum : AppColors.softClay.withOpacity(0.15),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe && msg.userName != null)
                    Text(
                      msg.userName!,
                      style: GoogleFonts.geist(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dustyRose,
                      ),
                    ),
                  Text(
                    msg.content,
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: isMe ? AppColors.vanillaCream : AppColors.cocoaPlum,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildSongSuggestionCard(BuildContext context, RoomMessage msg, bool isMe, bool isHost) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dustyRose.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dustyRose.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: User suggested
          Row(
            children: [
              const Icon(Icons.music_note_rounded, size: 14, color: AppColors.dustyRose),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${isMe ? "You" : (msg.userName ?? "Listener")} suggested a song:',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dustyRose,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Track row
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48,
                  height: 48,
                  color: AppColors.cocoaPlum.withOpacity(0.1),
                  child: msg.trackImageUrl != null && msg.trackImageUrl!.isNotEmpty
                      ? Image.network(
                          msg.trackImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: AppColors.cocoaPlum),
                        )
                      : const Icon(Icons.music_note_rounded, color: AppColors.cocoaPlum),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.trackTitle ?? 'Track',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cocoaPlum,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      msg.trackArtist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.cocoaPlum.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Optional note
          if (msg.content.isNotEmpty && !msg.content.startsWith('Suggested "') && !msg.content.startsWith('Can we play "')) ...[
            const SizedBox(height: 6),
            Text(
              '"${msg.content}"',
              style: GoogleFonts.geist(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.cocoaPlum.withOpacity(0.75),
              ),
            ),
          ],

          // Host Actions: Play Now & Queue
          if (isHost) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await ref.read(roomControllerProvider.notifier).hostPlaySuggestedTrack(msg);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Now playing "${msg.trackTitle}" in room'),
                            backgroundColor: AppColors.cocoaPlum,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Play Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cocoaPlum,
                      foregroundColor: AppColors.vanillaCream,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: GoogleFonts.geist(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(roomControllerProvider.notifier).hostQueueSuggestedTrack(msg);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added "${msg.trackTitle}" to room queue'),
                            backgroundColor: AppColors.cocoaPlum,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.playlist_add_rounded, size: 16),
                    label: const Text('Queue'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cocoaPlum,
                      side: BorderSide(color: AppColors.cocoaPlum.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: GoogleFonts.geist(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
