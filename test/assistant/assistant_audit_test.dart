import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/models/assistant_models.dart';
import 'package:spendsense/services/assistant/assistant_audit.dart';
import 'package:spendsense/services/ledger_encryption_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EncryptedAssistantAuditRepository', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('append succeeds when the audit store starts empty', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final repository = EncryptedAssistantAuditRepository(encryption: encryption);

      // An empty store must load as a mutable list: append() calls
      // entries.add, which throws on an unmodifiable/const empty list.
      expect(await repository.load(), isEmpty);

      await repository.append(
        AssistantAuditEntry(
          id: 'audit-1',
          type: AssistantChangeType.exclusion,
          createdAt: DateTime.utc(2026, 10, 30, 12),
          affectedCount: 1,
          totalMinor: 25000,
          transactionIds: const ['tx-1'],
          previousExcluded: const {'tx-1': false},
          deletedSnapshots: const [],
        ),
      );

      final entries = await repository.load();
      expect(entries, hasLength(1));
      expect(entries.single.id, 'audit-1');
    });

    test('appended entries survive a repository reload', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      await EncryptedAssistantAuditRepository(encryption: encryption).append(
        AssistantAuditEntry(
          id: 'audit-2',
          type: AssistantChangeType.deletion,
          createdAt: DateTime.utc(2026, 10, 30, 13),
          affectedCount: 2,
          totalMinor: 5000,
          transactionIds: const ['tx-1', 'tx-2'],
          previousExcluded: const {},
          deletedSnapshots: const [],
        ),
      );

      final reloaded =
          await EncryptedAssistantAuditRepository(encryption: encryption).load();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.id, 'audit-2');
    });
  });
}
