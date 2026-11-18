import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/sync/sync_manager.dart';

/// Shows a dialog allowing a user to enter an invite code to join a collaborative playlist.
Future<String?> showJoinPlaylistDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _JoinPlaylistDialog(),
  );
}

class _JoinPlaylistDialog extends ConsumerStatefulWidget {
  const _JoinPlaylistDialog();

  @override
  ConsumerState<_JoinPlaylistDialog> createState() => _JoinPlaylistDialogState();
}

class _JoinPlaylistDialogState extends ConsumerState<_JoinPlaylistDialog> {
  late final TextEditingController _controller;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _controller.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Please enter an invitation code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sync = ref.read(syncManagerProvider);
      final playlistId = await sync.acceptPlaylistInvitation(token);
      if (mounted) {
        Navigator.of(context).pop(playlistId);
        if (playlistId != null) {
          unawaited(context.push('/playlist/$playlistId'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Invalid or expired invite code';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusXl),
      title: Row(
        children: [
          const Icon(Icons.group_add_outlined, color: AppColors.primary),
          const SizedBox(width: 8.0),
          Text(
            'Join Playlist',
            style: AppTypography.headlineMedium.copyWith(color: AppColors.onSurface),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter the invite code you received to join and collaborate on this playlist.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16.0),
          TextField(
            controller: _controller,
            autofocus: true,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: 'Invite code (e.g. 8f2a...)',
              hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.onSurfaceVariant),
              errorText: _error,
              filled: true,
              fillColor: AppColors.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: AppRadius.radiusMd,
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            'Cancel',
            style: AppTypography.labelMedium.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusMd),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16.0,
                  height: 16.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white),
                )
              : Text(
                  'Join',
                  style: AppTypography.labelMedium.copyWith(color: Colors.white),
                ),
        ),
      ],
    );
  }
}
