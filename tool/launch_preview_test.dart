// Render the release launch screen to docs/design-research/launch-screen.png.
//
// Run:
//   flutter test --no-pub tool/launch_preview_test.dart
//
// This is a design preview, not a committed test suite: keeping it under tool/
// means `flutter test` does not write assets during normal verification.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/screens/launch_screen.dart';

Future<void> _loadFonts() async {
  final loader = FontLoader('Poppins');
  for (final file in [
    'Poppins-Regular.ttf',
    'Poppins-Medium.ttf',
    'Poppins-SemiBold.ttf',
    'Poppins-Bold.ttf',
  ]) {
    loader.addFont(rootBundle.load('assets/fonts/$file'));
  }
  await loader.load();
}

void main() {
  testWidgets('render launch screen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _loadFonts();

    const key = ValueKey('launch-preview');
    await tester.pumpWidget(
      const RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: SpendSenseLaunchScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('docs/design-research/launch-screen.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
