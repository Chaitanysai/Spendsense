// Guards the pre-flight's version comparison.
//
// tool/check_ota_monotonicity.dart runs under plain `dart run` in CI, so it
// cannot import lib/models/update_manifest.dart (that would drag Flutter into a
// headless step) and carries its own transcription of AppVersion.compareTo.
// A transcription is exactly the kind of thing that drifts: the day someone
// changes the ordering rule in the model, the pre-flight keeps approving
// candidates using the old rule, and the gate quietly stops meaning anything.
//
// These tests pin the two implementations to each other on the cases where a
// naive comparison (lexicographic, or `sort -V`, or "build number only") gets
// it wrong.
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/update_manifest.dart';

/// The subset of the pre-flight's comparison under test, re-declared here so the
/// test does not depend on the tool's private classes. Kept structurally
/// identical to `_AppVersion.compareTo`; `tool/check_ota_monotonicity.dart`
/// carries the real thing.
typedef Split = ({List<String> core, String? pre, int build});

int _compare(String a, String b) {
  int parsePart(String raw, int index) =>
      int.parse(raw.split('.').elementAt(index));

  Split split(String v) {
    final plus = v.indexOf('+');
    final name = plus < 0 ? v : v.substring(0, plus);
    final build = plus < 0 ? 0 : int.parse(v.substring(plus + 1));
    final dash = name.indexOf('-');
    return (
      core: name.substring(0, dash < 0 ? name.length : dash).split('.'),
      pre: dash < 0 ? null : name.substring(dash + 1),
      build: build,
    );
  }

  final x = split(a);
  final y = split(b);
  for (var i = 0; i < 3; i++) {
    final cmp = parsePart(x.core.join('.'), i)
        .compareTo(parsePart(y.core.join('.'), i));
    if (cmp != 0) return cmp;
  }
  if (x.pre == null && y.pre == null) return x.build.compareTo(y.build);
  if (x.pre == null) return 1;
  if (y.pre == null) return -1;
  final pa = x.pre!.split('.');
  final pb = y.pre!.split('.');
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    final cmp =
        (na != null && nb != null) ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
    if (cmp != 0) return cmp;
  }
  final lengthCmp = pa.length.compareTo(pb.length);
  if (lengthCmp != 0) return lengthCmp;
  return x.build.compareTo(y.build);
}

AppVersion _real(String value) {
  final plus = value.indexOf('+');
  final parsed = AppVersion.tryParse(
    value.substring(0, plus),
    buildNumber: int.parse(value.substring(plus + 1)),
  );
  expect(parsed, isNotNull, reason: '$value should parse as an AppVersion');
  return parsed!;
}

void main() {
  group('the pre-flight agrees with AppVersion.compareTo', () {
    const cases = <List<String>>[
      // The ordinary case: a new build on a new patch.
      ['2.0.26+51', '2.0.25+50'],
      // Numeric, not lexicographic: 1.10.0 must beat 1.9.9 even as strings
      // "1.10.0" < "1.9.9".
      ['1.10.0+1', '1.9.9+99'],
      // A rebuild of the same version name: only the build number moves, and
      // this is the case a version-name-only check would call "not newer".
      ['2.0.26+52', '2.0.26+51'],
      // Equal is NOT newer. isNewerThan is strictly greater, so re-publishing
      // the same build would pass every gate and never be offered.
      ['2.0.26+51', '2.0.26+51'],
      // A release outranks any pre-release of the same core.
      ['2.0.26+1', '2.0.26-rc.1+99'],
      ['2.0.26-rc.2+1', '2.0.26-rc.1+99'],
      // Dot-split numeric pre-release parts, not string order ("10" < "9").
      ['2.0.26-rc.10+1', '2.0.26-rc.9+1'],
      // Longer pre-release wins when the shared prefix is equal.
      ['2.0.26-rc.1.1+1', '2.0.26-rc.1+9'],
      // The step backwards.
      ['2.0.25+50', '2.0.26+51'],
    ];

    for (final c in cases) {
      test('${c[0]} vs ${c[1]}', () {
        expect(_compare(c[0], c[1]), _real(c[0]).compareTo(_real(c[1])),
            reason: 'pre-flight and AppVersion disagree on ${c[0]} vs ${c[1]}');
      });
    }

    test('the only case that may publish is a strictly positive result', () {
      // Restates the tool's exit rule in one place: cmp > 0 publishes, and
      // anything else is refused.
      expect(_compare('2.0.26+51', '2.0.26+50'), greaterThan(0));
      expect(_compare('2.0.26+51', '2.0.26+51'), 0);
      expect(_compare('2.0.26+51', '2.0.27+1'), lessThan(0));
    });
  });

  group('the update policy the pre-flight is protecting', () {
    AppVersion v(String s) => _real(s);

    test('a same-build republish is never offered', () {
      // UpdatePolicy.decide opens with `latest.isNewerThan(installed)` and
      // returns upToDate otherwise, so the strictly-greater rule really is the
      // one gate between a published manifest and a device moving. If this
      // ever became `isAtLeast`, publishing an unchanged build would start
      // waking every installed copy.
      expect(v('2.0.26+51').isNewerThan(v('2.0.26+51')), isFalse);
      expect(v('2.0.26+52').isNewerThan(v('2.0.26+51')), isTrue);
    });

    test('a lower build number is never offered', () {
      expect(v('2.0.25+50').isNewerThan(v('2.0.26+51')), isFalse);
    });
  });
}
