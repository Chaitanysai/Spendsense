import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';
import 'page_entry.dart';

/// Backwards-compatible name for the reusable page-entry fade + glide.
///
/// It keeps its original one-shot behaviour when no [PageEntryHost] is above
/// it, and replays whenever an enclosing page entry is signalled. Because the
/// scope mechanism is shared, a retained tab or a route revealed by a pop no
/// longer leaves this animation parked at its finished state.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final double offset;

  /// Optional list position for the subtle bounded stagger.
  final int? index;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.offset = 0.06,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    return PageEntrance(
      offset: offset,
      duration: AppMotion.slow,
      index: index,
      child: child,
    );
  }
}
