import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/playlist_model.dart';
import '../../providers/playlist_providers.dart';

/// Shows a dialog to create or rename a playlist.
///
/// [existingId] — when provided, operates in "Edit Playlist" (rename + cover) mode.
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

// ─────────────────────────────────────────────────────────────────────────────

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

  /// Newly picked cover path from gallery (null = nothing picked this session).
  String? _pickedCoverPath;

  /// True when the user explicitly tapped ✕ to remove the cover this session.
  bool _coverCleared = false;

  bool get _isRename => widget.existingId != null;

  /// Fetch the existing [PlaylistModel] when in rename/edit mode.
  PlaylistModel? get _existingPlaylist {
    if (widget.existingId == null) return null;
    final playlists = ref.read(playlistControllerProvider).playlists;
    try {
      return playlists.firstWhere((p) => p.id == widget.existingId);
    } catch (_) {
      return null;
    }
  }

  /// The URL/path that should be rendered in the cover preview right now.
  /// Priority: newly picked → existing persistent cover → nothing (placeholder).
  String? get _displayCoverUrl {
    if (_pickedCoverPath != null) return _pickedCoverPath;
    if (_coverCleared) return null;
    return _existingPlaylist?.effectiveCoverUrl;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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

  // ── Validation ────────────────────────────────────────────────────────────

  void _validate() {
    final error = ref.read(playlistControllerProvider.notifier).validateName(
          _controller.text,
          excludeId: widget.existingId,
        );
    if (error != _error) setState(() => _error = error);
  }

  // ── Cover actions ─────────────────────────────────────────────────────────

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked != null) {
      setState(() {
        _pickedCoverPath = picked.path;
        _coverCleared = false;
      });
    }
  }

  void _clearCover() => setState(() {
        _pickedCoverPath = null;
        _coverCleared = true;
      });

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _controller.text.trim();
    final ctrl = ref.read(playlistControllerProvider.notifier);

    if (_isRename) {
      // 1. Rename
      final err = await ctrl.renamePlaylist(widget.existingId!, name);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      // 2. Apply cover change (if any)
      if (_pickedCoverPath != null) {
        await ctrl.updateCoverPath(widget.existingId!, _pickedCoverPath);
      } else if (_coverCleared) {
        await ctrl.updateCoverPath(widget.existingId!, null);
      }
      if (mounted) Navigator.of(context).pop(widget.existingId);
    } else {
      // 1. Create playlist
      final id = await ctrl.createPlaylist(name);
      if (id == null) {
        setState(() => _error = ref.read(playlistErrorProvider));
        return;
      }
      // 2. Apply cover immediately if one was picked during creation
      if (_pickedCoverPath != null) {
        await ctrl.updateCoverPath(id, _pickedCoverPath);
      }
      if (mounted) Navigator.of(context).pop(id);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canSubmit = _error == null && _controller.text.trim().isNotEmpty;
    final hasCover = _displayCoverUrl != null;

    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusXl),
      title: Text(
        _isRename ? 'Edit Playlist' : 'New Playlist',
        style: AppTypography.headlineMedium.copyWith(color: AppColors.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover picker ──────────────────────────────────────────────────
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Main tappable square
                GestureDetector(
                  onTap: _pickCover,
                  child: Container(
                    width: 110.0,
                    height: 110.0,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 10.0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasCover
                        ? _buildCoverPreview()
                        : _buildCoverPlaceholder(),
                  ),
                ),

                // ✕ clear-badge (visible only when a cover is set)
                if (hasCover)
                  Positioned(
                    top: -7.0,
                    right: -7.0,
                    child: GestureDetector(
                      onTap: _clearCover,
                      child: Container(
                        width: 22.0,
                        height: 22.0,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 13.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 6.0),

          // Hint label below cover picker
          Center(
            child: Text(
              hasCover ? 'Tap to change  ·  ✕ to remove' : 'Tap to add a cover photo',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 16.0),

          // ── Name field ────────────────────────────────────────────────────
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
            _isRename ? 'Save' : 'Create',
            style: AppTypography.labelMedium.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ── Cover helper builders ─────────────────────────────────────────────────

  /// Renders the chosen image with a semi-transparent edit overlay.
  Widget _buildCoverPreview() {
    final url = _displayCoverUrl!;
    return Stack(
      fit: StackFit.expand,
      children: [
        url.startsWith('http')
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
              )
            : Image.file(
                File(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
              ),
        // Dim overlay so the edit icon is readable
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
            ),
          ),
        ),
        const Center(
          child: Icon(Icons.edit_outlined, color: Colors.white, size: 26.0),
        ),
      ],
    );
  }

  /// Dark gradient placeholder with a camera+ icon shown when no cover is set.
  Widget _buildCoverPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF111111), Color(0xFF2A2A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: Colors.white54,
          size: 36.0,
        ),
      ),
    );
  }
}
