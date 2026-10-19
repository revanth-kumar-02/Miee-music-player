import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/providers/profile_providers.dart';
import '../../profile/presentation/profile_controller.dart';
import '../data/artist_discovery_repository.dart';
import '../domain/artist_model.dart';

final artistRepositoryProvider = Provider<ArtistRepository>((ref) {
  return DeezerArtistRepository();
});

class OnboardingState {
  final List<ArtistSummary> selectedArtists;
  final List<ArtistModel> discoveredArtists;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String searchQuery;
  final String selectedLanguage;
  final Set<String> selectedLanguages;
  final List<String> supportedLanguages;

  const OnboardingState({
    this.selectedArtists = const [],
    this.discoveredArtists = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.searchQuery = '',
    this.selectedLanguage = 'All',
    this.selectedLanguages = const {'Tamil', 'Hindi', 'English'},
    this.supportedLanguages = const [
      'Tamil',
      'Hindi',
      'English',
      'Telugu',
      'Malayalam',
      'Kannada',
      'Punjabi',
      'Bengali',
      'Marathi',
    ],
  });

  bool get canContinue =>
      selectedArtists.length >= 3 && selectedArtists.length <= 5 && !isSaving;

  String get counterText => '${selectedArtists.length} of 5 selected';

  String get helperText {
    if (selectedArtists.length < 3) {
      final remaining = 3 - selectedArtists.length;
      return 'Select $remaining more to continue';
    }
    return 'Ready to continue';
  }

  /// Groups artists by language according to the currently active languages
  Map<String, List<ArtistModel>> get groupedArtists {
    final Map<String, List<ArtistModel>> grouped = {};
    final query = searchQuery.trim().toLowerCase();

    for (final lang in supportedLanguages) {
      if (!selectedLanguages.contains(lang)) continue;

      final artistsForLang = discoveredArtists.where((artist) {
        final matchesLang = artist.languages.contains(lang);
        if (!matchesLang) return false;
        if (query.isEmpty) return true;
        return artist.name.toLowerCase().contains(query);
      }).toList();

      if (artistsForLang.isNotEmpty) {
        grouped[lang] = artistsForLang;
      }
    }
    return grouped;
  }

  OnboardingState copyWith({
    List<ArtistSummary>? selectedArtists,
    List<ArtistModel>? discoveredArtists,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    String? searchQuery,
    String? selectedLanguage,
    Set<String>? selectedLanguages,
    List<String>? supportedLanguages,
    bool clearError = false,
  }) {
    return OnboardingState(
      selectedArtists: selectedArtists ?? this.selectedArtists,
      discoveredArtists: discoveredArtists ?? this.discoveredArtists,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      selectedLanguages: selectedLanguages ?? this.selectedLanguages,
      supportedLanguages: supportedLanguages ?? this.supportedLanguages,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final Ref _ref;
  final ArtistRepository _repository;
  Timer? _debounceTimer;

  OnboardingNotifier(this._ref, this._repository)
      : super(const OnboardingState(isLoading: true)) {
    loadAllArtists();
  }

  Future<void> loadAllArtists() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final artists = await _repository.getPopularArtists();
      state = state.copyWith(
        discoveredArtists: artists,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to load artists. Please check your connection.',
      );
    }
  }

  void toggleLanguage(String language) {
    final current = Set<String>.from(state.selectedLanguages);
    if (current.contains(language)) {
      if (current.length > 1) {
        current.remove(language);
      }
    } else {
      current.add(language);
    }
    state = state.copyWith(selectedLanguages: current);
  }

  void setLanguage(String language) {
    if (language == 'All') {
      state = state.copyWith(
        selectedLanguage: 'All',
        selectedLanguages: Set<String>.from(state.supportedLanguages),
      );
    } else {
      state = state.copyWith(
        selectedLanguage: language,
        selectedLanguages: {language},
      );
    }
  }

  void onSearchChanged(String query) {
    _debounceTimer?.cancel();
    state = state.copyWith(searchQuery: query);

    if (query.trim().isEmpty) {
      loadAllArtists();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await _repository.searchArtists(query);
      state = state.copyWith(
        discoveredArtists: results,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Search failed. Please try again.',
      );
    }
  }

  void toggleArtist(ArtistModel artist) {
    final current = List<ArtistSummary>.from(state.selectedArtists);
    final existingIndex = current.indexWhere((a) => a.id == artist.id);

    if (existingIndex >= 0) {
      current.removeAt(existingIndex);
      state = state.copyWith(selectedArtists: current, clearError: true);
    } else {
      if (current.length >= 5) {
        state = state.copyWith(
          errorMessage: 'Maximum 5 artists selected. Deselect one to add another.',
        );
        return;
      }
      current.add(artist.toSummary());
      state = state.copyWith(selectedArtists: current, clearError: true);
    }
  }

  Future<UserProfile?> completeOnboarding() async {
    if (state.selectedArtists.length < 3) {
      state = state.copyWith(
        errorMessage: 'Please select at least 3 favorite artists to continue.',
      );
      return null;
    }
    if (state.selectedArtists.length > 5) {
      state = state.copyWith(
        errorMessage: 'Maximum of 5 favorite artists allowed.',
      );
      return null;
    }

    final user = _ref.read(currentAuthUserProvider);
    if (user == null) {
      state = state.copyWith(
        errorMessage: 'User session not found. Please log in again.',
      );
      return null;
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final profileRepo = _ref.read(userProfileRepositoryProvider);
      final updatedProfile = await profileRepo.completeOnboarding(
        uid: user.uid,
        artists: state.selectedArtists,
        displayName: user.displayName,
        email: user.email,
      );

      // Update the user profile notifier state immediately
      _ref.read(userProfileNotifierProvider.notifier).updateProfileLocally(updatedProfile);

      // Also ensure the local ProfileController is updated with the real name
      final effectiveName = updatedProfile.displayName.trim();
      if (effectiveName.isNotEmpty &&
          effectiveName != 'Miee Listener' &&
          effectiveName != 'Miee User') {
        final currentLocal = _ref.read(profileProvider);
        await _ref.read(profileProvider.notifier).updateProfile(
          displayName: effectiveName,
          favoriteGenre: currentLocal.favoriteGenre,
          favoriteArtist: currentLocal.favoriteArtist,
        );
      }

      state = state.copyWith(isSaving: false);
      return updatedProfile;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage:
            'Failed to save preferences: ${e.toString().replaceFirst("Exception: ", "")}',
      );
      return null;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final onboardingNotifierProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  final repo = ref.watch(artistRepositoryProvider);
  return OnboardingNotifier(ref, repo);
});
