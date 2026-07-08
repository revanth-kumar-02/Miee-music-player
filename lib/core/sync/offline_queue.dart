import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../storage/hive_boxes.dart';
import 'offline_operation.dart';

/// Manages caching of offline database modification logs to Hive and their processing order.
class OfflineOperationQueue {
  final Box _box;

  OfflineOperationQueue(this._box);

  List<OfflineOperation> getOperations() {
    final values = _box.values.toList();
    return values
        .map((e) => OfflineOperation.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> addOperation(OfflineOperation op) async {
    await _box.put(op.id, op.toMap());
  }

  Future<void> removeOperation(String id) async {
    await _box.delete(id);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }

  bool get isEmpty => _box.isEmpty;
}
