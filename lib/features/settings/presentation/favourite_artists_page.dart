import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/artist_avatar.dart';
import '../../auth/providers/auth_providers.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_controller.dart';
import '../../profile/providers/profile_providers.dart';

/// Dedicated screen for managing the user's favourite artists from Settings.
///
/// Features:
/// - Pre-populates existing saved artists from [userProfileNotifierProvider].
/// - Real-time search and language filtering.
/// - Clear visual tray for currently selected artists (min 1, max 5).
/// - High-contrast light and dark theme styling following Anti-AI-slop standards.
/// - Direct persistence via [userProfileRepositoryProvider] and [userProfileNotifierProvider].
class FavouriteArtistsPage extends ConsumerStatefulWidget {
  const FavouriteArtistsPage({super.key});

  @override
  ConsumerState<FavouriteArtistsPage> createState() =>
      _FavouriteArtistsPageState();
}

class _FavouriteArtistsPageState extends ConsumerState<FavouriteArtistsPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<ArtistSummary> _selectedArtists = [];
  List<ArtistModel> _discoveredArtists = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String _selectedLanguage = 'All';
  String _searchQuery = '';
  bool _hasInitializedSelection = false;

  static const List<String> _supportedLanguages = [
    'All',
    'Tamil',
    'Hindi',
    'English',
    'Telugu',
    'Malayalam',
    'Kannada',
    'Punjabi',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialArtists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialArtists() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(artistRepositoryProvider);
      final artists = await repo.getPopularArtists();
      if (mounted) {
        setState(() {
          _discoveredArtists = artists;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _searchQuery = query;

    if (query.trim().isEmpty) {
      _loadInitialArtists();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        final repo = ref.read(artistRepositoryProvider);
        final results = await repo.searchArtists(query.trim());
        if (mounted) {
          setState(() {
            _discoveredArtists = results;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  void _toggleArtist(ArtistModel artist) {
    final existingIndex =
        _selectedArtists.indexWhere((a) => a.id == artist.id);

    setState(() {
      if (existingIndex >= 0) {
        _selectedArtists.removeAt(existingIndex);
      } else {
        if (_selectedArtists.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can select up to 5 favorite artists.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedArtists.add(artist.toSummary());
      }
    });
  }

  void _removeSelectedArtist(ArtistSummary artist) {
    setState(() {
      _selectedArtists.removeWhere((a) => a.id == artist.id);
    });
  }

  Future<void> _savePreferences() async {
    if (_selectedArtists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 favorite artist.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = ref.read(currentAuthUserProvider);
      final profileState = ref.read(userProfileNotifierProvider);
      final existingProfile = profileState.profile;

      final updatedProfile = (existingProfile ??
              UserProfile.initial(
                uid: user?.uid ?? 'guest',
                email: user?.email ?? '',
                displayName: user?.displayName ?? 'Miee Listener',
              ))
          .copyWith(
        selectedArtists: _selectedArtists,
        selectedArtistIds: _selectedArtists.map((a) => a.id).toList(),
        onboardingCompleted: true,
      );

      final repo = ref.read(userProfileRepositoryProvider);
      await repo.saveUserProfile(updatedProfile);
      ref
          .read(userProfileNotifierProvider.notifier)
          .updateProfileLocally(updatedProfile);

      // Keep local ProfileController synced
      final effectiveName = updatedProfile.displayName.trim();
      if (effectiveName.isNotEmpty &&
          effectiveName != 'Miee Listener' &&
          effectiveName != 'Miee User') {
        final currentLocal = ref.read(profileProvider);
        await ref.read(profileProvider.notifier).updateProfile(
              displayName: effectiveName,
              favoriteGenre: currentLocal.favoriteGenre,
              favoriteArtist: _selectedArtists.isNotEmpty
                  ? _selectedArtists.first.name
                  : currentLocal.favoriteArtist,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Favourite artists updated'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preferences: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<ArtistModel> get _filteredArtists {
    if (_selectedLanguage == 'All') return _discoveredArtists;
    return _discoveredArtists
        .where((a) => a.matchesLanguage(_selectedLanguage))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(userProfileNotifierProvider);
    if (!_hasInitializedSelection && profileState.profile != null) {
      if (profileState.profile!.selectedArtists.isNotEmpty) {
        _selectedArtists =
            List<ArtistSummary>.from(profileState.profile!.selectedArtists);
      }
      _hasInitializedSelection = true;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF131418) : AppColors.vanillaCream;
    final cardBg = isDark ? const Color(0xFF1E1F24) : AppColors.white;
    final primaryText = isDark ? const Color(0xFFF6F6F4) : AppColors.cocoaPlum;
    final secondaryText =
        isDark ? const Color(0xFFA1A1AA) : AppColors.mutedMauve;
    final borderColor = isDark ? Colors.white12 : AppColors.oatBeige;

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 800;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppHeader(
          title: 'Favourite Artists',
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: primaryText),
            tooltip: 'Back',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/settings');
              }
            },
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                children: [
                  // Top summary & selection tray
                  _buildSelectionTray(
                    cardBg: cardBg,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    borderColor: borderColor,
                  ),

                  // Search & Language filters
                  _buildFilterSection(
                    cardBg: cardBg,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    borderColor: borderColor,
                  ),

                  // Artist Grid / List
                  Expanded(
                    child: _isLoading && _discoveredArtists.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          )
                        : _buildArtistGrid(
                            isDesktop: isDesktop,
                            cardBg: cardBg,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                            borderColor: borderColor,
                          ),
                  ),

                  // Sticky Bottom Dock
                  _buildBottomDock(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionTray({
    required Color cardBg,
    required Color primaryText,
    required Color secondaryText,
    required Color borderColor,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current Selection',
                style: GoogleFonts.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryText,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _selectedArtists.isNotEmpty
                      ? AppColors.primary.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedArtists.isNotEmpty
                        ? AppColors.primary.withOpacity(0.4)
                        : borderColor,
                  ),
                ),
                child: Text(
                  '${_selectedArtists.length} of 5 selected',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _selectedArtists.isNotEmpty
                        ? AppColors.primary
                        : secondaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_selectedArtists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Select 1 to 5 artists to personalize your daily mixes and recommendations.',
                style: GoogleFonts.geist(fontSize: 13, color: secondaryText),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedArtists.map((artist) {
                return Chip(
                  avatar: ArtistAvatar(
                    name: artist.name,
                    imageUrl: artist.imageUrl,
                    radius: 12,
                  ),
                  label: Text(
                    artist.shortDisplayName,
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: primaryText,
                    ),
                  ),
                  deleteIcon: Icon(Icons.close_rounded,
                      size: 14, color: secondaryText),
                  onDeleted: () => _removeSelectedArtist(artist),
                  backgroundColor: AppColors.primary.withOpacity(0.08),
                  side: BorderSide(
                    color: AppColors.primary.withOpacity(0.25),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterSection({
    required Color cardBg,
    required Color primaryText,
    required Color secondaryText,
    required Color borderColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // Search Input
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: GoogleFonts.geist(color: primaryText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search any artist (e.g. A. R. Rahman, Jonita...)',
              hintStyle: GoogleFonts.geist(color: secondaryText, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: secondaryText, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: secondaryText, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: cardBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Language filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _supportedLanguages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final lang = _supportedLanguages[index];
                final isSelected = _selectedLanguage == lang;
                return ChoiceChip(
                  label: Text(lang),
                  selected: isSelected,
                  labelStyle: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.white : primaryText,
                  ),
                  selectedColor: AppColors.primary,
                  backgroundColor: cardBg,
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : borderColor,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedLanguage = lang);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistGrid({
    required bool isDesktop,
    required Color cardBg,
    required Color primaryText,
    required Color secondaryText,
    required Color borderColor,
  }) {
    final artists = _filteredArtists;

    if (artists.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 48, color: secondaryText),
            const SizedBox(height: 12),
            Text(
              'No artists found for "$_searchQuery"',
              style: GoogleFonts.geist(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try searching for another name or change the language filter.',
              style: GoogleFonts.geist(fontSize: 12, color: secondaryText),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 4 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: isDesktop ? 1.4 : 1.25,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final isSelected = _selectedArtists.any((a) => a.id == artist.id);

        return Material(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _toggleArtist(artist),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : borderColor,
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ArtistAvatar(
                        name: artist.name,
                        imageUrl: artist.imageUrl,
                        radius: 26,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? AppColors.primary : primaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist.languages.isNotEmpty
                            ? artist.languages.join(' · ')
                            : (artist.fanCount > 0
                                ? '${(artist.fanCount / 1000).toStringAsFixed(0)}k fans'
                                : 'Artist'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.geist(
                          fontSize: 11,
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ),
                  if (isSelected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomDock({
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _isSaving ? null : _savePreferences,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Save Preferences (${_selectedArtists.length} of 5)',
                    style: GoogleFonts.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
