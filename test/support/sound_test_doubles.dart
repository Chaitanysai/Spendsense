import 'package:spendsense/services/sound_service.dart';

/// A [SoundPlayer] that records calls instead of touching audio hardware, and
/// can be told to misbehave so the service's failure handling is exercised.
///
/// Shared by the unit tests for [SoundService] and the widget-level integration
/// tests, so both assert against the same notion of "a cue was played".
class RecordingSoundPlayer implements SoundPlayer {
  RecordingSoundPlayer({
    this.loadable,
    this.failPreload = false,
    this.failPlay = false,
  });

  /// Assets that "exist". `null` means every asset loads.
  final Set<String>? loadable;
  final bool failPreload;
  final bool failPlay;

  final List<String> played = <String>[];
  final List<double> volumes = <double>[];
  int preloadCalls = 0;
  int stopAllCalls = 0;
  int disposeCalls = 0;

  @override
  Future<Set<String>> preload(Iterable<String> assets) async {
    preloadCalls++;
    if (failPreload) throw StateError('preload unavailable');
    final all = assets.toSet();
    return loadable == null ? all : all.where(loadable!.contains).toSet();
  }

  @override
  Future<void> play(String asset, {required double volume}) async {
    if (failPlay) throw StateError('no audio device');
    played.add(asset);
    volumes.add(volume);
  }

  @override
  Future<void> stopAll() async => stopAllCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}

/// Frozen clock so duplicate-suppression windows are tested exactly.
class TestClock {
  DateTime now = DateTime(2026, 1, 1, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}
