import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../domain/artist_model.dart';
import '../providers/onboarding_providers.dart';

class ArtistSelectionPage extends ConsumerStatefulWidget {
  const ArtistSelectionPage({super.key});

  @override
  ConsumerState<ArtistSelectionPage> createState() => _ArtistSelectionPageState();
}

class _ArtistSelectionPageState extends ConsumerState<ArtistSelectionPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final notifier = ref.read(onboardingNotifierProvider.notifier);
    final profile = await notifier.completeOnboarding();
    if (profile != null && mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingNotifierProvider);
    final notifier = ref.read(onboardingNotifierProvider.notifier);

    final selectedCount = onboardingState.selectedArtists.length;
    final canContinue = onboardingState.canContinue;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header & Instructions
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.marginMobile,
                AppSpacing.marginMobile,
                AppSpacing.marginMobile,
                AppSpacing.marginMobile / 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pick Your Sound',
                    style: AppTypography.headlineLargeMobile.copyWith(
                      color: AppColors.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  AppSpacing.heightXs,
                  Text(
                    'Select 3 to 5 artists you love to curate your personalized music stream.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.heightMd,

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: AppRadius.radiusMd,
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: notifier.onSearchChanged,
                      style: AppTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search any artist (e.g. Coldplay, Taylor Swift)',
                        hintStyle: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  notifier.onSearchChanged('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                      ),
                    ),
                  ),

                  // Language Filter Chips Shelf
                  Container(
                    height: 38,
                    margin: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: onboardingState.supportedLanguages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final lang = onboardingState.supportedLanguages[index];
                        final isSelected = lang == onboardingState.selectedLanguage;

                        return GestureDetector(
                          onTap: () => notifier.setLanguage(lang),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : AppColors.surfaceContainerLow,
                              borderRadius: AppRadius.radiusFull,
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                              ),
                              boxShadow: isSelected ? AppShadows.shadowLow : null,
                            ),
                            child: Center(
                              child: Text(
                                lang,
                                style: AppTypography.labelSmall.copyWith(
                                  color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Selected Artists Chips Shelf (if any selected)
            if (onboardingState.selectedArtists.isNotEmpty) ...[
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: onboardingState.selectedArtists.length,
                  separatorBuilder: (_, __) => AppSpacing.widthSm,
                  itemBuilder: (context, index) {
                    final artist = onboardingState.selectedArtists[index];
                    return Chip(
                      avatar: ArtistAvatar(
                        imageUrl: artist.imageUrl,
                        name: artist.name,
                        radius: 12,
                      ),
                      label: Text(
                        artist.name,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        notifier.toggleArtist(
                          ArtistModel(
                            id: artist.id,
                            name: artist.name,
                            imageUrl: artist.imageUrl,
                          ),
                        );
                      },
                      backgroundColor: AppColors.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.radiusFull,
                        side: const BorderSide(color: AppColors.outlineVariant),
                      ),
                    );
                  },
                ),
              ),
              AppSpacing.heightSm,
            ],

            // Error Banner (if any)
            if (onboardingState.errorMessage != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: AppRadius.radiusSm,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.error, size: 18),
                      AppSpacing.widthSm,
                      Expanded(
                        child: Text(
                          onboardingState.errorMessage!,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.heightSm,
            ],

            // Artists Grid
            Expanded(
              child: onboardingState.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    )
                  : onboardingState.discoveredArtists.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.music_off, size: 48, color: AppColors.outline),
                              AppSpacing.heightSm,
                              Text(
                                'No artists found for "${onboardingState.searchQuery}"',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              AppSpacing.heightSm,
                              TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  notifier.onSearchChanged('');
                                },
                                child: const Text('Show Popular Artists'),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.marginMobile,
                            AppSpacing.sm,
                            AppSpacing.marginMobile,
                            100, // Space for bottom bar
                          ),
                          physics: const BouncingScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.78,
                            crossAxisSpacing: AppSpacing.marginMobile / 2,
                            mainAxisSpacing: AppSpacing.marginMobile / 2,
                          ),
                          itemCount: onboardingState.discoveredArtists.length,
                          itemBuilder: (context, index) {
                            final artist = onboardingState.discoveredArtists[index];
                            final isSelected = onboardingState.selectedArtists
                                .any((a) => a.id == artist.id);

                            return _ArtistCard(
                              artist: artist,
                              isSelected: isSelected,
                              onTap: () => notifier.toggleArtist(artist),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),

      // Bottom Persistent Action Bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(AppSpacing.marginMobile),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Selection Counter Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selectedCount >= 3
                      ? AppColors.surfaceContainerHigh
                      : AppColors.surfaceContainerLow,
                  borderRadius: AppRadius.radiusFull,
                  border: Border.all(
                    color: selectedCount >= 3 ? AppColors.primary : AppColors.outlineVariant,
                  ),
                ),
                child: Text(
                  onboardingState.counterText,
                  style: AppTypography.labelMedium.copyWith(
                    color: selectedCount >= 3 ? AppColors.onSurface : AppColors.onSurfaceVariant,
                    fontWeight: selectedCount >= 3 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              AppSpacing.widthMd,

              // Continue Button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: canContinue ? _handleContinue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      disabledBackgroundColor: AppColors.surfaceContainerHigh,
                      disabledForegroundColor: AppColors.outline,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.radiusMd,
                      ),
                    ),
                    child: onboardingState.isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            selectedCount < 3
                                ? 'Pick ${3 - selectedCount} more'
                                : 'Continue to Music',
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
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

/// Polished, resilient circular artist avatar supporting smooth network loading,
/// verified image validation, memory-safe decoding, and graceful neutral fallbacks.
class ArtistAvatar extends StatelessWidget {
  final String imageUrl;
  final String name;
  final double radius;

  const ArtistAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 36.0,
  });

  bool get _hasValidUrl {
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) return false;
    if (imageUrl.contains('d41d8cd98f00b204e9800998ecf8427e')) return false;
    if (imageUrl.contains('/artist//')) return false;
    return true;
  }

  Widget _buildFallback() {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: radius * 2,
      height: radius * 2,
      color: AppColors.surfaceContainerHighest,
      child: Center(
        child: Text(
          initial,
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.7,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: _hasValidUrl
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                cacheWidth: 200,
                cacheHeight: 200,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: AppColors.surfaceContainerHighest,
                    child: Center(
                      child: SizedBox(
                        width: radius * 0.5,
                        height: radius * 0.5,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final ArtistModel artist;
  final bool isSelected;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.artist,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceContainerHigh : AppColors.surfaceContainerLow,
          borderRadius: AppRadius.radiusMd,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected ? AppShadows.shadowLow : const [],
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Avatar with Selection Indicator
            Stack(
              alignment: Alignment.center,
              children: [
                ArtistAvatar(
                  imageUrl: artist.imageUrl,
                  name: artist.name,
                  radius: 36,
                ),
                if (isSelected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
            AppSpacing.heightSm,

            // Artist Name
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(
                color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
