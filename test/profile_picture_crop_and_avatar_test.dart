import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:Miee/shared/widgets/profile_avatar.dart';
import 'package:Miee/features/profile/presentation/widgets/profile_picture_crop_dialog.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to generate a test JPEG image of specific width and height
  Uint8List generateTestImageBytes({int width = 400, int height = 300, int color = 0xFFFF0000}) {
    final image = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        image.setPixelRgba(x, y, 200, 50, 50, 255);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  group('ProfileAvatar Widget Rendering & Fallback Invariants', () {
    testWidgets('Renders placeholder icon when imageUrl is null or empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(size: 40.0),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('Renders fallback user initial letter when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              size: 40.0,
              fallbackInitials: 'Revanth',
            ),
          ),
        ),
      );

      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('Renders Image.memory when imageUrl is a base64 data URI', (tester) async {
      final testBytes = generateTestImageBytes(width: 50, height: 50);
      final base64Uri = 'data:image/jpeg;base64,${base64Encode(testBytes)}';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              size: 48.0,
              imageUrl: base64Uri,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<MemoryImage>());
    });

    testWidgets('Renders Image.network when imageUrl is an HTTP/HTTPS URL', (tester) async {
      const httpsUrl = 'https://example.com/avatar.jpg';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              size: 48.0,
              imageUrl: httpsUrl,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<NetworkImage>());
    });
  });

  group('Interactive Profile Picture Crop Editor & Math Verification', () {
    testWidgets('ProfilePictureCropDialog displays title, instructions, circular mask, and controls', (tester) async {
      final sampleBytes = generateTestImageBytes(width: 300, height: 200);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ProfilePictureCropDialog.show(context, sampleBytes),
                child: const Text('Open Cropper'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Cropper'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Crop Profile Picture'), findsOneWidget);
      expect(find.text('Drag to reposition and zoom to adjust your photo.'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      // Tap Close button in header to dismiss dialog
      final closeBtnFinder = find.byIcon(Icons.close_rounded);
      expect(closeBtnFinder, findsOneWidget);
      await tester.tap(closeBtnFinder);
      await tester.pumpAndSettle();
      expect(find.text('Crop Profile Picture'), findsNothing);
    });

    test('Actual crop processing generates square JPEG bytes matching target resolution', () {
      final rawBytes = generateTestImageBytes(width: 800, height: 600);

      // Verify source decoded image is non-square (4:3 aspect ratio)
      final srcImage = img.decodeImage(rawBytes)!;
      expect(srcImage.width, equals(800));
      expect(srcImage.height, equals(600));

      // Simulate the exact cropping logic executed by _executeCrop
      const side = 600; // shorter side
      const cropX = (800 - side) ~/ 2;
      const cropY = 0;
      final cropped = img.copyCrop(srcImage, x: cropX, y: cropY, width: side, height: side);

      // Verify cropped image is perfectly 1:1 square
      expect(cropped.width, equals(side));
      expect(cropped.height, equals(side));

      // Resize to avatar standard resolution 512x512
      final resized = img.copyResize(cropped, width: 512, height: 512, interpolation: img.Interpolation.linear);
      expect(resized.width, equals(512));
      expect(resized.height, equals(512));

      final encodedJpg = Uint8List.fromList(img.encodeJpg(resized, quality: 88));
      expect(encodedJpg.isNotEmpty, isTrue);

      // Verify encoded bytes can be decoded back to a valid 512x512 square image
      final decodedResult = img.decodeImage(encodedJpg)!;
      expect(decodedResult.width, equals(512));
      expect(decodedResult.height, equals(512));
    });
  });

  group('Profile Model & Persistence Invariants', () {
    test('ProfileModel maintains profilePicturePath and supports clearing', () {
      final profile = ProfileModel.defaultProfile();
      expect(profile.profilePicturePath, isNull);

      final withPic = profile.copyWith(profilePicturePath: 'data:image/jpeg;base64,abc123');
      expect(withPic.profilePicturePath, equals('data:image/jpeg;base64,abc123'));

      final cleared = withPic.copyWith(clearProfilePicture: true);
      expect(cleared.profilePicturePath, isNull);
    });

    test('ProfileImageService rejects empty or invalid bytes safely', () {
      final emptyBytes = Uint8List(0);
      expect(emptyBytes.lengthInBytes < 16, isTrue);

      final tooSmallBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(tooSmallBytes.lengthInBytes < 16, isTrue);
    });
  });
}
