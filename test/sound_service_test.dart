import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/sound_provider.dart';
import 'package:spendsense/services/sound_service.dart';

import 'support/sound_test_doubles.dart';

const Map<SoundEventType, String> kAssets = SoundService.assets;

void main() {
  // SoundProvider reads and writes SharedPreferences, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SoundPreferences', () {
    test('defaults enable everything', () {
      const prefs = SoundPreferences.defaults;
      expect(prefs.masterEnabled, isTrue);
      expect(prefs.uiEnabled, isTrue);
      expect(prefs.transactionsEnabled, isTrue);
      for (final event in SoundEventType.values) {
        expect(prefs.allows(event), isTrue, reason: '$event should be allowed');
      }
    });

    test('events are split into exactly two categories', () {
      expect(SoundEventType.buttonTap.category, SoundCategory.ui);
      expect(SoundEventType.selectionChanged.category, SoundCategory.ui);
      expect(
          SoundEventType.transactionSaved.category, SoundCategory.transaction);
      expect(
          SoundEventType.actionSucceeded.category, SoundCategory.transaction);
      expect(SoundEventType.actionFailed.category, SoundCategory.transaction);
      expect(
          SoundEventType.milestoneReached.category, SoundCategory.transaction);
    });

    test('master mute blocks every category', () {
      const prefs = SoundPreferences(masterEnabled: false);
      for (final event in SoundEventType.values) {
        expect(prefs.allows(event), isFalse);
      }
    });

    test('ui off leaves transaction sounds enabled', () {
      const prefs = SoundPreferences(uiEnabled: false);
      expect(prefs.allows(SoundEventType.buttonTap), isFalse);
      expect(prefs.allows(SoundEventType.selectionChanged), isFalse);
      expect(prefs.allows(SoundEventType.transactionSaved), isTrue);
      expect(prefs.allows(SoundEventType.actionSucceeded), isTrue);
    });

    test('transaction sounds off leaves ui sounds enabled', () {
      const prefs = SoundPreferences(transactionsEnabled: false);
      expect(prefs.allows(SoundEventType.buttonTap), isTrue);
      expect(prefs.allows(SoundEventType.transactionSaved), isFalse);
      expect(prefs.allows(SoundEventType.actionFailed), isFalse);
    });

    test('copyWith only changes what it is given', () {
      const base = SoundPreferences();
      final next = base.copyWith(uiEnabled: false);
      expect(next.uiEnabled, isFalse);
      expect(next.masterEnabled, isTrue);
      expect(next.transactionsEnabled, isTrue);
      expect(next, isNot(base));
    });
  });

  group('SoundService dispatch', () {
    late TestClock clock;
    late RecordingSoundPlayer player;
    late SoundService service;

    setUp(() {
      clock = TestClock();
      player = RecordingSoundPlayer();
      service = SoundService(player: player, clock: clock.call);
    });

    test('every event maps to a distinct bundled asset', () {
      expect(kAssets.keys.toSet(), SoundEventType.values.toSet());
      expect(kAssets.values.toSet(), hasLength(SoundEventType.values.length));
      for (final asset in kAssets.values) {
        expect(asset, startsWith('sounds/'));
        expect(asset, endsWith('.wav'));
      }
    });

    test('init preloads the whole cue set', () async {
      await service.init();
      expect(player.preloadCalls, 1);
      expect(service.loadedAssets, kAssets.values.toSet());
      expect(service.isReady, isTrue);
    });

    test('a prefs-allowed event plays its asset at a restrained volume',
        () async {
      await service.init();
      await service.play(SoundEventType.buttonTap, SoundPreferences.defaults);

      expect(player.played, [kAssets[SoundEventType.buttonTap]]);
      expect(player.volumes.single, SoundService.defaultVolume);
      expect(SoundService.defaultVolume, lessThan(0.5));
    });

    test('a disallowed event is never handed to the player', () async {
      await service.init();
      await service.play(
        SoundEventType.buttonTap,
        const SoundPreferences(masterEnabled: false),
      );
      await service.play(
        SoundEventType.transactionSaved,
        const SoundPreferences(transactionsEnabled: false),
      );
      expect(player.played, isEmpty);
    });

    test('the same event cannot stack within its repeat window', () async {
      await service.init();
      const prefs = SoundPreferences();

      await service.play(SoundEventType.buttonTap, prefs);
      await service.play(SoundEventType.buttonTap, prefs);
      expect(player.played, hasLength(1),
          reason: 'a double-fired tap must not play twice');

      clock.advance(const Duration(milliseconds: 120));
      await service.play(SoundEventType.buttonTap, prefs);
      expect(player.played, hasLength(2));
    });

    test('duplicate suppression is per event, not global', () async {
      await service.init();
      const prefs = SoundPreferences();

      await service.play(SoundEventType.buttonTap, prefs);
      await service.play(SoundEventType.selectionChanged, prefs);

      expect(player.played, [
        kAssets[SoundEventType.buttonTap],
        kAssets[SoundEventType.selectionChanged],
      ]);
    });

    test('transaction cues use a wider window than interaction cues', () {
      expect(
        SoundEventType.transactionSaved.repeatWindow,
        greaterThan(SoundEventType.buttonTap.repeatWindow),
      );
      expect(SoundEventType.actionFailed.repeatWindow,
          SoundEventType.transactionSaved.repeatWindow);
    });
  });

  group('SoundService failure handling', () {
    test('a missing asset is skipped without throwing', () async {
      final player = RecordingSoundPlayer(
        loadable: {SoundService.assets[SoundEventType.buttonTap]!},
      );
      final service = SoundService(player: player);
      await service.init();

      expect(service.loadedAssets,
          {SoundService.assets[SoundEventType.buttonTap]});

      await service.play(SoundEventType.buttonTap, SoundPreferences.defaults);
      await service.play(
          SoundEventType.transactionSaved, SoundPreferences.defaults);

      expect(player.played, [SoundService.assets[SoundEventType.buttonTap]]);
    });

    test('a player that fails to preload leaves the service silent', () async {
      final player = RecordingSoundPlayer(failPreload: true);
      final service = SoundService(player: player);

      await service.init(); // must not throw
      expect(service.isReady, isFalse);

      await service.play(SoundEventType.buttonTap, SoundPreferences.defaults);
      expect(player.played, isEmpty);
    });

    test('a playback error is swallowed', () async {
      final player = RecordingSoundPlayer(failPlay: true);
      final service = SoundService(player: player);
      await service.init();

      await expectLater(
        service.play(SoundEventType.buttonTap, SoundPreferences.defaults),
        completes,
      );
      expect(player.played, isEmpty);
    });

    test('playing before init() is silent but triggers a load', () async {
      final player = RecordingSoundPlayer();
      final service = SoundService(player: player);

      await service.play(SoundEventType.buttonTap, SoundPreferences.defaults);

      expect(player.played, isEmpty, reason: 'nothing loaded yet');
      expect(player.preloadCalls, 1, reason: 'a retry was kicked off');
    });
  });

  group('SoundService lifecycle and disposal', () {
    test('going to the background stops playback', () async {
      final player = RecordingSoundPlayer();
      final service = SoundService(player: player);
      await service.init();

      await service.handleLifecycle(AppLifecycleState.paused);
      await service.handleLifecycle(AppLifecycleState.hidden);
      expect(player.stopAllCalls, 2);

      await service.handleLifecycle(AppLifecycleState.resumed);
      expect(player.stopAllCalls, 2, reason: 'resuming has nothing to stop');
    });

    test('dispose releases the player and ignores later plays', () async {
      final player = RecordingSoundPlayer();
      final service = SoundService(player: player);
      await service.init();

      await service.dispose();
      expect(player.disposeCalls, 1);

      await service.play(SoundEventType.buttonTap, SoundPreferences.defaults);
      expect(player.played, isEmpty);
    });

    test('dispose is idempotent', () async {
      final player = RecordingSoundPlayer();
      final service = SoundService(player: player);
      await service.dispose();
      await service.dispose();
      expect(player.disposeCalls, 1);
    });
  });

  group('SoundProvider persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<SoundProvider> loaded(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      final provider = SoundProvider(
        service: SoundService(player: RecordingSoundPlayer()),
        observeLifecycle: false,
      );
      await provider.initialized;
      return provider;
    }

    test('falls back to the defaults with nothing stored', () async {
      final provider = await loaded({});
      expect(provider.isRestored, isTrue);
      expect(provider.prefs, SoundPreferences.defaults);
    });

    test('restores previously stored values', () async {
      final provider = await loaded({
        SoundProvider.masterKey: true,
        SoundProvider.uiKey: false,
        SoundProvider.transactionsKey: false,
      });
      expect(provider.masterEnabled, isTrue);
      expect(provider.uiEnabled, isFalse);
      expect(provider.transactionsEnabled, isFalse);
    });

    test('every toggle persists under a stable key', () async {
      final provider = await loaded({});

      await provider.setMasterEnabled(false);
      await provider.setUiEnabled(false);
      await provider.setTransactionsEnabled(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SoundProvider.masterKey), isFalse);
      expect(prefs.getBool(SoundProvider.uiKey), isFalse);
      expect(prefs.getBool(SoundProvider.transactionsKey), isFalse);
    });

    test('settings survive a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final first = SoundProvider(
        service: SoundService(player: RecordingSoundPlayer()),
        observeLifecycle: false,
      );
      await first.initialized;
      await first.setMasterEnabled(false);
      await first.setUiEnabled(false);

      final second = SoundProvider(
        service: SoundService(player: RecordingSoundPlayer()),
        observeLifecycle: false,
      );
      await second.initialized;

      expect(second.masterEnabled, isFalse);
      expect(second.uiEnabled, isFalse);
      expect(second.transactionsEnabled, isTrue);
    });

    test('notifies on change but not on a no-op write', () async {
      final provider = await loaded({});
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setUiEnabled(false);
      expect(notified, 1);

      await provider.setUiEnabled(false);
      expect(notified, 1, reason: 'writing the same value changes nothing');
    });

    test('master mute takes effect on the very next play', () async {
      final player = RecordingSoundPlayer();
      final provider = SoundProvider(
        service: SoundService(player: player),
        observeLifecycle: false,
      );
      await provider.initialized;

      await provider.play(SoundEventType.transactionSaved);
      expect(player.played, hasLength(1));

      await provider.setMasterEnabled(false);
      await provider.play(SoundEventType.actionSucceeded);
      expect(player.played, hasLength(1),
          reason: 'muted: the second cue must not reach the player');
    });

    test('turning off interaction sounds keeps transaction sounds', () async {
      final player = RecordingSoundPlayer();
      final provider = SoundProvider(
        service: SoundService(player: player),
        observeLifecycle: false,
      );
      await provider.initialized;
      await provider.setUiEnabled(false);

      await provider.play(SoundEventType.buttonTap);
      await provider.play(SoundEventType.transactionSaved);

      expect(player.played, [kAssets[SoundEventType.transactionSaved]]);
    });

    test('dispose releases the underlying service', () async {
      final player = RecordingSoundPlayer();
      final provider = SoundProvider(
        service: SoundService(player: player),
        observeLifecycle: false,
      );
      await provider.initialized;

      provider.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(player.disposeCalls, 1);
    });
  });
}
