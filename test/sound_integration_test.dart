import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/sound_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/screens/sound_settings_screen.dart';
import 'package:spendsense/screens/transaction_details_screen.dart';
import 'package:spendsense/services/sound_service.dart';
import 'package:spendsense/widgets/app_button.dart';
import 'package:spendsense/widgets/pressable.dart';
import 'package:spendsense/widgets/sound_scope.dart';
import 'package:spendsense/widgets/transaction_type_toggle.dart';

import 'support/sound_test_doubles.dart';

/// A [TransactionProvider] whose writes are recorded rather than persisted.
///
/// Every write also takes a visible amount of time, so a test can watch the
/// exact moment the cue appears relative to the write landing ΓÇö and so the
/// failure case can model a real storage error.
class FakeTransactionProvider extends TransactionProvider {
  FakeTransactionProvider({this.failWrites = false});

  /// When `true` every write throws, standing in for a full disk or a locked
  /// database: nothing was saved and nothing may claim otherwise.
  final bool failWrites;

  final List<TransactionModel> added = <TransactionModel>[];
  final List<String> updated = <String>[];
  final List<TransactionType> updatedTypes = <TransactionType>[];

  static const Duration _writeLatency = Duration(milliseconds: 10);

  Future<void> _commit() async {
    await Future<void>.delayed(_writeLatency);
    if (failWrites) throw StateError('simulated persistence failure');
  }

  @override
  Future<void> addTransaction(TransactionModel transaction) async {
    await _commit();
    added.add(transaction);
    debugSeed([...transactions, transaction]);
  }

  @override
  Future<void> updateTransaction(
    String id, {
    required int amount,
    required String merchant,
    required String category,
    required TransactionType type,
    required bool isExcluded,
    String? bank,
  }) async {
    await _commit();
    updated.add(id);
    updatedTypes.add(type);
  }
}

/// A throwaway route whose only job is to push the screen under test, so the
/// screen can pop itself without emptying the Navigator.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.screen});

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => screen),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

