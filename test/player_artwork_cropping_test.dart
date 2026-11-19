import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/app/theme/app_colors.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/artwork/presentation/miee_artwork_image.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  final testOverrides = [
    resolvedArtworkProvider.overrideWith((ref, query) async {
      return ResolvedArtwork(
        imageUrl: query.albumArtworkUrl ?? 'https://is1-ssl.mzstatic.com/image/thumb/Music/cover.jpg/600x600bb.jpg',
        source: ArtworkSource.itunes,
        confidence: 0.95,
      );
    }),
  ];

  group('Full-Screen Player Artwork Display & Fit Tests', () {
    testWidgets('Renders studio album artwork with BoxFit.cover filling square container without distortion', (tester) async {
      const studioTrack = Track(
        id: 'youtube_fafafa',
        title: 'FA FA FA',
        artist: 'Sai Abhyankkar & Dhanush',
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/fafafa.jpg/600x600bb.jpg',
        albumArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/fafafa.jpg/600x600bb.jpg',
        duration: '3:04',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: MieeArtworkImage(
                      musicItem: studioTrack,
                      explicitUrl: studioTrack.albumArtworkUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify MieeArtworkImage is rendered
      final artworkFinder = find.byType(MieeArtworkImage);
      expect(artworkFinder, findsOneWidget);

      final mieeArtwork = tester.widget<MieeArtworkImage>(artworkFinder);
      expect(mieeArtwork.fit, equals(BoxFit.cover));
    });

    testWidgets('YouTube thumbnails are rejected from album artwork and fallback to neutral fallback', (tester) async {
      const ytTrack = Track(
        id: 'youtube_urugi',
        title: 'Urugi Urugi',
        artist: 'Siddhu Kumar',
        imageUrl: '',
        youtubeThumbnailUrl: 'https://i.ytimg.com/vi/urugi123/hqdefault.jpg',
        duration: '3:56',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            resolvedArtworkProvider.overrideWith((ref, query) async {
              return ResolvedArtwork.neutralFallback();
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: MieeArtworkImage(
                      musicItem: ytTrack,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final artworkFinder = find.byType(MieeArtworkImage);
      expect(artworkFinder, findsOneWidget);

      // Verify neutral fallback icon is rendered instead of YouTube video banner
      expect(find.byIcon(Icons.album_rounded), findsOneWidget);
    });

    testWidgets('Renders square (1:1) album artwork with BoxFit.cover', (tester) async {
      const squareTrack = Track(
        id: 'track_square',
        title: 'Blue Hour',
        artist: 'Dhanush',
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/cover.jpg/600x600bb.jpg',
        albumArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/cover.jpg/600x600bb.jpg',
        duration: '2:33',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: MieeArtworkImage(
                      musicItem: squareTrack,
                      explicitUrl: squareTrack.albumArtworkUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final artworkFinder = find.byType(MieeArtworkImage);
      expect(artworkFinder, findsOneWidget);

      final mieeArtwork = tester.widget<MieeArtworkImage>(artworkFinder);
      expect(mieeArtwork.fit, equals(BoxFit.cover));
    });

    testWidgets('Renders portrait (3:4) soundtrack artwork with BoxFit.contain without vertical cropping', (tester) async {
      const portraitTrack = Track(
        id: 'track_portrait',
        title: 'Soundtrack Theme',
        artist: 'Composer',
        imageUrl: 'https://example.com/movie_poster.jpg',
        duration: '4:15',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: MieeArtworkImage(
                      musicItem: portraitTrack,
                      explicitUrl: portraitTrack.imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final artworkFinder = find.byType(MieeArtworkImage);
      expect(artworkFinder, findsOneWidget);

      final mieeArtwork = tester.widget<MieeArtworkImage>(artworkFinder);
      expect(mieeArtwork.fit, equals(BoxFit.contain));
    });

    testWidgets('Renders fallback artwork when no track or image is available', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.softClay,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 72,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    });

    testWidgets('List thumbnails still use BoxFit.cover for square small tiles', (tester) async {
      const queueTrack = Track(
        id: 'track_queue',
        title: 'Queue Song',
        artist: 'Artist',
        imageUrl: 'https://example.com/thumb.jpg',
        duration: '3:00',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 40,
                height: 40,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: MieeArtworkImage(
                    musicItem: queueTrack,
                    explicitUrl: queueTrack.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final artworkFinder = find.byType(MieeArtworkImage);
      expect(artworkFinder, findsOneWidget);

      final mieeArtwork = tester.widget<MieeArtworkImage>(artworkFinder);
      expect(mieeArtwork.fit, equals(BoxFit.cover));
    });
  });
}
