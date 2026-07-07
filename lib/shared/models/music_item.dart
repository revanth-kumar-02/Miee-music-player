/// Unified abstraction representing a playable track/music item in Miee.
/// Both local offline songs and online YouTube tracks inherit from this interface.
abstract class MusicItem {
  String get id;
  String get title;
  String get artist;
  String get imageUrl;
  String get duration;
  String get filePath;
  bool get isYoutube;
}
