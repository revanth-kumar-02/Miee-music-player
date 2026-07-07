import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/audio/providers.dart';
import '../../../../features/playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../domain/youtube_model.dart';

/// Bottom sheet displaying operations for a selected YouTube video.
class YouTubeOptionsMenu extends ConsumerWidget {
  final YouTubeVideo video;

  const YouTubeOptionsMenu({super.key, required this.video});

  Future<void> _launchURL(String urlString, BuildContext context) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $urlString';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open link: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
            child: Container(
              width: 36.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),

          // Header with Title / Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.marginMobile,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        video.channelTitle,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Actions
          ListTile(
            leading: const Icon(Icons.queue, color: AppColors.onSurfaceVariant),
            title: const Text('Add to Queue'),
            onTap: () {
              Navigator.of(context).pop();
              ref.read(playerControllerProvider.notifier).addTrackToQueue(video);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added "${video.title}" to queue'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: AppColors.onSurfaceVariant),
            title: const Text('Save to Playlist'),
            onTap: () {
              Navigator.of(context).pop();
              showAddToPlaylistSheet(context, video);
            },
          ),

          ListTile(
            leading: const Icon(Icons.open_in_new, color: AppColors.onSurfaceVariant),
            title: const Text('Open in YouTube'),
            onTap: () {
              Navigator.of(context).pop();
              _launchURL(video.videoUrl, context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note_outlined, color: AppColors.onSurfaceVariant),
            title: const Text('Open in YouTube Music'),
            onTap: () {
              Navigator.of(context).pop();
              _launchURL(video.musicUrl, context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined, color: AppColors.onSurfaceVariant),
            title: const Text('Share Link'),
            onTap: () {
              Navigator.of(context).pop();
              Share.share('${video.title}\n${video.videoUrl}');
            },
          ),
        ],
      ),
    );
  }
}
