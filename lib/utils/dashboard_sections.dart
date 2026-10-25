/// Dashboard sections the user may show, hide or reorder. Quick actions and the
/// balance card are always shown first: they are the dashboard's core and its
/// entry points.
///
/// Ids are stable persistence keys. Never persist labels or list indices.
class DashboardSection {
  DashboardSection._();

  static const String budget = 'budget';
  static const String categories = 'categories';
  static const String weekly = 'weekly';
  static const String recent = 'recent';

  /// The default order, and the complete set of known sections. A section added
  /// here later is appended to any older saved order by [normalizeOrder].
  static const List<String> ids = [budget, categories, weekly, recent];

  static String label(String id) => switch (id) {
        budget => 'Monthly budget',
        categories => 'Spending by category',
        weekly => 'Last 7 days',
        recent => 'Recent transactions',
        _ => id,
      };

  /// Turns anything stored (null, wrong type, duplicates, unknown or removed
  /// ids, missing ids) into a complete, duplicate-free order. Known ids keep
  /// their stored relative order; missing ones follow in default order.
  static List<String> normalizeOrder(Object? stored) {
    final result = <String>[];
    if (stored is Iterable) {
      for (final item in stored) {
        if (item is String && ids.contains(item) && !result.contains(item)) {
          result.add(item);
        }
      }
    }
    for (final id in ids) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  /// The sections to draw: [order] without the [hidden] ones.
  static List<String> visibleInOrder(
    List<String> order,
    Set<String> hidden,
  ) =>
      [
        for (final id in order)
          if (!hidden.contains(id)) id
      ];

  /// Moves one *visible* section and returns the new full order. Hidden
  /// sections never move, so hiding then reordering cannot re-enable or
  /// shuffle them. [newIndex] follows [ReorderableList.onReorder] semantics
  /// (the index before the removal is applied).
  static List<String> reorderVisible(
    List<String> order,
    Set<String> hidden,
    int oldIndex,
    int newIndex,
  ) {
    final visible = visibleInOrder(order, hidden);
    if (oldIndex < 0 || oldIndex >= visible.length) return order;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, visible.length - 1);
    final moved = visible.removeAt(oldIndex);
    visible.insert(target, moved);

    // Visible ids fill, in the new order, the slots visible ids occupied.
    var next = 0;
    return [
      for (final id in order) hidden.contains(id) ? id : visible[next++],
    ];
  }
}
