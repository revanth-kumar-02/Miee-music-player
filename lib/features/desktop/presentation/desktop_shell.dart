import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/midnight_velvet_tokens.dart';
import '../../../core/audio/providers.dart';
import 'views/desktop_local_library_view.dart';
import 'widgets/left_console_rail.dart';
import 'widgets/top_telemetry_header.dart';
import 'widgets/master_transport_deck.dart';
import 'widgets/session_queue_view.dart';

class DesktopShell extends ConsumerStatefulWidget {
  final Widget? child;

  const DesktopShell({
    super.key,
    this.child,
  });

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  DesktopNavSection _activeSection = DesktopNavSection.nowSpinning;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isQueuePanelOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSectionChanged(DesktopNavSection section) {
    setState(() {
      _activeSection = section;
    });
  }

  void _toggleQueuePanel() {
    setState(() {
      _isQueuePanelOpen = !_isQueuePanelOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () {
          final focus = FocusManager.instance.primaryFocus;
          if (focus != null && focus.context != null) {
            final isEditable = focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
            if (isEditable) return;
          }
          ref.read(playerControllerProvider.notifier).togglePlayPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final focus = FocusManager.instance.primaryFocus;
          if (focus != null && focus.context != null) {
            final isEditable = focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
            if (isEditable) return;
          }
          final state = ref.read(playerControllerProvider);
          final newPos = state.position - const Duration(seconds: 5);
          final clamped = newPos < Duration.zero ? Duration.zero : newPos;
          ref.read(playerControllerProvider.notifier).seek(clamped);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final focus = FocusManager.instance.primaryFocus;
          if (focus != null && focus.context != null) {
            final isEditable = focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
            if (isEditable) return;
          }
          final state = ref.read(playerControllerProvider);
          final newPos = state.position + const Duration(seconds: 5);
          final clamped = newPos > state.duration ? state.duration : newPos;
          ref.read(playerControllerProvider.notifier).seek(clamped);
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isQueuePanelOpen) {
            setState(() => _isQueuePanelOpen = false);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: MidnightVelvetTokens.canvasBase,
          body: Stack(
            children: [
              // 1. Primary Split Layout: Rail on left, Main Stage on right
              Row(
                children: [
                  // Left Console Rail
                  LeftConsoleRail(
                    activeSection: _activeSection,
                    onSectionChanged: _handleSectionChanged,
                    onCutNewCrate: () {
                      // Prompt cut new crate / playlist dialog
                    },
                  ),

                  // Main Stage Area + Optional Right Queue Drawer
                  Expanded(
                    child: Column(
                      children: [
                        // Top Telemetry Header
                        TopTelemetryHeader(
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                          onSearchSubmitted: (query) {
                            // Trigger search query
                          },
                        ),

                    // Stage Content Body with optional side queue panel
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: widget.child ?? _buildDefaultStageContent(),
                          ),
                          if (_isQueuePanelOpen) ...[
                            Container(
                              width: 380,
                              margin: const EdgeInsets.only(
                                right: 16,
                                top: 12,
                                bottom: MidnightVelvetTokens.masterDeckHeight +
                                    MidnightVelvetTokens.masterDeckBottomMargin +
                                    12,
                              ),
                              child: SessionQueueView(
                                onClose: _toggleQueuePanel,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Spacing buffer so scrolling content is not hidden behind the floating deck
                    if (!_isQueuePanelOpen)
                      const SizedBox(
                        height: MidnightVelvetTokens.masterDeckHeight +
                            MidnightVelvetTokens.masterDeckBottomMargin +
                            8,
                      ),
                  ],
                ),
              ),
            ],
          ),

          // 2. Floating Master Transport Deck Dock
          Positioned(
            left: MidnightVelvetTokens.consoleRailWidth,
            right: 0,
            bottom: 0,
            child: MasterTransportDeck(
              onToggleQueue: _toggleQueuePanel,
            ),
          ),
        ],
      ),
    ),
  ),
);
  }

  Widget _buildDefaultStageContent() {
    return const DesktopLocalLibraryView();
  }
}
