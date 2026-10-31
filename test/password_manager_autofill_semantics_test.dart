import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/auth/presentation/login_page.dart';
import 'package:Miee/features/auth/presentation/register_page.dart';
import 'package:Miee/features/auth/presentation/widgets/auth_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Password Manager & Autofill Semantics Suite', () {
    testWidgets('LoginPage contains AutofillGroup and correct AutofillHints for credentials', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      await tester.pump();

      // 1. Verify AutofillGroup is present around login form
      expect(find.byType(AutofillGroup), findsOneWidget);

      // 2. Verify Email field exposes AutofillHints.email and AutofillHints.username
      final emailFinder = find.byWidgetPredicate(
        (widget) => widget is AuthTextField && widget.label == 'Email address',
      );
      expect(emailFinder, findsOneWidget);
      final emailWidget = tester.widget<AuthTextField>(emailFinder);
      expect(emailWidget.autofillHints, contains(AutofillHints.email));
      expect(emailWidget.autofillHints, contains(AutofillHints.username));
      expect(emailWidget.keyboardType, equals(TextInputType.emailAddress));
      expect(emailWidget.autocorrect, isFalse);

      // 3. Verify Password field exposes AutofillHints.password
      final passwordFinder = find.byWidgetPredicate(
        (widget) => widget is AuthTextField && widget.label == 'Password',
      );
      expect(passwordFinder, findsOneWidget);
      final passwordWidget = tester.widget<AuthTextField>(passwordFinder);
      expect(passwordWidget.autofillHints, contains(AutofillHints.password));
      expect(passwordWidget.obscureText, isTrue);
      expect(passwordWidget.autocorrect, isFalse);
    });

    testWidgets('RegisterPage contains AutofillGroup and correct AutofillHints for new account creation', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: RegisterPage(),
          ),
        ),
      );
      await tester.pump();

      // 1. Verify AutofillGroup is present around registration form
      expect(find.byType(AutofillGroup), findsOneWidget);

      // 2. Full name field has AutofillHints.name
      final nameFinder = find.byWidgetPredicate(
        (widget) => widget is AuthTextField && widget.label == 'FULL NAME',
      );
      expect(nameFinder, findsOneWidget);
      final nameWidget = tester.widget<AuthTextField>(nameFinder);
      expect(nameWidget.autofillHints, contains(AutofillHints.name));

      // 3. Email field has AutofillHints.email
      final emailFinder = find.byWidgetPredicate(
        (widget) => widget is AuthTextField && widget.label == 'EMAIL ADDRESS',
      );
      expect(emailFinder, findsOneWidget);
      final emailWidget = tester.widget<AuthTextField>(emailFinder);
      expect(emailWidget.autofillHints, contains(AutofillHints.email));
      expect(emailWidget.keyboardType, equals(TextInputType.emailAddress));
      expect(emailWidget.autocorrect, isFalse);

      // 4. Password field has AutofillHints.newPassword
      final passwordFinder = find.byWidgetPredicate(
        (widget) => widget is AuthTextField && widget.label == 'PASSWORD',
      );
      expect(passwordFinder, findsOneWidget);
      final passwordWidget = tester.widget<AuthTextField>(passwordFinder);
      expect(passwordWidget.autofillHints, contains(AutofillHints.newPassword));
      expect(passwordWidget.obscureText, isTrue);
      expect(passwordWidget.autocorrect, isFalse);

      // 5. Confirm Password field has AutofillHints.newPassword
      final confirmPasswordFinder = find.byWidgetPredicate(
        (widget) => widget is AuthTextField && widget.label == 'CONFIRM PASSWORD',
      );
      expect(confirmPasswordFinder, findsOneWidget);
      final confirmPasswordWidget = tester.widget<AuthTextField>(confirmPasswordFinder);
      expect(confirmPasswordWidget.autofillHints, contains(AutofillHints.newPassword));
      expect(confirmPasswordWidget.obscureText, isTrue);
      expect(confirmPasswordWidget.autocorrect, isFalse);
    });

    testWidgets('AuthTextField correctly propagates autofillHints to underlying TextField', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthTextField(
              label: 'Test Email',
              hintText: 'Enter email',
              controller: controller,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
            ),
          ),
        ),
      );

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.autofillHints, contains(AutofillHints.email));
      expect(textField.autocorrect, isFalse);
    });

    testWidgets('Login form validation triggers without leaking credentials', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      await tester.pump();

      // Tap Log in button with empty fields
      final loginBtnFinder = find.widgetWithText(AuthPrimaryButton, 'Log in');
      expect(loginBtnFinder, findsOneWidget);
      await tester.tap(loginBtnFinder);
      await tester.pumpAndSettle();

      // Form validation errors displayed
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });
  });
}
