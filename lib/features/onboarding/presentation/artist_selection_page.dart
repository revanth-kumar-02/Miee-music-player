import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/presentation/widgets/auth_components.dart';
import '../domain/artist_model.dart';
import '../providers/onboarding_providers.dart';
export '../../../shared/widgets/artist_avatar.dart';

/// Recreated Artist & Language Personalization screen strictly matching Stitch:
/// - Mobile: `05_mobile_miee_mobile_language_artist_personalization.html`
/// - Desktop / Web: `08_desktop_miee_web_artist_personalization.html`
class ArtistSelectionPage extends ConsumerStatefulWidget {
  const ArtistSelectionPage({super.key});

  @override
  ConsumerState<ArtistSelectionPage> createState() =>
      _ArtistSelectionPageState();
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
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: AuthPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            _buildTopBar(context, isDesktop: isDesktop),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  isDesktop ? 48 : 20,
                  isDesktop ? 24 : 12,
                  isDesktop ? 48 : 20,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 1200 : 540,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Narrative
                        _buildHeader(onboardingState, isDesktop: isDesktop),
                        const SizedBox(height: 20),

                        // Language Selection Chips
                        _buildLanguageSelector(onboardingState, notifier,
                            isDesktop: isDesktop),
                        const SizedBox(height: 16),

                        // Search Input Across Selected Languages
                        _buildSearchBar(notifier),
                        const SizedBox(height: 14),

                        // Selection Counter Badge
                        _buildCounterBadge(onboardingState),

                        // Error / Max Toast Banner
                        if (onboardingState.errorMessage != null) ...[
                          const SizedBox(height: 10),
                          _buildErrorBanner(onboardingState.errorMessage!),
                        ],
                        const SizedBox(height: 24),

                        // Grouped Artists by Language
                        if (onboardingState.isLoading &&
                            onboardingState.discoveredArtists.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40.0),
                              child: CircularProgressIndicator(
                                color: AuthPalette.primaryButton,
                              ),
                            ),
                          )
                        else
                          _buildGroupedArtists(
                              onboardingState, notifier, isDesktop: isDesktop),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Sticky Bottom Continuation Dock
            _buildBottomDock(onboardingState, isDesktop: isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, {required bool isDesktop}) {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
      ),
      decoration: const BoxDecoration(
        color: AuthPalette.background,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE9E8E6), width: 0.8),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : 540),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: AuthPalette.textPrimary,
                      ),
                      children: const [
                        TextSpan(text: 'miee'),
                        TextSpan(
                          text: '.',
                          style: TextStyle(color: AuthPalette.accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEEEC),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      'AUDIO SETUP',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AuthPalette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              // Step Indicator
              Row(
                children: [
                  Container(
                    width: isDesktop ? 140 : 80,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3E2E0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.66,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AuthPalette.primaryButton,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Step 2 of 3',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AuthPalette.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(OnboardingState state, {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFDADC),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                'TUNING ACOUSTIC PROFILE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: const Color(0xFF4B0014),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Which languages do you listen to?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: isDesktop ? 32 : 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AuthPalette.textPrimary,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select your musical languages, then choose 3 to 5 artists to calibrate your personalized sound sanctuary.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: isDesktop ? 15 : 13.5,
            fontWeight: FontWeight.w400,
            color: AuthPalette.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSelector(
      OnboardingState state, OnboardingNotifier notifier,
      {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACTIVE DIALECTS & TRADITIONS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AuthPalette.textSecondary,
              ),
            ),
            Text(
              'Tap to toggle languages',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AuthPalette.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: state.supportedLanguages.map((lang) {
              final isSelected = state.selectedLanguages.contains(lang);
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: InkWell(
                  onTap: () => notifier.toggleLanguage(lang),
                  borderRadius: BorderRadius.circular(9999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AuthPalette.primaryButton
                          : AuthPalette.cardSurface,
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(
                        color: isSelected
                            ? AuthPalette.primaryButton
                            : AuthPalette.cardBorder,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x081A0F12),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          lang,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AuthPalette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(OnboardingNotifier notifier) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AuthPalette.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuthPalette.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081A0F12),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: notifier.onSearchChanged,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: AuthPalette.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search artists across selected languages...',
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            color: AuthPalette.textMuted.withValues(alpha: 0.7),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AuthPalette.textMuted,
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AuthPalette.textMuted,
                  onPressed: () {
                    _searchController.clear();
                    notifier.onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCounterBadge(OnboardingState state) {
    final count = state.selectedArtists.length;
    final isReady = count >= 3 && count <= 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F3F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9E8E6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.stars_rounded,
                size: 20,
                color: isReady
                    ? AuthPalette.primaryButton
                    : AuthPalette.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                state.counterText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AuthPalette.textPrimary,
                ),
              ),
            ],
          ),
          Text(
            state.helperText,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isReady
                  ? AuthPalette.primaryButton
                  : AuthPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AuthPalette.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AuthPalette.errorRed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AuthPalette.errorRed,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AuthPalette.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedArtists(
      OnboardingState state, OnboardingNotifier notifier,
      {required bool isDesktop}) {
    final grouped = state.groupedArtists;

    if (grouped.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            children: [
              const Icon(
                Icons.person_search_rounded,
                size: 48,
                color: AuthPalette.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                'No artists found for your search',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AuthPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try selecting another language or clear your search term.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AuthPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: grouped.entries.map((entry) {
        final language = entry.key;
        final artists = entry.value;

        return Padding(
          padding: const EdgeInsets.only(bottom: 28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '$language Artists',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AuthPalette.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFEEEC),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          language,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AuthPalette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${artists.length} artists',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AuthPalette.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Artist Cards Horizontal Scroll (or Wrap on wide desktop)
              SizedBox(
                height: 142,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: artists.length,
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    final isSelected = state.selectedArtists
                        .any((a) => a.id == artist.id);

                    return _buildArtistCard(
                      artist: artist,
                      isSelected: isSelected,
                      onTap: () => notifier.toggleArtist(artist),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildArtistCard({
    required ArtistModel artist,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 104,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF4F3F1)
                : AuthPalette.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AuthPalette.primaryButton
                  : AuthPalette.cardBorder,
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x061A0F12),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar Stack with Checkmark Badge
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AuthPalette.primaryButton
                            : Colors.transparent,
                        width: 2.0,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.network(
                        artist.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFFEFEEEC),
                            child: Center(
                              child: Text(
                                artist.name.isNotEmpty
                                    ? artist.name[0]
                                    : 'A',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AuthPalette.primaryButton,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AuthPalette.primaryButton,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x201A0F12),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Artist Name
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: AuthPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),

              // Genre / Fan Label
              Text(
                artist.fanCount > 0
                    ? '${(artist.fanCount / 1000).toStringAsFixed(0)}k listeners'
                    : 'Artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AuthPalette.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomDock(OnboardingState state, {required bool isDesktop}) {
    final canContinue = state.canContinue;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 20,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        color: AuthPalette.cardSurface,
        border: Border(
          top: BorderSide(color: Color(0xFFE9E8E6), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x0C1A0F12),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : 540),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Selected Summary
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Artists (${state.selectedArtists.length}/5)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AuthPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canContinue
                        ? 'Profile ready to calibrate'
                        : 'Select 3 to 5 artists to continue',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: canContinue
                          ? AuthPalette.primaryButton
                          : AuthPalette.textMuted,
                      fontWeight:
                          canContinue ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),

              // Continue CTA
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: canContinue ? _handleContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AuthPalette.primaryButton,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE3E2E0),
                    disabledForegroundColor: const Color(0xFF897173),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: state.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Continue to Miee',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
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