TransactionModel _transaction({String merchant = 'Test Merchant'}) =>
    TransactionModel(
      id: 'tx-1',
      amount: 500,
      type: TransactionType.expense,
      merchant: merchant,
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 1, 5),
      time: '',
      originalSms: '',
      isExcluded: false,
      source: 'Manual',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late RecordingSoundPlayer player;
  late SoundProvider sound;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    player = RecordingSoundPlayer();
    sound = SoundProvider(
      service: SoundService(player: player),
      observeLifecycle: false,
    );
    await sound.initialized;
  });

  /// Pumps [screen] inside a [SoundScope] and a transaction provider, reached
  /// by pushing it from a launcher route.
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Widget screen,
    required TransactionProvider provider,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<TransactionProvider>.value(
        value: provider,
        child: SoundScope(
          provider: sound,
          child: MaterialApp(home: _Launcher(screen: screen)),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The screen's primary save button, used to assert the loading state comes
  /// back when a write fails.
  AppPrimaryButton saveButton(WidgetTester tester) =>
      tester.widget<AppPrimaryButton>(find.byType(AppPrimaryButton));

  testWidgets('a saved transaction fires its cue once, after the write lands',
      (tester) async {
    final provider = FakeTransactionProvider();
    await pumpScreen(
      tester,
      screen: const AddTransactionScreen(),
      provider: provider,
    );

    await tester.enterText(find.byType(TextField).first, '250');
    await tester.pump();
    await tester.tap(find.text('Add expense'));

    // The write is still in flight: a cue here would be a lie.
    expect(player.played, isEmpty,
        reason: 'nothing may be announced before the write completes');

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(provider.added, hasLength(1));
    expect(provider.added.single.amountMinor, 25000);
    expect(
      player.played,
      [SoundService.assets[SoundEventType.transactionSaved]],
      reason: 'exactly one cue, and it is the saved cue',
    );
    expect(find.byType(AddTransactionScreen), findsNothing,
        reason: 'a successful save closes the screen');
  });

  testWidgets('a failed save is reported, recovers the button and stays silent',
      (tester) async {
    final provider = FakeTransactionProvider(failWrites: true);
    await pumpScreen(
      tester,
      screen: const AddTransactionScreen(),
      provider: provider,
    );

    await tester.enterText(find.byType(TextField).first, '250');
    await tester.pump();
    await tester.tap(find.text('Add expense'));
    await tester.pump();

    expect(saveButton(tester).loading, isTrue,
        reason: 'the button shows progress while the write is in flight');

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(provider.added, isEmpty);
    expect(player.played, isEmpty,
        reason: 'a rejected write must never announce success');
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
    expect(find.byType(AddTransactionScreen), findsOneWidget,
        reason: 'the screen stays open so the entry can be retried');

    final button = saveButton(tester);
    expect(button.loading, isFalse,
        reason:
            'the loading state is always released, so the retry is possible');
    expect(button.onPressed, isNotNull,
        reason: 'save is interactive again after the failure');
    expect(tester.takeException(), isNull,
        reason: 'the storage error is handled, not left unhandled');
  });

  testWidgets(
      'a failed edit is reported, keeps the route open and stays silent',
      (tester) async {
    final provider = FakeTransactionProvider(failWrites: true);
    await pumpScreen(
      tester,
      screen: TransactionDetailsScreen(transaction: _transaction()),
      provider: provider,
    );

    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(saveButton(tester).loading, isTrue);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(provider.updated, isEmpty);
    expect(player.played, isEmpty,
        reason: 'a rejected edit must never announce success');
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
    expect(find.byType(TransactionDetailsScreen), findsOneWidget);

    final button = saveButton(tester);
    expect(button.loading, isFalse);
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details picks the type with segments, not a dropdown overlay',
      (tester) async {
    final provider = FakeTransactionProvider();
    await pumpScreen(
      tester,
      screen: TransactionDetailsScreen(transaction: _transaction()),
      provider: provider,
    );

    expect(find.byType(DropdownButtonFormField<TransactionType>), findsNothing);
    expect(find.byType(TransactionTypeToggle), findsOneWidget);

    await tester.tap(find.text('Income'));
    await tester.pump();
    expect(player.played, isNotEmpty,
        reason: 'a real type change plays the selection cue');

    await tester.tap(find.text('Save changes'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(provider.updatedTypes, [TransactionType.income]);
  });
  testWidgets('a rejected edit plays the failure cue, never the success cue',
      (tester) async {
    final provider = FakeTransactionProvider();
    await pumpScreen(
      tester,
      screen: TransactionDetailsScreen(transaction: _transaction(merchant: '')),
      provider: provider,
    );

    // Regression guard for the list tile inside this screen's decorated
    // container: it must own a Material, or Flutter reports that the tile's ink
    // splashes may be invisible.
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(provider.updated, isEmpty,
        reason: 'validation failure must not reach the provider');
    expect(
      player.played,
      [SoundService.assets[SoundEventType.actionFailed]],
      reason: 'the user is told, and the cue matches the outcome',
    );
    expect(find.text('Enter a valid merchant and amount'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound settings switches render cleanly inside their card',
      (tester) async {
    await tester.pumpWidget(
      SoundScope(
        provider: sound,
        child: const MaterialApp(home: SoundSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Interaction sounds'), findsOneWidget);
    // Regression guard: these SwitchListTiles sit inside a decorated
    // GlassCard, so each needs its own Material.
    expect(tester.takeException(), isNull);
  });

  group('no duplicated cues', () {
    /// Taps once and lets any second cue arrive, then reports what played.
    Future<List<String>> singleTap(WidgetTester tester, Finder target) async {
      player.played.clear();
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 500));
      return List<String>.of(player.played);
    }

    testWidgets('AppPrimaryButton fires exactly one tap cue, not two',
        (tester) async {
      // AppPrimaryButton nests Pressable *and* InkWell, each with an onTap.
      // Exactly one of them may announce the press.
      var taps = 0;
      await tester.pumpWidget(
        SoundScope(
          provider: sound,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  child: AppPrimaryButton(
                    label: 'Continue',
                    onPressed: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final played = await singleTap(tester, find.byType(AppPrimaryButton));

      expect(taps, 1, reason: 'the action itself still runs exactly once');
      expect(
        played,
        [SoundService.assets[SoundEventType.buttonTap]],
        reason: 'one press must produce exactly one cue',
      );
    });

    testWidgets('an AppPrimaryButton with sound:null stays completely silent',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        SoundScope(
          provider: sound,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  child: AppPrimaryButton(
                    label: 'Save',
                    sound: null,
                    onPressed: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final played = await singleTap(tester, find.byType(AppPrimaryButton));

      expect(taps, 1);
      expect(played, isEmpty,
          reason: 'screens that own a state cue suppress the generic tick');
    });

    testWidgets('a Pressable with a cue fires once per tap and not on drag',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        SoundScope(
          provider: sound,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: Pressable(
                  sound: SoundEventType.buttonTap,
                  onTap: () => taps++,
                  child: const SizedBox(width: 220, height: 60),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final played = await singleTap(tester, find.byType(Pressable));
      expect(taps, 1);
      expect(played, [SoundService.assets[SoundEventType.buttonTap]]);

      // A drag across the control must not tick: no tap was ever recognised.
      player.played.clear();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Pressable)),
      );
      await gesture.moveBy(const Offset(0, 60));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));

      expect(taps, 1, reason: 'the drag is not a tap');
      expect(player.played, isEmpty, reason: 'a drag must stay silent');
    });

    testWidgets('the saved cue is the only cue a successful save emits',
        (tester) async {
      final provider = FakeTransactionProvider();
      await pumpScreen(
        tester,
        screen: const AddTransactionScreen(),
        provider: provider,
      );

      player.played.clear();
      await tester.enterText(find.byType(TextField).first, '250');
      await tester.pump();
      await tester.tap(find.text('Add expense'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(
        player.played,
        [SoundService.assets[SoundEventType.transactionSaved]],
        reason: 'no generic tap tick is stacked on top of the saved cue',
      );
    });
  });
}
