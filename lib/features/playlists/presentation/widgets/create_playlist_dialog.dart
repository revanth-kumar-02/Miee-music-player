import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_typography.dart';
import '../../providers/playlist_providers.dart';

/// Shows a dialog to create or rename a playlist.
///
/// [existingId] — when provided, operates in rename mode.
/// Returns the playlist id on success, or null if cancelled.
Future<String?> showCreatePlaylistDialog(
  BuildContext context, {
  String? existingId,
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CreatePlaylistDialog(
      existingId: existingId,
      initialName: initialName,
    ),
  );
}

class _CreatePlaylistDialog extends ConsumerStatefulWidget {
  final String? existingId;
  final String? initialName;

  const _CreatePlaylistDialog({this.existingId, this.initialName});

  @override
  ConsumerState<_CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<_CreatePlaylistDialog> {
  late final TextEditingController _controller;
  String? _error;

  bool get _isRename => widget.existingId != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    _controller.addListener(_validate);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    final error = ref.read(playlistControllerProvider.notifier).validateName(
          _controller.text,
          excludeId: widget.existingId,
        );
    if (error != _error) setState(() => _error = error);
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    final ctrl = ref.read(playlistControllerProvider.notifier);

    if (_isRename) {
      final err = await ctrl.renamePlaylist(widget.existingId!, name);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      if (mounted) Navigator.of(context).pop(widget.existingId);
    } else {
      final id = await ctrl.createPlaylist(name);
      if (id == null) {
        setState(() => _error = ref.read(playlistErrorProvider));
        return;
      }
      if (mounted) Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _error == null && _controller.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusXl),
      title: Text(
        _isRename ? 'Rename Playlist' : 'New Playlist',
        style: AppTypography.headlineMedium.copyWith(color: AppColors.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 100,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: AppTypography.bodyMedium
                  .copyWith(color: AppColors.onSurfaceVariant),
              errorText: _error,
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: AppRadius.radiusMd,
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
            ),
            onSubmitted: (_) => canSubmit ? _submit() : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            'Cancel',
            style: AppTypography.labelMedium
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusMd),
          ),
          child: Text(
            _isRename ? 'Rename' : 'Create',
            style: AppTypography.labelMedium.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
