import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/utils/dashboard_sections.dart';

Future<ThemeProvider> _loaded() async {
  final theme = ThemeProvider();
  for (var i = 0; i < 50 && !theme.isLoaded; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return theme;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DashboardSection order rules', () {
    test('default order is the known ids', () {
      expect(DashboardSection.normalizeOrder(null), DashboardSection.ids);
    });

    test('unknown, duplicate and wrong-type entries are dropped', () {
      expect(
        DashboardSection.normalizeOrder(
            ['recent', 'ghost', 'recent', 7, 'budget']),
        ['recent', 'budget', 'categories', 'weekly'],
      );
      expect(
          DashboardSection.normalizeOrder('not a list'), DashboardSection.ids);
    });

    test('a section missing from an older saved order is appended', () {
      expect(DashboardSection.normalizeOrder(['weekly', 'budget']),
          ['weekly', 'budget', 'categories', 'recent']);
    });

    test('reordering visible sections never moves or reveals hidden ones', () {
      const order = ['budget', 'categories', 'weekly', 'recent'];
      final next = DashboardSection.reorderVisible(
          order, {'categories'}, 0, 3); // budget to the end of visible
      expect(next, ['weekly', 'categories', 'recent', 'budget']);
      expect(DashboardSection.visibleInOrder(next, {'categories'}),
          ['weekly', 'recent', 'budget']);
    });

    test('out-of-range moves are ignored', () {
      const order = ['budget', 'categories', 'weekly', 'recent'];
      expect(DashboardSection.reorderVisible(order, {}, 9, 0), order);
    });
  });

  group('ThemeProvider dashboard order', () {
    test('new users get the default order', () async {
      final theme = await _loaded();
      expect(theme.sectionOrder, DashboardSection.ids);
    });

    test('a saved order survives recreation and keeps hidden sections hidden',
        () async {
      final theme = await _loaded();
      await theme.setSectionVisible('weekly', false);
      await theme.setSectionOrder(['recent', 'weekly', 'budget', 'categories']);

      final reloaded = await _loaded();
      expect(
          reloaded.sectionOrder, ['recent', 'weekly', 'budget', 'categories']);
      expect(reloaded.isSectionVisible('weekly'), isFalse);
      expect(reloaded.visibleSectionOrder, ['recent', 'budget', 'categories']);
    });

    test('stale or malformed stored values fall back safely', () async {
      SharedPreferences.setMockInitialValues({
        'dashboard_section_order': ['old_widget', 'recent'],
      });
      final stale = await _loaded();
      expect(stale.sectionOrder, ['recent', 'budget', 'categories', 'weekly']);

      SharedPreferences.setMockInitialValues({
        'dashboard_section_order': 'garbage',
      });
      final bad = await _loaded();
      expect(bad.sectionOrder, DashboardSection.ids);
    });

    test('reset restores the default order', () async {
      final theme = await _loaded();
      await theme.setSectionOrder(['recent', 'weekly', 'categories', 'budget']);
      await theme.resetSectionOrder();
      expect((await _loaded()).sectionOrder, DashboardSection.ids);
    });
  });
}
