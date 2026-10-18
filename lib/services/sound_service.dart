import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// The semantic sound vocabulary of the app.
///
/// Call sites name *what happened*, never *which file to play* — the mapping,
/// volume and gating all live in [SoundService] so the sound identity can be
/// retuned in one place.
enum SoundEventType {
  /// A button or comparable control was activated.
  buttonTap,

  /// A discrete choice changed (tab, segment, chip, dropdown, switch).
  selectionChanged,

  /// A transaction was **successfully persisted**.
  transactionSaved,

  /// A user-initiated action completed successfully.
  actionSucceeded,

  /// A user-initiated action failed and the user was told about it.
  actionFailed,

  /// A verified, real milestone was reached.
  milestoneReached,
}

/// Which user-facing switch governs an event.
///
/// Two categories only, mirroring the two toggles offered in Settings:
/// interaction feedback vs. money/outcome feedback.
enum SoundCategory {
  /// Governed by the "Interaction sounds" switch.
  ui,

  /// Governed by the "Transaction & success" switch.
  transaction,
}

extension SoundEventTypeCategory on SoundEventType {
  SoundCategory get category => switch (this) {
        SoundEventType.buttonTap ||
        SoundEventType.selectionChanged =>
          SoundCategory.ui,
        SoundEventType.transactionSaved ||
        SoundEventType.actionSucceeded ||
        SoundEventType.actionFailed ||
        SoundEventType.milestoneReached =>
          SoundCategory.transaction,
      };

  /// Minimum gap before the same event may fire again.
  ///
  /// Guards against a single interaction reaching the service twice (a widget
  /// and its child both accepting one tap) and against rapid-fire re-taps
  /// stacking the same cue on top of itself.
  Duration get repeatWindow => switch (category) {
        SoundCategory.ui => const Duration(milliseconds: 70),
        SoundCategory.transaction => const Duration(milliseconds: 300),
      };
}

/// Immutable snapshot of the user's audio preferences.
@immutable
class SoundPreferences {
  /// Everything on, at a restrained volume.
  ///
  /// Deliberately *not* silent by default: the cue set is soft, short and
  /// played at [SoundService.defaultVolume], so the premium feel is present
  /// without ever being loud. One tap in Settings mutes everything.
  static const SoundPreferences defaults = SoundPreferences();

  const SoundPreferences({
    this.masterEnabled = true,
    this.uiEnabled = true,
    this.transactionsEnabled = true,
  });

  final bool masterEnabled;
  final bool uiEnabled;
  final bool transactionsEnabled;

  /// Whether [event] may be played under this snapshot.
  bool allows(SoundEventType event) {
    if (!masterEnabled) return false;
    return switch (event.category) {
      SoundCategory.ui => uiEnabled,
      SoundCategory.transaction => transactionsEnabled,
    };
  }

  SoundPreferences copyWith({
    bool? masterEnabled,
    bool? uiEnabled,
    bool? transactionsEnabled,
  }) =>
      SoundPreferences(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        uiEnabled: uiEnabled ?? this.uiEnabled,
        transactionsEnabled: transactionsEnabled ?? this.transactionsEnabled,
      );

  @override
  bool operator ==(Object other) =>
      other is SoundPreferences &&
      other.masterEnabled == masterEnabled &&
      other.uiEnabled == uiEnabled &&
      other.transactionsEnabled == transactionsEnabled;

  @override
  int get hashCode =>
      Object.hash(masterEnabled, uiEnabled, transactionsEnabled);

  @override
  String toString() => 'SoundPreferences(master: $masterEnabled, '
      'ui: $uiEnabled, transactions: $transactionsEnabled)';
}

/// Minimal playback port that [SoundService] depends on.
///
/// Keeping this an interface is what makes the service testable without audio
/// hardware: tests supply a fake and assert on the calls it receives.
abstract interface class SoundPlayer {
  /// Loads [assets] ahead of time and returns the subset that loaded.
  ///
  /// Implementations must not throw: a missing or broken asset is reported by
  /// omitting it from the returned set.
  Future<Set<String>> preload(Iterable<String> assets);

  /// Plays [asset]. May throw; [SoundService] treats that as non-fatal.
  Future<void> play(String asset, {required double volume});

  /// Stops anything currently playing.
  Future<void> stopAll();

  /// Releases all native resources.
  Future<void> dispose();
}

/// Coordinates the bundled cues: asset mapping, preference gating, duplicate
/// suppression, and lifecycle.
///
/// Every public entry point is failure-tolerant. Audio is a garnish — it must
/// never be able to break navigation, a transaction, or startup.
class SoundService {
  SoundService({SoundPlayer? player, DateTime Function()? clock})
      : _player = player ?? AudioPlayersSoundPlayer(),
        _clock = clock ?? DateTime.now;

  /// Asset paths are relative to the `assets/` prefix the player adds, so
  /// `sounds/ui_tap.wav` resolves to `assets/sounds/ui_tap.wav`.
  static const Map<SoundEventType, String> assets = {
    SoundEventType.buttonTap: 'sounds/ui_tap.wav',
    SoundEventType.selectionChanged: 'sounds/selection.wav',
    SoundEventType.transactionSaved: 'sounds/transaction_saved.wav',
    SoundEventType.actionSucceeded: 'sounds/action_success.wav',
    SoundEventType.actionFailed: 'sounds/action_failed.wav',
    SoundEventType.milestoneReached: 'sounds/milestone.wav',
  };

