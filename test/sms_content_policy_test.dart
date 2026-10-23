import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/services/sms_content_policy.dart';

// Task D (reduce-only): new records must stop retaining the raw SMS body.
//
// The decision "does this record keep its body?" is one place, so it can be
// flipped — or reverted — without touching the parser, the AI adapter, the
// importer, the model, the store or the UI. Existing stored bodies are left
// exactly as they are; nothing is rewritten.

const _bankDebit =
    'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26. Avl Bal Rs 12,340.50';

void main() {
  group('policy', () {
    test('the policy is reduce-only: bodies are not retained', () {
      expect(SmsContentPolicy.retainRawBodies, isFalse);
    });

    test('null is returned instead of the body for a new record', () {
      expect(SmsContentPolicy.retainedBody(_bankDebit), isNull);
    });

    test('an already-stored body passes through untouched', () {
      // Reading an existing record must never mutate it: a details screen or an
      // export still shows what was stored.
      expect(SmsContentPolicy.preserve(_bankDebit), _bankDebit);
      expect(SmsContentPolicy.preserve(''), '');
    });

    test('reviving retention is a one-line change and is covered', () {
      // Documents the flip: with the flag on, the body is kept (the old
      // behaviour). Guarded so a future flip cannot silently bypass this
      // decision without a failing test here.
      expect(
        SmsContentPolicy.bodyForNewRecord(
          _bankDebit,
          retainOverride: true,
        ),
        _bankDebit,
      );
    });
  });
}
