import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../features/library/providers/library_providers.dart';

enum DesktopNavSection {
  nowSpinning,
  cratesAndMixes,
  studioCatalog,
  heavyRotation,
  sessionHistory,
  masterAlbums,
}

class LeftConsoleRail extends ConsumerWidget {
  final DesktopNavSection activeSection;
  final ValueChanged<DesktopNavSection> onSectionChanged;
  final VoidCallback? onCutNewCrate;

  const LeftConsoleRail({
    super.key,
    required this.activeSection,
    required this.onSectionChanged,
    this.onCutNewCrate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final favoritesCount = favorites.length;
    final playlists = ref.watch(userPlaylistsProvider);

    return Container(
      width: MidnightVelvetTokens.consoleRailWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: MidnightVelvetTokens.surfaceLayer1,
        border: Border(
          right: BorderSide(
            color: MidnightVelvetTokens.hairlineRim,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Brand Header
              _buildBrandHeader(),

              const SizedBox(height: 16),

              // 2. Scrollable Navigation Index & Playlists
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // --- SECTION 1: INDEX ---
                    _buildSectionHeader('INDEX'),
                    _buildNavItem(
                      icon: Icons.album_outlined,
                      activeIcon: Icons.album,
                      label: 'Now Spinning',
                      isSelected: activeSection == DesktopNavSection.nowSpinning,
                      onTap: () => onSectionChanged(DesktopNavSection.nowSpinning),
                    ),
                    _buildNavItem(
                      icon: Icons.graphic_eq_rounded,
                      activeIcon: Icons.graphic_eq_rounded,
                      label: 'Crates & Mixes',
                      isSelected: activeSection == DesktopNavSection.cratesAndMixes,
                      onTap: () => onSectionChanged(DesktopNavSection.cratesAndMixes),
                    ),
                    _buildNavItem(
                      icon: Icons.grid_view_rounded,
                      activeIcon: Icons.grid_view_rounded,
                      label: 'Studio Catalog',
                      isSelected: activeSection == DesktopNavSection.studioCatalog,
                      onTap: () => onSectionChanged(DesktopNavSection.studioCatalog),
                    ),

                    const SizedBox(height: 24),

                    // --- SECTION 2: COLLECTION ---
                    _buildSectionHeader('COLLECTION'),
                    _buildNavItem(
                      icon: Icons.favorite_border_rounded,
                      activeIcon: Icons.favorite_rounded,
                      label: 'Heavy Rotation',
                      badge: favoritesCount > 0 ? '$favoritesCount' : null,
                      isSelected: activeSection == DesktopNavSection.heavyRotation,
                      onTap: () => onSectionChanged(DesktopNavSection.heavyRotation),
                    ),
                    _buildNavItem(
                      icon: Icons.history_rounded,
                      activeIcon: Icons.history_rounded,
                      label: 'Session History',
                      isSelected: activeSection == DesktopNavSection.sessionHistory,
                      onTap: () => onSectionChanged(DesktopNavSection.sessionHistory),
                    ),
                    _buildNavItem(
                      icon: Icons.radio_button_checked_rounded,
                      activeIcon: Icons.radio_button_checked_rounded,
                      label: 'Master Albums',
                      isSelected: activeSection == DesktopNavSection.masterAlbums,
                      onTap: () => onSectionChanged(DesktopNavSection.masterAlbums),
                    ),

                    const SizedBox(height: 24),

                    // --- SECTION 3: RECORD CRATES ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader('RECORD CRATES'),
                        IconButton(
                          icon: const Icon(
                            Icons.add_rounded,
                            size: 16,
                            color: MidnightVelvetTokens.textSecondary,
                          ),
                          tooltip: 'Cut New Crate',
                          onPressed: onCutNewCrate,
                          splashRadius: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...playlists.take(8).map((p) => _buildCrateItem(p.name, p.tracks.length)),
                  ],
                ),
              ),

              // 3. Docked Audiophile Telemetry Module
              _buildDacTelemetryFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 22, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: MidnightVelvetTokens.primaryEmber,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: MidnightVelvetTokens.glowEmberLow,
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'miee.',
            style: MidnightVelvetTokens.fontDisplayMedium.copyWith(
              fontSize: 20,
              letterSpacing: -0.04 * 20,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: MidnightVelvetTokens.amberChampagne.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: MidnightVelvetTokens.amberChampagne.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Text(
              'STUDIO',
              style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.08 * 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 4),
      child: Text(
        title,
        style: MidnightVelvetTokens.fontLabelSmall,
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: MidnightVelvetTokens.surfaceCardHover,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected ? MidnightVelvetTokens.surfaceCard : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(color: MidnightVelvetTokens.hairlineRimHighlight, width: 1.0)
                  : null,
            ),
            child: Row(
              children: [
                if (isSelected)
                  Container(
                    width: 3,
                    height: 18,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: MidnightVelvetTokens.primaryEmber,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [
                        BoxShadow(
                          color: MidnightVelvetTokens.glowEmberMid,
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 18,
                  color: isSelected
                      ? MidnightVelvetTokens.textDisplay
                      : MidnightVelvetTokens.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                      color: isSelected
                          ? MidnightVelvetTokens.textDisplay
                          : MidnightVelvetTokens.textSecondary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: MidnightVelvetTokens.primaryEmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.primaryEmber,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCrateItem(String name, int trackCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(6),
        hoverColor: MidnightVelvetTokens.surfaceCardHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              const Icon(
                Icons.circle,
                size: 6,
                color: MidnightVelvetTokens.amberChampagne,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                    fontSize: 13,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$trackCount',
                style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                  fontSize: 10,
                  color: MidnightVelvetTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDacTelemetryFooter() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.canvasBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: MidnightVelvetTokens.emeraldStream,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MidnightVelvetTokens.emeraldStream,
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AUDIO ENGINE: ACTIVE',
                  style: MidnightVelvetTokens.fontLabelSmall.copyWith(
                    fontSize: 9,
                    color: MidnightVelvetTokens.textMuted,
                    letterSpacing: 0.05 * 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Direct Output • 48.0 kHz',
            style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Bit-Perfect Stream Pipeline',
            style: MidnightVelvetTokens.fontBodyMedium.copyWith(
              fontSize: 11,
              color: MidnightVelvetTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