  /// Ceiling for playback volume. Kept low on purpose: these are UI cues, not
  /// media. The assets themselves are also mastered at -6 dBFS.
  static const double defaultVolume = 0.45;

  final SoundPlayer _player;
  final DateTime Function() _clock;

  final Set<String> _loaded = {};
  final Map<SoundEventType, DateTime> _lastFired = {};
  bool _initializing = false;
  bool _disposed = false;

  /// Assets that loaded successfully. Empty until [init] first succeeds.
  @visibleForTesting
  Set<String> get loadedAssets => Set.unmodifiable(_loaded);

  /// Whether at least one cue is ready to play.
  bool get isReady => _loaded.isNotEmpty;

  /// Loads every bundled cue. Safe to call more than once.
  Future<void> init() async {
    if (_disposed || _initializing) return;
    _initializing = true;
    try {
      final loaded = await _player.preload(assets.values);
      _loaded
        ..clear()
        ..addAll(loaded);
    } catch (error) {
      // A player that cannot even preload leaves the service silent, which is
      // the correct degraded behaviour.
      debugPrint('SoundService: preload failed — $error');
    } finally {
      _initializing = false;
    }
  }

  /// Fires [event] if the current [prefs] allow it and it is not a duplicate.
  ///
  /// Never throws, and never blocks the caller beyond the player hand-off.
  Future<void> play(
    SoundEventType event,
    SoundPreferences prefs, {
    double volume = defaultVolume,
  }) async {
    if (_disposed) return;

    final asset = assets[event];
    if (asset == null || !prefs.allows(event)) return;

    if (!_loaded.contains(asset)) {
      // Either preloading is still in flight or this asset is missing. Kick a
      // single retry so a very early tap is merely silent, not permanently so.
      unawaited(init());
      return;
    }

    if (_isDuplicate(event)) return;
    _lastFired[event] = _clock();

    try {
      await _player.play(asset, volume: volume);
    } catch (error) {
      // Playback failure is swallowed by design.
      debugPrint('SoundService: playback failed for $event — $error');
    }
  }

  bool _isDuplicate(SoundEventType event) {
    final last = _lastFired[event];
    if (last == null) return false;
    return _clock().difference(last) < event.repeatWindow;
  }

  /// Stops playback when the app leaves the foreground.
  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (_disposed || state == AppLifecycleState.resumed) return;
    try {
      await _player.stopAll();
    } catch (_) {
      // Nothing to do — a cue is not worth surfacing an error for.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lastFired.clear();
    _loaded.clear();
    try {
      await _player.dispose();
    } catch (_) {
      // Ignore: disposal must never throw during teardown.
    }
  }
}

/// Production [SoundPlayer] built on `audioplayers`.
///
/// One long-lived, pre-loaded player per cue. Each cue is single-instance by
/// design — the service already suppresses duplicates, so a second overlapping
/// copy of the same tick would only add mud.
class AudioPlayersSoundPlayer implements SoundPlayer {
  /// Tells the OS these are user-interface sounds, not media.
  ///
  /// Android: `sonification` content + `assistanceSonification` usage means the
  /// cue is routed as a UI effect, and `audioFocus: none` guarantees we never
  /// steal focus from music the user is already playing.
  /// iOS: the `ambient` category is silenced by the Ring/Silent switch.
  static final AudioContext _audioContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
      stayAwake: false,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final Map<String, AudioPlayer> _players = {};
  bool _disposed = false;

  @override
  Future<Set<String>> preload(Iterable<String> assets) async {
    final loaded = <String>{};
    if (_disposed) return loaded;

    for (final asset in assets) {
      if (_players.containsKey(asset)) {
        loaded.add(asset);
        continue;
      }
      AudioPlayer? player;
      try {
        player = AudioPlayer();
        // Low latency matters: a 45 ms tick is worthless if it starts 150 ms
        // after the finger lifts.
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setAudioContext(_audioContext);
        await player.setSource(AssetSource(asset));
        _players[asset] = player;
        loaded.add(asset);
      } catch (error) {
        debugPrint('SoundService: could not load $asset — $error');
        try {
          await player?.dispose();
        } catch (_) {
          // Nothing further to do.
        }
      }
    }
    return loaded;
  }

  @override
  Future<void> play(String asset, {required double volume}) async {
    final player = _players[asset];
    if (player == null || _disposed) return;
    // stop -> setVolume -> resume replays from the start with the new volume,
    // which is how a low-latency player restarts a one-shot cue.
    await player.stop();
    await player.setVolume(volume);
    await player.resume();
  }

  @override
  Future<void> stopAll() async {
    for (final player in _players.values) {
      try {
        await player.stop();
      } catch (_) {
        // A cue that cannot be stopped is not worth reporting.
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final players = _players.values.toList(growable: false);
    _players.clear();
    for (final player in players) {
      try {
        await player.dispose();
      } catch (_) {
        // Ignore: teardown never throws.
      }
    }
  }
}
