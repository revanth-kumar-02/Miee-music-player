import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../domain/playlist_model.dart';
import '../../providers/playlist_providers.dart';

/// Opens the collaboration and sharing bottom sheet for [playlist].
Future<void> showPlaylistCollaborationSheet(
  BuildContext context,
  PlaylistModel playlist,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PlaylistCollaborationSheet(playlist: playlist),
  );
}

class PlaylistCollaborationSheet extends ConsumerStatefulWidget {
  final PlaylistModel playlist;

  const PlaylistCollaborationSheet({
    super.key,
    required this.playlist,
  });

  @override
  ConsumerState<PlaylistCollaborationSheet> createState() =>
      _PlaylistCollaborationSheetState();
}

class _PlaylistCollaborationSheetState
    extends ConsumerState<PlaylistCollaborationSheet> {
  bool _isLoading = false;
  String? _inviteToken;
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final sync = ref.read(syncManagerProvider);
    final members = await sync.fetchPlaylistMembers(widget.playlist.id);
    if (mounted) {
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    }
  }

  Future<void> _toggleCollaborative(bool enable) async {
    setState(() => _isLoading = true);
    final targetType = enable ? PlaylistType.collaborative : PlaylistType.private;
    await ref
        .read(playlistControllerProvider.notifier)
        .updatePlaylistType(widget.playlist.id, targetType);
    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enable
              ? 'Playlist set to Collaborative'
              : 'Playlist set to Private'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _generateInvite() async {
    setState(() => _isLoading = true);
    final sync = ref.read(syncManagerProvider);
    final token = await sync.createPlaylistInvitation(
      playlistId: widget.playlist.id,
      role: 'editor',
    );
    if (mounted) {
      setState(() {
        _isLoading = false;
        _inviteToken = token;
      });
      if (token != null) {
        unawaited(Clipboard.setData(ClipboardData(text: token)));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite code copied to clipboard!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.playlist.isOwner;
    final isCollab = widget.playlist.isCollaborative;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      padding: EdgeInsets.only(
        top: 12.0,
        left: 20.0,
        right: 20.0,
        bottom: MediaQuery.of(context).padding.bottom + 20.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),
          AppSpacing.heightMd,

          // Header
          Row(
            children: [
              Container(
                width: 42.0,
                height: 42.0,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: const Icon(
                  Icons.group_outlined,
                  color: AppColors.primary,
                  size: 24.0,
                ),
              ),
              AppSpacing.widthSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playlist Collaboration',
                      style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.playlist.name,
                      style: AppTypography.labelMedium.copyWith(
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
          AppSpacing.heightLg,

          // Owner toggle
          if (isOwner) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: AppRadius.radiusMd,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Collaborative Playlist',
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Allow invited friends to add, remove & reorder songs',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isCollab,
                    activeThumbColor: AppColors.primary,
                    onChanged: _isLoading ? null : (v) => _toggleCollaborative(v),
                  ),
                ],
              ),
            ),
            AppSpacing.heightMd,
          ],

          if (isCollab && (isOwner || widget.playlist.canEdit)) ...[
            FilledButton.icon(
              icon: const Icon(Icons.person_add_outlined, size: 20.0),
              label: Text(
                _isLoading ? 'Generating...' : 'Invite Collaborators',
                style: AppTypography.labelMedium.copyWith(color: Colors.white),
              ),
              onPressed: _isLoading ? null : _generateInvite,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusMd),
              ),
            ),
            if (_inviteToken != null) ...[
              AppSpacing.heightSm,
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: AppRadius.radiusMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _inviteToken!,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.onSurface,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18.0),
                      tooltip: 'Copy Code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _inviteToken!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied invite token!'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            AppSpacing.heightLg,
          ],

          // Members list
          Text(
            'Members',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          AppSpacing.heightSm,

          if (_loadingMembers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(strokeWidth: 2.0),
              ),
            )
          else if (_members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                isOwner
                    ? 'Only you have access to this playlist.'
                    : 'Collaborator details loaded from cloud.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._members.map((m) {
              final profile = m['profiles'] as Map<String, dynamic>?;
              final String name = (profile?['display_name'] ??
                      profile?['username'] ??
                      'User ${m['user_id']?.toString().substring(0, 6) ?? ''}')
                  .toString();
              final role = m['role']?.toString().toUpperCase() ?? 'MEMBER';

              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18.0,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurface),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Text(
                    role,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 10.0,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
