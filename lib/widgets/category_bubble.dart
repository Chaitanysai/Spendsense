import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';

/// Circular, bubble-like category indicator.
///
/// A colour-tinted circle with the category's Material icon. Optionally shows
/// a percentage label beneath it (used by the spending visualisation).
class CategoryBubble extends StatelessWidget {
  final String category;
  final double size;
  final String? label;
  final String? percentLabel;
  final bool highlighted;

  const CategoryBubble({
    super.key,
    required this.category,
    this.size = 48,
    this.label,
    this.percentLabel,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(category);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: highlighted ? 0.32 : 0.20),
                color.withValues(alpha: highlighted ? 0.18 : 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: color.withValues(alpha: highlighted ? 0.55 : 0.28),
              width: 1.2,
            ),
          ),
          child: Icon(
            CategoryStyle.icon(category),
            size: size * 0.46,
            // The ring and wash keep the category hue; the glyph is measured
            // against the stronger gradient stop it sits on.
            color: AppColors.inkOnWash(
              context,
              color,
              alpha: highlighted ? 0.32 : 0.20,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption(context),
          ),
        ],
        if (percentLabel != null)
          Text(
            percentLabel!,
            style: AppText.weight(AppText.label(context), FontWeight.w700).copyWith(
              fontSize: 11,
              color: AppColors.resolveInk(color, AppColors.glassSurface(context)),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}
