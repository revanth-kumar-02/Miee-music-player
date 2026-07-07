import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Reusable Search Bar input.
/// Handles active focus states internally to transition color backings and outline borders.
class AppSearchBar extends StatefulWidget {
  /// Optional text editing controller.
  final TextEditingController? controller;

  /// Callback when query changes.
  final ValueChanged<String>? onChanged;

  /// Placeholder hint text. Defaults to "Artists, songs, or podcasts".
  final String placeholder;

  /// Callback when search field is clicked.
  final VoidCallback? onTap;

  /// Optional focus node.
  final FocusNode? focusNode;

  const AppSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.placeholder = 'Artists, songs, or podcasts',
    this.onTap,
    this.focusNode,
  });

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  late final FocusNode _effectiveFocusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    } else {
      _effectiveFocusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _hasFocus = _effectiveFocusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56.0,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _hasFocus
            ? AppColors.surfaceContainerLowest
            : AppColors.surfaceContainerHighest,
        borderRadius: AppRadius.radiusFull,
        border: _hasFocus
            ? Border.all(color: AppColors.primary, width: 2.0)
            : null,
        boxShadow: _hasFocus ? AppShadows.shadowLow : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: _hasFocus ? AppColors.onSurface : AppColors.outline,
          ),
          AppSpacing.widthSm,
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _effectiveFocusNode,
              onChanged: widget.onChanged,
              onTap: widget.onTap,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
