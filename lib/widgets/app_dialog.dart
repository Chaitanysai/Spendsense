import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';

/// The app's one dialog shell.
///
/// PanelUI `dialog` + `Card` anatomy: a title, an optional muted description, an
/// optional body, and a footer of actions that wraps instead of overflowing at
/// large text. The surface, hairline and radius come from `dialogTheme` in
/// `main.dart`, so a dialog, a sheet and a menu read as the same family.
///
/// Use [showAppConfirmDialog] for the common yes/no case; [AppDialog] directly
/// when the body is bespoke (a form, a list, a warning with details). Call sites
/// should never build a bare [AlertDialog] again: nineteen of them existed
/// before Phase 3.
class AppDialog extends StatelessWidget {
  final String title;
  final String? message;
  final IconData? icon;
  final Widget? content;

  /// False for the destructive variant: the icon plate and the confirm action
  /// both take the danger tone.
  final bool destructive;

  /// Let a long body scroll inside the dialog instead of growing past the
  /// screen. Short one-line messages should leave this false.
  final bool scrollable;

  final List<Widget> actions;

  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.content,
    this.destructive = false,
    this.scrollable = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tone =
        destructive ? AppColors.danger : AppColors.brandInk(context);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                tone.withValues(alpha: 0.14),
                AppColors.overlaySurface(context),
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 20, color: tone),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(title, style: AppText.title(context)),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            style: AppText.body(context)
                .copyWith(color: AppColors.textSecondary(context)),
          ),
        ],
        if (content != null) ...[
          const SizedBox(height: AppSpacing.lg),
          content!,
        ],
      ],
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scrollable)
                Flexible(child: SingleChildScrollView(child: body))
              else
                body,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                // A Wrap, not a Row: at 2× text two action labels do not fit
                // side by side on a 320dp phone, and wrapping keeps both.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The confirm action of an [AppDialog].
///
/// Kept as a button rather than a plain [FilledButton] so the destructive tone
/// resolves through the palette's measured ink instead of assuming white.
class AppDialogConfirmButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
  final bool loading;

  const AppDialogConfirmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill = destructive ? AppColors.danger : AppColors.filledBrand;
    final ink = destructive
        ? AppColors.resolveInk(Colors.white, AppColors.danger)
        : AppColors.resolveInk(Colors.white, AppColors.filledBrand);

    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: ink,
        disabledBackgroundColor: fill.withValues(alpha: 0.5),
        minimumSize: const Size(88, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        textStyle: AppText.weight(AppText.label(context), FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            )
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Yes/no confirmation. Returns `true` only when the confirm action was taken;
/// a barrier tap or the system back gesture resolves to `false`.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => AppDialog(
      title: title,
      message: message,
      icon: icon,
      destructive: destructive,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        AppDialogConfirmButton(
          label: confirmLabel,
          destructive: destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A single-action acknowledgement.
Future<void> showAppAlertDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  String dismissLabel = 'OK',
  IconData? icon,
  bool destructive = false,
  bool scrollable = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: title,
      message: message,
      icon: icon,
      destructive: destructive,
      scrollable: scrollable,
      content: content,
      actions: [
        AppDialogConfirmButton(
          label: dismissLabel,
          destructive: destructive,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}
