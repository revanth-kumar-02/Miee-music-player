import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/hive_boxes.dart';
import '../domain/resolved_artwork.dart';

/// Two-tiered cache combining fast in-memory LRU storage with persistent Hive backing.
class ArtworkCache {
  final int maxMemoryEntries;
  final LinkedHashMap<String, ResolvedArtwork> _memoryCache;
  final Box<dynamic>? _hiveBox;

  ArtworkCache({
    this.maxMemoryEntries = 200,
    Box<dynamic>? hiveBox,
  })  : _hiveBox = hiveBox,
        _memoryCache = LinkedHashMap<String, ResolvedArtwork>();

  Box<dynamic>? get _box {
    if (_hiveBox != null && _hiveBox!.isOpen) return _hiveBox;
    try {
      if (Hive.isBoxOpen(HiveBoxes.artworkCache)) {
        return Hive.box<dynamic>(HiveBoxes.artworkCache);
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves cached artwork by its deterministic [cacheKey].
  ResolvedArtwork? get(String cacheKey) {
    if (cacheKey.isEmpty) return null;

    // 1. Check in-memory LRU cache
    if (_memoryCache.containsKey(cacheKey)) {
      final item = _memoryCache.remove(cacheKey)!;
      _memoryCache[cacheKey] = item; // re-insert at end (most recently used)
      return item;
    }

    // 2. Check persistent Hive cache
    try {
      final box = _box;
      if (box != null && box.containsKey(cacheKey)) {
        final raw = box.get(cacheKey);
        if (raw is Map) {
          final resolved = ResolvedArtwork.fromJson(Map<String, dynamic>.from(raw));
          _putInMemory(cacheKey, resolved);
          return resolved;
        }
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Error reading from Hive: $e');
    }

    return null;
  }

  /// Persists [artwork] under [cacheKey] in both memory and persistent storage.
  Future<void> put(String cacheKey, ResolvedArtwork artwork) async {
    if (cacheKey.isEmpty) return;

    _putInMemory(cacheKey, artwork);

    // Save to Hive
    try {
      final box = _box;
      if (box != null) {
        await box.put(cacheKey, artwork.toJson());
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Error writing to Hive: $e');
    }
  }

  void _putInMemory(String key, ResolvedArtwork artwork) {
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    } else if (_memoryCache.length >= maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first); // Evict LRU
    }
    _memoryCache[key] = artwork;
  }

  /// Removes a cached entry.
  Future<void> evict(String cacheKey) async {
    _memoryCache.remove(cacheKey);
    try {
      final box = _box;
      if (box != null) {
        await box.delete(cacheKey);
      }
    } catch (_) {}
  }

  /// Clears both in-memory and persistent caches.
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final box = _box;
      if (box != null) {
        await box.clear();
      }
    } catch (_) {}
  }

  int get memoryCount => _memoryCache.length;
}
