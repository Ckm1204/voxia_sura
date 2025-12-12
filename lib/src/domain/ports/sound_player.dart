abstract class SoundPlayer {
  bool get isPlaying;
  Future<void> setAsset(String assetPath, {bool preload = true, Duration? initialPosition});
  Future<void> play(String assetToPlay, {bool loop = false});
  Future<void> stop();
  set onStop(void Function()? callback);
}