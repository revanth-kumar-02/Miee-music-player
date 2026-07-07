import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

/// App entry point.
/// Wraps the root [MieeApp] in a [ProviderScope] to initialize Riverpod.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: MieeApp(),
    ),
  );
}
