import '../../shared/models/music_item.dart';

/// Reusable manager responsible for maintaining the track play queue list,
/// active index pointers, and playlist reorder/remove events.
class QueueManager {
  final List<MusicItem> _queue = [];
  int _currentIndex = -1;

  /// Returns the current play queue list.
  List<MusicItem> get queue => List.unmodifiable(_queue);

  /// Returns the currently active index.
  int get currentIndex => _currentIndex;

  /// Returns the active track if a queue exists and is loaded.
  MusicItem? get currentTrack {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      return _queue[_currentIndex];
    }
    return null;
  }

  /// Sets the play queue and resets the active index pointer.
  void setQueue(List<MusicItem> tracks, {int startIndex = 0}) {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = (startIndex >= 0 && startIndex < _queue.length) ? startIndex : 0;
  }

  /// Appends a track to the end of the queue.
  void addTrack(MusicItem track) {
    _queue.add(track);
    if (_currentIndex == -1) {
      _currentIndex = 0;
    }
  }

  /// Appends a list of tracks to the end of the queue.
  void addTracks(List<MusicItem> tracks) {
    _queue.addAll(tracks);
    if (_currentIndex == -1 && _queue.isNotEmpty) {
      _currentIndex = 0;
    }
  }

  /// Selects the next index. Returns the track if successful.
  MusicItem? next() {
    if (_queue.isEmpty) return null;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      return _queue[_currentIndex];
    }
    return null;
  }

  /// Selects the previous index. Returns the track if successful.
  MusicItem? previous() {
    if (_queue.isEmpty) return null;
    if (_currentIndex > 0) {
      _currentIndex--;
      return _queue[_currentIndex];
    }
    return null;
  }

  /// Sets the active index directly.
  void setIndex(int index) {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
    }
  }

  /// Reorders items in the queue.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;

    var actualNewIndex = newIndex;
    if (oldIndex < actualNewIndex) {
      actualNewIndex -= 1;
    }

    final track = _queue.removeAt(oldIndex);
    _queue.insert(actualNewIndex, track);

    // Keep active pointer synchronized
    if (_currentIndex == oldIndex) {
      _currentIndex = actualNewIndex;
    } else if (_currentIndex > oldIndex && _currentIndex <= actualNewIndex) {
      _currentIndex--;
    } else if (_currentIndex < oldIndex && _currentIndex >= actualNewIndex) {
      _currentIndex++;
    }
  }

  /// Replaces the track at [index] with [newTrack].
  void replaceTrackAt(int index, MusicItem newTrack) {
    if (index >= 0 && index < _queue.length) {
      _queue[index] = newTrack;
    }
  }

  /// Removes an item from the queue by index.
  void removeTrackAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _currentIndex = -1;
    } else if (_currentIndex >= _queue.length) {
      _currentIndex = _queue.length - 1;
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
  }

  /// Empties the play queue.
  void clear() {
    _queue.clear();
    _currentIndex = -1;
  }
}

