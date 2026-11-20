import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/midnight_velvet_tokens.dart';
import '../../../core/audio/providers.dart';
import '../../search/presentation/search_page.dart';
import '../../settings/presentation/settings_page.dart';
import 'views/desktop_crates_view.dart';
import 'views/desktop_dashboard_view.dart';
import 'views/desktop_heavy_rotation_view.dart';
import 'views/desktop_local_library_view.dart';
import 'views/desktop_master_albums_view.dart';
import 'views/desktop_session_history_view.dart';
import 'views/studio_now_spinning_view.dart';
import 'widgets/desktop_floating_player.dart';
import 'widgets/desktop_sidebar.dart';
import 'widgets/left_console_rail.dart';
import 'widgets/session_queue_view.dart';

class DesktopShell extends ConsumerStatefulWidget {
  final Widget? child;
  final String? currentPath;

  const DesktopShell({
    super.key,
    this.child,
    this.currentPath,
  });

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  // Default to Dashboard strictly reproducing the First Reference Image
  DesktopNavSection _activeSection = DesktopNavSection.dashboard;
  bool _isQueuePanelOpen = false;

  void _handleSectionChanged(DesktopNavSection section) {
    setState(() {
      _activeSection = section;
    });
    final path = widget.currentPath;
    if (path != null && path != '/home' && path != '/') {
      try {
        context.go('/home');
      } catch (_) {}
    }
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
            final isEditable =
                focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
            if (isEditable) return;
          }
          ref.read(playerControllerProvider.notifier).togglePlayPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final focus = FocusManager.instance.primaryFocus;
          if (focus != null && focus.context != null) {
            final isEditable =
                focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
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
            final isEditable =
                focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
            if (isEditable) return;
          }
          final state = ref.read(playerControllerProvider);
          final newPos = state.position + const Duration(seconds: 5);
          final clamped = newPos > state.duration ? state.duration : newPos;
          ref.read(playerControllerProvider.notifier).seek(clamped);
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          setState(() => _activeSection = DesktopNavSection.search);
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          setState(() => _activeSection = DesktopNavSection.search);
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
              // 1. Primary Split Layout: Narrow Sidebar (64px) on left, Stage on right
              Row(
                children: [
                  DesktopSidebar(
                    activeSection: _activeSection,
                    onSectionChanged: _handleSectionChanged,
                  ),

                  // Main Content Stage Area + Optional Right Queue Drawer
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _resolveStageWidget(),
                        ),
                        if (_isQueuePanelOpen) ...[
                          Container(
                            width: 380,
                            margin: const EdgeInsets.only(
                              right: 16,
                              top: 16,
                              bottom: 96,
                            ),
                            child: SessionQueueView(
                              onClose: _toggleQueuePanel,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // 2. Single Persistent Floating Pill Player (Bottom Centre)
              // Detached, floating over the dashboard with soft blur and shadow
              Positioned(
                left: DesktopSidebar.sidebarWidth,
                right: _isQueuePanelOpen ? 396 : 0,
                bottom: 22,
                child: Center(
                  child: DesktopFloatingPlayer(
                    onOpenNowSpinning: () {
                      setState(() {
                        _activeSection = DesktopNavSection.nowSpinning;
                      });
                    },
                    onToggleQueue: _toggleQueuePanel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resolveStageWidget() {
    final path = widget.currentPath;
    // When mounted on the root dashboard ('/home' or '/'):
    if (path == '/home' || path == '/') {
      return _buildActiveSectionStage();
    }
    // If an explicit child was provided (e.g. test harness or subroute):
    if (widget.child != null) {
      return Theme(
        data: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: MidnightVelvetTokens.canvasBase,
        ),
        child: widget.child!,
      );
    }
    // Fallback to active section
    return _buildActiveSectionStage();
  }

  Widget _buildActiveSectionStage() {
    switch (_activeSection) {
      case DesktopNavSection.dashboard:
        return DesktopDashboardView(
          onSearchTap: () => setState(() => _activeSection = DesktopNavSection.search),
          onSeeAllContinue: () => setState(() => _activeSection = DesktopNavSection.sessionHistory),
          onSeeAllMixes: () => setState(() => _activeSection = DesktopNavSection.cratesAndMixes),
        );
      case DesktopNavSection.cratesAndMixes:
        return const DesktopCratesView();
      case DesktopNavSection.nowSpinning:
        return const StudioNowSpinningView();
      case DesktopNavSection.search:
        return const SearchPage();
      case DesktopNavSection.heavyRotation:
        return const DesktopHeavyRotationView();
      case DesktopNavSection.sessionHistory:
        return const DesktopSessionHistoryView();
      case DesktopNavSection.studioCatalog:
        return const DesktopLocalLibraryView();
      case DesktopNavSection.masterAlbums:
        return const DesktopMasterAlbumsView();
      case DesktopNavSection.settings:
        return const SettingsPage();
    }
  }
}
