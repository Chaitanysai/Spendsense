import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_text_styles.dart';
import '../utils/money_parser.dart';

/// A single-amount dialog that validates **inline** and stays open on error.
///
/// The previous pattern popped the dialog with whatever text was typed and
/// validated afterwards, then reported the failure in a SnackBar at the bottom
/// of the screen — detached from the field, and gone a few seconds later. The
/// user had to reopen the dialog and retype the amount.
///
/// Here the error is attached to the field it belongs to, the dialog stays
/// open, and the text the user typed is preserved so they can correct it.
///
/// Returns the parsed amount in integer paise, or null if the user cancelled.
Future<int?> showAmountDialog(
  BuildContext context, {
  required String title,
  String? initialText,
  String hintText = 'e.g. 5000',
  String? helperText,
  String prefixText = '₹ ',
  String saveLabel = 'Save',
  /// Upper bound in paise. Values above it are rejected with [rangeError].
  int? maxMinor,
  String rangeError = 'That amount is too large.',
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _AmountInputDialog(
      title: title,
      initialText: initialText,
      hintText: hintText,
      helperText: helperText,
      prefixText: prefixText,
      saveLabel: saveLabel,
      maxMinor: maxMinor,
      rangeError: rangeError,
    ),
  );
}

class _AmountInputDialog extends StatefulWidget {
  const _AmountInputDialog({
    required this.title,
    required this.initialText,
    required this.hintText,
    required this.helperText,
    required this.prefixText,
    required this.saveLabel,
    required this.maxMinor,
    required this.rangeError,
  });

  final String title;
  final String? initialText;
  final String hintText;
  final String? helperText;
  final String prefixText;
  final String saveLabel;
  final int? maxMinor;
  final String rangeError;

  @override
  State<_AmountInputDialog> createState() => _AmountInputDialogState();
}

class _AmountInputDialogState extends State<_AmountInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Validates on submit. Returns the parsed paise, or null after setting the
  /// inline error so the dialog stays open.
  int? _validate() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter an amount.');
      return null;
    }
    final int minor;
    try {
      minor = parseRupeesToPaise(raw);
    } on MoneyParseException {
      setState(() => _error = 'Enter a valid amount.');
      return null;
    }
    if (minor <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return null;
    }
    final max = widget.maxMinor;
    if (max != null && minor > max) {
      setState(() => _error = widget.rangeError);
      return null;
    }
    return minor;
  }

  void _submit() {
    final minor = _validate();
    if (minor == null) return;
    Navigator.pop(context, minor);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: AppText.title(context)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        // Clearing the error as soon as the user edits means the message never
        // lingers against text that has already been corrected.
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          prefixText: widget.prefixText,
          hintText: widget.hintText,
          helperText: widget.helperText,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
