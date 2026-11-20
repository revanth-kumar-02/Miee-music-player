import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import 'left_console_rail.dart';

/// The compact icon navigation sidebar strictly reproducing the
/// First Reference Design Image (Miee Desktop — Midnight Velvet & Warm Studio).
/// Width: ~64-68px, icon-only layout, champagne amber active-state indicator pill.
class DesktopSidebar extends ConsumerWidget {
  final DesktopNavSection activeSection;
  final ValueChanged<DesktopNavSection> onSectionChanged;
  final VoidCallback? onLogout;

  const DesktopSidebar({
    super.key,
    required this.activeSection,
    required this.onSectionChanged,
    this.onLogout,
  });

  static const double sidebarWidth = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: sidebarWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xF02A272B), // Warmer graphite with subtle bronze undertone
        border: Border(
          right: BorderSide(
            color: Color(0x1FFFFFFF), // Subtle 1px graphite separator
            width: 1.0,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: MidnightVelvetTokens.glassBlurSigma,
            sigmaY: MidnightVelvetTokens.glassBlurSigma,
          ),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── Top Brand Wordmark ─────────────────────────────────────
              Text(
                'Miee',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFBA9B7B), // Warm muted champagne beige gold (measured RGB 163, 136, 111)
                  letterSpacing: -0.2,
                ),
              ),

              const SizedBox(height: 52), // Refined vertical gap matching reference header alignment

              // ── Core Navigation Icons ──────────────────────────────────
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildNavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_outlined, // Delicate thin outline matching reference
                      section: DesktopNavSection.dashboard,
                      tooltip: 'Dashboard',
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view_outlined,
                      section: DesktopNavSection.cratesAndMixes,
                      tooltip: 'Crates & Mixes',
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      icon: Icons.bar_chart_rounded,
                      activeIcon: Icons.bar_chart_rounded,
                      section: DesktopNavSection.nowSpinning,
                      tooltip: 'Studio Now Spinning',
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      icon: Icons.search_rounded,
                      activeIcon: Icons.search_rounded,
                      section: DesktopNavSection.search,
                      tooltip: 'Search Studio',
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      icon: Icons.queue_music_rounded,
                      activeIcon: Icons.queue_music_rounded,
                      section: DesktopNavSection.heavyRotation,
                      tooltip: 'Heavy Rotation',
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      icon: Icons.folder_outlined,
                      activeIcon: Icons.folder_outlined,
                      section: DesktopNavSection.studioCatalog,
                      tooltip: 'Studio Catalog',
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings_outlined,
                      section: DesktopNavSection.settings,
                      tooltip: 'Settings',
                    ),
                  ],
                ),
              ),

              // ── Bottom Utility Icons ───────────────────────────────────
              _buildUtilityItem(
                icon: Icons.info_outline_rounded,
                tooltip: 'System Info & Diagnostics',
                hasBadge: true,
                onTap: () {},
              ),
              const SizedBox(height: 12),
              _buildUtilityItem(
                icon: Icons.logout_rounded,
                tooltip: 'Disconnect Session',
                hasBadge: false,
                onTap: onLogout ?? () {},
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required DesktopNavSection section,
    required String tooltip,
  }) {
    final isSelected = activeSection == section;

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        // Left active indicator pill
        if (isSelected)
          Positioned(
            left: 0,
            child: Container(
              width: 2.5,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFFD5AD8A), // Refined warm champagne gold (RGB 213, 173, 138)
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33D5AD8A),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),

        // Centered icon button
        Center(
          child: Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              onTap: () => onSectionChanged(section),
              borderRadius: BorderRadius.circular(9.5),
              hoverColor: const Color(0x14FFFFFF),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 48,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0x385A3F2C) // Refined translucent warm bronze (measured RGB 75, 58, 48)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9.5),
                ),
                child: Center(
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    size: 16.5, // Delicate refined outline stroke matching reference
                    color: isSelected
                        ? const Color(0xFFE5C29F) // Champagne gold (never saturated orange)
                        : const Color(0xFF78716C), // Muted graphite
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUtilityItem({
    required IconData icon,
    required String tooltip,
    required bool hasBadge,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9.5),
        hoverColor: const Color(0x14FFFFFF),
        child: SizedBox(
          width: 48,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 16.5,
                color: const Color(0xFF78716C),
              ),
              if (hasBadge)
                Positioned(
                  top: 7,
                  right: 9,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE5A96A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x40E5A96A),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
