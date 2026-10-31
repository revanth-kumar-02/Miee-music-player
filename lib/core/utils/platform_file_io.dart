import 'dart:io' as io;
import 'package:flutter/widgets.dart';

class PlatformFileHelper {
  static bool exists(String path) {
    try {
      return io.File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String path) async {
    try {
      final file = io.File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<String> writeBytes(String path, List<int> bytes) async {
    final file = io.File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Widget buildFileImage({
    required String path,
    required double size,
    required Widget Function() errorBuilder,
  }) {
    return Image.file(
      io.File(path),
      fit: BoxFit.cover,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => errorBuilder(),
    );
  }
}
