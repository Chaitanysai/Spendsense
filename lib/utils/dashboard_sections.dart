/// Dashboard sections the user may show or hide. Quick actions and the balance
/// card are always shown: they are the dashboard's core and its entry points.
class DashboardSection {
  DashboardSection._();

  static const String budget = 'budget';
  static const String categories = 'categories';
  static const String weekly = 'weekly';
  static const String recent = 'recent';

  static const List<String> ids = [budget, categories, weekly, recent];

  static String label(String id) => switch (id) {
        budget => 'Monthly budget',
        categories => 'Spending by category',
        weekly => 'Last 7 days',
        recent => 'Recent transactions',
        _ => id,
      };
}
