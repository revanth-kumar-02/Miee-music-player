import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../shared/models/music_item.dart';
import '../../../search/providers/search_providers.dart';
import '../../providers/room_providers.dart';

class InRoomSongSearchSheet extends ConsumerStatefulWidget {
  final bool isSuggestionMode;

  const InRoomSongSearchSheet({
    super.key,
    this.isSuggestionMode = false,
  });

  static Future<void> show(BuildContext context, {bool isSuggestionMode = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InRoomSongSearchSheet(isSuggestionMode: isSuggestionMode),
    );
  }

  @override
  ConsumerState<InRoomSongSearchSheet> createState() => _InRoomSongSearchSheetState();
}

class _InRoomSongSearchSheetState extends ConsumerState<InRoomSongSearchSheet> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    ref.read(searchNotifierProvider.notifier).updateQuery(query);
  }

  Future<void> _handlePlayNow(MusicItem track) async {
    final roomCtrl = ref.read(roomControllerProvider.notifier);
    await roomCtrl.hostPlayTrack(track);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playing "${track.title}" in room'),
          backgroundColor: AppColors.cocoaPlum,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleAddToQueue(MusicItem track) async {
    final roomCtrl = ref.read(roomControllerProvider.notifier);
    await roomCtrl.hostQueueTrack(track);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${track.title}" to room queue'),
          backgroundColor: AppColors.cocoaPlum,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleSuggest(MusicItem track) async {
    final roomCtrl = ref.read(roomControllerProvider.notifier);
    await roomCtrl.sendSongSuggestion(track);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suggested "${track.title}" to the room!'),
          backgroundColor: AppColors.cocoaPlum,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);
    final isLoading = searchState.isYouTubeLoading || searchState.isLocalLoading;
    final results = <MusicItem>[
      ...searchState.youtubeResults,
      ...searchState.localSongs,
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.vanillaCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cocoaPlum.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isSuggestionMode ? 'Suggest a Song' : 'Search & Play in Room',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cocoaPlum,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isSuggestionMode
                            ? 'Search any song to drop a request into the room chat'
                            : 'Search any track to play instantly or add to room queue',
                        style: GoogleFonts.geist(
                          fontSize: 12,
                          color: AppColors.cocoaPlum.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.cocoaPlum),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cocoaPlum.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onChanged: _onQueryChanged,
                style: GoogleFonts.geist(
                  color: AppColors.cocoaPlum,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, or keywords...',
                  hintStyle: GoogleFonts.geist(
                    color: AppColors.cocoaPlum.withOpacity(0.45),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.dustyRose,
                    size: 22,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.cocoaPlum, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),

          // Content list
          Expanded(
            child: isLoading && results.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.dustyRose,
                      strokeWidth: 2.5,
                    ),
                  )
                : results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.music_note_rounded,
                                size: 48,
                                color: AppColors.cocoaPlum.withOpacity(0.2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'Type to search tracks...'
                                    : 'No songs found for "${_searchController.text}"',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.geist(
                                  fontSize: 14,
                                  color: AppColors.cocoaPlum.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: AppColors.cocoaPlum.withOpacity(0.06),
                        ),
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return _buildSearchResultTile(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultTile(MusicItem track) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52,
              height: 52,
              color: AppColors.cocoaPlum.withOpacity(0.08),
              child: track.imageUrl.isNotEmpty
                  ? Image.network(
                      track.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.cocoaPlum,
                      ),
                    )
                  : const Icon(
                      Icons.music_note_rounded,
                      color: AppColors.cocoaPlum,
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 14,
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
                    color: AppColors.cocoaPlum.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action Buttons
          if (widget.isSuggestionMode)
            ElevatedButton.icon(
              onPressed: () => _handleSuggest(track),
              icon: const Icon(Icons.send_rounded, size: 14),
              label: const Text('Suggest'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dustyRose,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else ...[
            // Host: Add to Queue
            IconButton(
              icon: const Icon(Icons.playlist_add_rounded, color: AppColors.cocoaPlum, size: 22),
              tooltip: 'Add to Room Queue',
              onPressed: () => _handleAddToQueue(track),
            ),
            // Host: Play Now
            ElevatedButton.icon(
              onPressed: () => _handlePlayNow(track),
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              label: const Text('Play'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cocoaPlum,
                foregroundColor: AppColors.vanillaCream,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
