import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../media/providers/media_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/playback_state.dart';
import '../../../features/library/providers/library_providers.dart';

class GenresPage extends ConsumerStatefulWidget {
  const GenresPage({super.key});

  @override
  ConsumerState<GenresPage> createState() => _GenresPageState();
}

class _GenresPageState extends ConsumerState<GenresPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isScrolled = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.offset > 10.0 && !_isScrolled) {
      setState(() => _isScrolled = true);
    } else if (_scrollController.offset <= 10.0 && _isScrolled) {
      setState(() => _isScrolled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genres = ref.watch(genresProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final query = _searchController.text.toLowerCase().trim();
    final filteredGenres = genres.where((genre) {
      return genre.name.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: 'Genres',
        isScrolled: _isScrolled,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: false,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Search Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.marginMobile,
                        vertical: AppSpacing.md,
                      ),
                      child: AppSearchBar(
                        controller: _searchController,
                        placeholder: 'Search genres...',
                        onSubmitted: (_) {},
                      ),
                    ),
                  ),

                  if (filteredGenres.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        title: 'No genres found',
                        message: 'Try checking your search query.',
                        icon: Icons.music_note_outlined,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.marginMobile,
                        right: AppSpacing.marginMobile,
                        bottom: 120.0,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final genre = filteredGenres[index];

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: ListTile(
                                leading: Container(
                                  width: 48.0,
                                  height: 48.0,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: const Icon(Icons.music_note, color: AppColors.onSurfaceVariant),
                                ),
                                title: Text(
                                  genre.name,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${genre.trackCount} track${genre.trackCount != 1 ? 's' : ''}',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
                                onTap: () => context.push('/genre/${genre.id}'),
                              ),
                            );
                          },
                          childCount: filteredGenres.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Mini Player
          Positioned(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            bottom: bottomInset + AppSpacing.sm,
            child: Consumer(
              builder: (context, ref, child) {
                final playbackState = ref.watch(playerControllerProvider);
                final currentTrack = playbackState.currentTrack;
                if (currentTrack == null) return const SizedBox.shrink();
                
                final favorites = ref.watch(favoritesProvider);
                final isPlaying = playbackState.status == PlaybackStatus.playing;
                final total = playbackState.duration.inMilliseconds;
                final pos = playbackState.position.inMilliseconds;
                final progress = total > 0 ? pos / total : 0.0;

                return MiniPlayer(
                  musicItem: currentTrack,
                  progress: progress,
                  isPlaying: isPlaying,
                  isFavorited: favorites.any((t) => t.id == currentTrack.id),
                  isDark: false,
                  onTap: () => context.push('/player'),
                  onPlayPauseTap: () {
                    final controller = ref.read(playerControllerProvider.notifier);
                    if (isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  onFavoriteTap: () {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
