import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/onboarding/presentation/artist_selection_page.dart';
import 'package:Miee/features/onboarding/providers/onboarding_providers.dart';

void main() {
  group('Part 1: ArtistModel Image Validation & Language Metadata', () {
    test('hasValidImage identifies valid Deezer CDN images', () {
      const validArtist = ArtistModel(
        id: '491',
        name: 'A. R. Rahman',
        imageUrl: 'https://e-cdns-images.dzcdn.net/images/artist/066d7ad5f09627581bf82d6da6155fe5/500x500-000000-80-0-0.jpg',
        languages: ['Tamil', 'Hindi', 'Telugu'],
      );
      expect(validArtist.hasValidImage, isTrue);
    });

    test('hasValidImage rejects Deezer fallback empty MD5 hash and malformed URLs', () {
      const emptyHashArtist = ArtistModel(
        id: '999',
        name: 'Ghost Artist',
        imageUrl: 'https://e-cdns-images.dzcdn.net/images/artist/d41d8cd98f00b204e9800998ecf8427e/500x500-000000-80-0-0.jpg',
      );
      expect(emptyHashArtist.hasValidImage, isFalse);

      const malformedArtist = ArtistModel(
        id: '998',
        name: 'Malformed URL Artist',
        imageUrl: 'https://e-cdns-images.dzcdn.net/images/artist//500x500-000000-80-0-0.jpg',
      );
      expect(malformedArtist.hasValidImage, isFalse);

      const blankArtist = ArtistModel(
        id: '997',
        name: 'Blank Image Artist',
        imageUrl: '',
      );
      expect(blankArtist.hasValidImage, isFalse);
    });

    test('matchesLanguage correctly checks against artist languages list', () {
      const arr = ArtistModel(
        id: '491',
        name: 'A. R. Rahman',
        imageUrl: 'https://e-cdns-images.dzcdn.net/images/artist/test.jpg',
        languages: ['Tamil', 'Hindi', 'Telugu'],
      );

      expect(arr.matchesLanguage('All'), isTrue);
      expect(arr.matchesLanguage('Tamil'), isTrue);
      expect(arr.matchesLanguage('tamil'), isTrue);
      expect(arr.matchesLanguage('Hindi'), isTrue);
      expect(arr.matchesLanguage('Telugu'), isTrue);
      expect(arr.matchesLanguage('Malayalam'), isFalse);
      expect(arr.matchesLanguage('English'), isFalse);
    });

    test('ArtistSummary retains languages and serializes backwards-compatibly', () {
      const summary = ArtistSummary(
        id: '1516162',
        name: 'Anirudh Ravichander',
        imageUrl: 'https://e-cdns-images.dzcdn.net/images/artist/anirudh.jpg',
        languages: ['Tamil', 'Telugu'],
      );

      final map = summary.toMap();
      expect(map['id'], equals('1516162'));
      expect(map['name'], equals('Anirudh Ravichander'));
      expect(map['imageUrl'], equals('https://e-cdns-images.dzcdn.net/images/artist/anirudh.jpg'));
      expect(map['languages'], equals(['Tamil', 'Telugu']));

      // Deserializing without languages defaults safely to empty list
      final legacy = ArtistSummary.fromMap({
        'id': '1516162',
        'name': 'Anirudh Ravichander',
        'imageUrl': 'https://e-cdns-images.dzcdn.net/images/artist/anirudh.jpg',
      });
      expect(legacy.languages, isEmpty);
    });
  });

  group('Part 2: Curated Indian & Global Artist Catalog Integrity', () {
    final repo = DeezerArtistRepository();

    test('All curated artists have verified non-empty IDs, names, images, and languages', () {
      final allArtists = repo.curatedArtists;
      expect(allArtists.length, greaterThanOrEqualTo(35));

      for (final artist in allArtists) {
        expect(artist.id.trim(), isNotEmpty, reason: 'Artist ${artist.name} missing ID');
        expect(artist.name.trim(), isNotEmpty, reason: 'Artist with ID ${artist.id} missing name');
        expect(artist.imageUrl.trim(), isNotEmpty, reason: 'Artist ${artist.name} missing imageUrl');
        expect(artist.imageUrl.contains('d41d8cd98f00b204e9800998ecf8427e'), isFalse,
            reason: 'Artist ${artist.name} has placeholder silhouette hash');
        expect(artist.imageUrl.contains('/artist//'), isFalse,
            reason: 'Artist ${artist.name} has malformed URL');
        expect(artist.languages, isNotEmpty, reason: 'Artist ${artist.name} has no language metadata');
      }
    });

    test('Catalog contains well-represented artists for each required language', () {
      final allArtists = repo.curatedArtists;

      final tamilArtists = allArtists.where((a) => a.matchesLanguage('Tamil')).toList();
      final hindiArtists = allArtists.where((a) => a.matchesLanguage('Hindi')).toList();
      final teluguArtists = allArtists.where((a) => a.matchesLanguage('Telugu')).toList();
      final malayalamArtists = allArtists.where((a) => a.matchesLanguage('Malayalam')).toList();
      final kannadaArtists = allArtists.where((a) => a.matchesLanguage('Kannada')).toList();
      final englishArtists = allArtists.where((a) => a.matchesLanguage('English')).toList();

      expect(tamilArtists.length, greaterThanOrEqualTo(5), reason: 'Insufficient Tamil artists');
      expect(hindiArtists.length, greaterThanOrEqualTo(5), reason: 'Insufficient Hindi artists');
      expect(teluguArtists.length, greaterThanOrEqualTo(4), reason: 'Insufficient Telugu artists');
      expect(malayalamArtists.length, greaterThanOrEqualTo(3), reason: 'Insufficient Malayalam artists');
      expect(kannadaArtists.length, greaterThanOrEqualTo(3), reason: 'Insufficient Kannada artists');
      expect(englishArtists.length, greaterThanOrEqualTo(8), reason: 'Insufficient English artists');
    });

    test('Cross-language artists appear in all matching language queries', () async {
      final tamil = await repo.getPopularArtists(language: 'Tamil');
      final hindi = await repo.getPopularArtists(language: 'Hindi');
      final telugu = await repo.getPopularArtists(language: 'Telugu');

      // A. R. Rahman is in Tamil, Hindi, and Telugu
      expect(tamil.any((a) => a.name == 'A. R. Rahman'), isTrue);
      expect(hindi.any((a) => a.name == 'A. R. Rahman'), isTrue);
      expect(telugu.any((a) => a.name == 'A. R. Rahman'), isTrue);

      // Anirudh Ravichander is in Tamil and Telugu
      expect(tamil.any((a) => a.name == 'Anirudh Ravichander'), isTrue);
      expect(telugu.any((a) => a.name == 'Anirudh Ravichander'), isTrue);

      // Shreya Ghoshal is in Hindi and Tamil
      expect(hindi.any((a) => a.name == 'Shreya Ghoshal'), isTrue);
      expect(tamil.any((a) => a.name == 'Shreya Ghoshal'), isTrue);
    });
  });

  group('Part 3: Onboarding Notifier & Language State Preservation', () {
    test('Switching language preserves previously selected artists', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(onboardingNotifierProvider.notifier);
      expect(container.read(onboardingNotifierProvider).selectedLanguage, equals('All'));
      expect(container.read(onboardingNotifierProvider).selectedArtists, isEmpty);

      // Select 2 Tamil artists
      const arr = ArtistModel(id: '491', name: 'A. R. Rahman', imageUrl: '');
      const anirudh = ArtistModel(id: '1516162', name: 'Anirudh Ravichander', imageUrl: '');
      notifier.toggleArtist(arr);
      notifier.toggleArtist(anirudh);
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(2));
      expect(container.read(onboardingNotifierProvider).canContinue, isFalse); // Need at least 3

      // Switch language to Hindi
      notifier.setLanguage('Hindi');
      expect(container.read(onboardingNotifierProvider).selectedLanguage, equals('Hindi'));
      // Selections MUST NOT be lost!
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(2));
      expect(container.read(onboardingNotifierProvider).selectedArtists.any((a) => a.name == 'A. R. Rahman'), isTrue);

      // Select 1 Hindi artist (e.g. Arijit Singh)
      const arijit = ArtistModel(id: '3830821', name: 'Arijit Singh', imageUrl: '');
      notifier.toggleArtist(arijit);
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(3));
      // Now meets minimum 3 selection requirement
      expect(container.read(onboardingNotifierProvider).canContinue, isTrue);
      expect(container.read(onboardingNotifierProvider).counterText, equals('3 of 5 selected'));

      // Switch language to Telugu
      notifier.setLanguage('Telugu');
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(3));

      // Deselecting works across language tabs
      notifier.toggleArtist(anirudh);
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(2));
      expect(container.read(onboardingNotifierProvider).canContinue, isFalse);
    });

    test('Enforces maximum 5 artists regardless of language switching', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(onboardingNotifierProvider.notifier);
      const a1 = ArtistModel(id: '1', name: 'Artist 1', imageUrl: '');
      const a2 = ArtistModel(id: '2', name: 'Artist 2', imageUrl: '');
      const a3 = ArtistModel(id: '3', name: 'Artist 3', imageUrl: '');
      const a4 = ArtistModel(id: '4', name: 'Artist 4', imageUrl: '');
      const a5 = ArtistModel(id: '5', name: 'Artist 5', imageUrl: '');
      const a6 = ArtistModel(id: '6', name: 'Artist 6', imageUrl: '');

      notifier.toggleArtist(a1);
      notifier.toggleArtist(a2);
      notifier.setLanguage('Tamil');
      notifier.toggleArtist(a3);
      notifier.toggleArtist(a4);
      notifier.setLanguage('Telugu');
      notifier.toggleArtist(a5);
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(5));

      // Attempting 6th artist should be ignored
      notifier.toggleArtist(a6);
      expect(container.read(onboardingNotifierProvider).selectedArtists, hasLength(5));
      expect(container.read(onboardingNotifierProvider).selectedArtists.any((a) => a.id == '6'), isFalse);
    });
  });

  group('Part 4: ArtistAvatar & Fallback UI Tests', () {
    testWidgets('ArtistAvatar renders initial fallback when image is blank or invalid',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArtistAvatar(
                name: 'Kishore Kumar',
                imageUrl: '',
                radius: 40,
              ),
            ),
          ),
        ),
      );

      // Verify that initial 'K' is rendered
      expect(find.text('K'), findsOneWidget);
    });

    testWidgets('ArtistAvatar falls back to initials when given silhouette placeholder hash',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArtistAvatar(
                name: 'Devi Sri Prasad',
                imageUrl: 'https://e-cdns-images.dzcdn.net/images/artist/d41d8cd98f00b204e9800998ecf8427e/200x200.jpg',
                radius: 40,
              ),
            ),
          ),
        ),
      );

      // Verify that fallback initial badge 'D' is displayed instead of broken image
      expect(find.text('D'), findsOneWidget);
    });

    testWidgets('ArtistAvatar extracts clean initials from multi-word names',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArtistAvatar(
                name: 'A. R. Rahman',
                imageUrl: '',
                radius: 40,
              ),
            ),
          ),
        ),
      );

      // 'A. R. Rahman' should extract 'A'
      expect(find.text('A'), findsOneWidget);
    });
  });
}
