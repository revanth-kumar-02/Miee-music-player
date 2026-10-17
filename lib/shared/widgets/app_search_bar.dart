import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/app_colors.dart';

/// Reusable Search Bar input styled for Miee's reference design.
/// Clean white/cream pill container with search icon, clear button, and refined typography.
class AppSearchBar extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String placeholder;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  const AppSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.placeholder = 'Search songs, artists, albums...',
    this.onTap,
    this.focusNode,
    this.onSubmitted,
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
    final hasText = widget.controller?.text.isNotEmpty ?? false;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 46.0,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: _hasFocus ? AppColors.cocoaPlum : AppColors.oatBeige,
          width: _hasFocus ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cocoaPlum.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.mutedMauve,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _effectiveFocusNode,
              onChanged: (text) {
                setState(() {});
                widget.onChanged?.call(text);
              },
              onTap: widget.onTap,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.geist(
                fontSize: 14,
                color: AppColors.cocoaPlum,
              ),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: GoogleFonts.geist(
                  fontSize: 13.5,
                  color: AppColors.mutedMauve.withOpacity(0.8),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.mutedMauve,
              splashRadius: 16,
              onPressed: () {
                widget.controller?.clear();
                widget.onChanged?.call('');
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}
