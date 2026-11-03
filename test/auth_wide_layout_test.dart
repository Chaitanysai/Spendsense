import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/screens/auth/auth_screen.dart';
import 'package:spendsense/widgets/glass_card.dart';

void main() {
  testWidgets('auth form stays readable in a wide landscape viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.getSize(find.byType(GlassCard));
    expect(card.width, lessThanOrEqualTo(520));
    expect(card.width, greaterThan(400));
  });
}
