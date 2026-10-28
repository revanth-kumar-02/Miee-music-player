import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:Miee/app/theme/web_colors.dart';
import 'package:Miee/features/auth/presentation/widgets/auth_components.dart';
import 'package:Miee/shared/widgets/miee_brand_header.dart';
import 'package:Miee/shared/widgets/miee_brand_mark.dart';

void main() {
  group('Miee Brand Refinement — Wordmark Dot Alignment Tests', () {
    testWidgets('1. MieeWordmarkDot renders "miee." as a unified inline TextSpan composition', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MieeWordmarkDot(
                fontSize: 24,
                textColor: Color(0xFF1A0F12),
                dotColor: Color(0xFFBA0032),
              ),
            ),
          ),
        ),
      );

      // Verify MieeWordmarkDot is mounted
      expect(find.byType(MieeWordmarkDot), findsOneWidget);

      // Verify RichText exists inside MieeWordmarkDot
      final richTextFinder = find.descendant(
        of: find.byType(MieeWordmarkDot),
        matching: find.byType(RichText),
      );
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final textSpan = richText.text as TextSpan;

      // Verify text spans: 'miee' followed by '.'
      expect(textSpan.children, isNotNull);
      expect(textSpan.children!.length, equals(2));

      final firstSpan = textSpan.children![0] as TextSpan;
      final dotSpan = textSpan.children![1] as TextSpan;

      expect(firstSpan.text, equals('miee'));
      expect(dotSpan.text, equals('.'));
      expect(dotSpan.style?.color, equals(const Color(0xFFBA0032)));
      expect(dotSpan.style?.fontWeight, equals(FontWeight.w900));
    });

    testWidgets('2. MieeBrandMark.soundwaveWordmark renders inline MieeWordmarkDot (miee.)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MieeBrandMark.soundwaveWordmark(fontSize: 24),
            ),
          ),
        ),
      );

      expect(find.byType(MieeBrandMark), findsOneWidget);
      expect(find.byType(MieeWordmarkDot), findsOneWidget);

      final richTextFinder = find.descendant(
        of: find.byType(MieeWordmarkDot),
        matching: find.byType(RichText),
      );
      final richText = tester.widget<RichText>(richTextFinder);
      final textSpan = richText.text as TextSpan;

      expect((textSpan.children![0] as TextSpan).text, equals('miee'));
      expect((textSpan.children![1] as TextSpan).text, equals('.'));
    });

    testWidgets('3. MieeBrandMark.emblem renders inline MieeWordmarkDot (miee.) without floating containers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MieeBrandMark.emblem(
                emblemSize: 52,
                fontSize: 24,
                showWordmark: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MieeBrandMark), findsOneWidget);
      // Wordmark is rendered via MieeWordmarkDot
      expect(find.byType(MieeWordmarkDot), findsOneWidget);

      final richTextFinder = find.descendant(
        of: find.byType(MieeWordmarkDot),
        matching: find.byType(RichText),
      );
      final richText = tester.widget<RichText>(richTextFinder);
      final textSpan = richText.text as TextSpan;

      expect((textSpan.children![0] as TextSpan).text, equals('miee'));
      expect((textSpan.children![1] as TextSpan).text, equals('.'));
    });

    testWidgets('4. MieeWordmarkDot scales proportionally across multiple sizes', (tester) async {
      const sizes = [16.0, 20.0, 22.0, 24.0, 32.0];

      for (final size in sizes) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MieeWordmarkDot(
                  fontSize: size,
                  textColor: MieeWebColors.textDark,
                  dotColor: MieeWebColors.primaryContainer,
                ),
              ),
            ),
          ),
        );

        final richTextFinder = find.descendant(
          of: find.byType(MieeWordmarkDot),
          matching: find.byType(RichText),
        );
        final richText = tester.widget<RichText>(richTextFinder);
        final textSpan = richText.text as TextSpan;

        expect(textSpan.style?.fontSize, equals(size));
        expect((textSpan.children![0] as TextSpan).text, equals('miee'));
        expect((textSpan.children![1] as TextSpan).text, equals('.'));
      }
    });

    testWidgets('5. MieeBrandHeader embeds canonical MieeWordmarkDot (miee.)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(title: 'Home'),
            body: SizedBox.expand(),
          ),
        ),
      );

      expect(find.byType(MieeBrandHeader), findsOneWidget);
      expect(find.byType(MieeWordmarkDot), findsOneWidget);
    });

    testWidgets('6. AuthDesktopHeader mounts MieeBrandMark with inline MieeWordmarkDot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthDesktopHeader(),
          ),
        ),
      );

      expect(find.byType(AuthDesktopHeader), findsOneWidget);
      expect(find.byType(MieeBrandMark), findsOneWidget);
      expect(find.byType(MieeWordmarkDot), findsOneWidget);
    });
  });
}
