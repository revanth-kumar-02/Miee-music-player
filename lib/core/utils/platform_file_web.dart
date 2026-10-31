import 'package:flutter/widgets.dart';

class PlatformFileHelper {
  static bool exists(String path) => false;
  static Future<void> delete(String path) async {}
  static Future<String> writeBytes(String path, List<int> bytes) async => '';
  static Widget buildFileImage({
    required String path,
    required double size,
    required Widget Function() errorBuilder,
  }) {
    return errorBuilder();
  }
}
