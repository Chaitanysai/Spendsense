import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Barrier behind every modal sheet. One value so no sheet dims more than
/// another.
const Color kSheetBarrierColor = Color(0x6B000000); // black at ~42%

/// Sheet motion: [AppMotion.base] in, [AppMotion.fast] out, both zero when the
/// platform asks for reduced motion.
AnimationStyle appSheetAnimation(BuildContext context) {
  final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
  return AnimationStyle(
    duration: reduced ? Duration.zero : AppMotion.base,
    reverseDuration: reduced ? Duration.zero : AppMotion.fast,
    curve: AppMotion.emphasized,
    reverseCurve: AppMotion.easeOut,
  );
}

/// The one way the app opens a bottom sheet.
///
/// Every sheet gets the same entry/exit motion, barrier, safe-area handling and
/// drag/tap dismissal:
/// * `useSafeArea` keeps the sheet below the status bar.
/// * A sheet that uses the themed (opaque) surface is wrapped in a bottom-only
///   [SafeArea], so the last row clears the system navigation bar while the
///   surface still paints underneath it. A sheet with a *transparent*
///   background paints its own surface and handles the inset itself (the
///   Add, SMS date and salary sheets); wrapping those would leave a see-through
///   strip under the sheet, so they are not wrapped. Flutter's
///   `MediaQuery.padding` already shrinks while the keyboard is open, so
///   neither case doubles up with `viewInsets` padding.
/// * `isScrollControlled` lets a sheet grow past half height for large text and
///   rise above the keyboard; content still sizes to itself.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final ownsSurface = backgroundColor == Colors.transparent;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    shape: shape,
    barrierColor: kSheetBarrierColor,
    sheetAnimationStyle: appSheetAnimation(context),
    builder: (ctx) =>
        ownsSurface ? builder(ctx) : SafeArea(top: false, child: builder(ctx)),
  );
}
