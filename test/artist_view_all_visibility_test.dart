import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/widgets/section_header.dart';
import 'package:Miee/app/theme/app_colors.dart';

void main() {
  group('Artist Profile View All Visibility & Accessibility Tests', () {
    testWidgets('SectionHeader renders action button in AppColors.primary with accessible styling and tap target', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: SectionHeader(
                title: 'Popular Tracks',
                actionLabel: 'View All',
                actionColor: AppColors.primary,
                onActionTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify header title
      expect(find.text('Popular Tracks'), findsOneWidget);

      // Verify VIEW ALL button exists
      final actionFinder = find.text('VIEW ALL');
      expect(actionFinder, findsOneWidget);

      // Verify text styling: color is AppColors.primary (#D78D9B), not invisible AppColors.outline (#E7DED5)
      final textWidget = tester.widget<Text>(actionFinder);
      expect(textWidget.style?.color, equals(AppColors.primary));
      expect(textWidget.style?.fontWeight, equals(FontWeight.w700));

      // Verify button tap target is accessible (min height >= 36)
      final buttonFinder = find.byType(TextButton);
      expect(buttonFinder, findsOneWidget);
      final buttonSize = tester.getSize(buttonFinder);
      expect(buttonSize.height, greaterThanOrEqualTo(36.0));
      expect(buttonSize.width, greaterThanOrEqualTo(48.0));

      // Verify tapping invokes callback
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('SectionHeader defaults actionColor to AppColors.primary when omitted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: SectionHeader(
                title: 'Popular Tracks',
                actionLabel: 'View All',
                onActionTap: () {},
              ),
            ),
          ),
        ),
      );

      final actionFinder = find.text('VIEW ALL');
      final textWidget = tester.widget<Text>(actionFinder);
      expect(textWidget.style?.color, equals(AppColors.primary));
    });
  });
}

