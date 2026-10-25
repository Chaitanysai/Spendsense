import 'package:flutter/material.dart';

/// Labelled, icon-led text field for the auth forms.
///
/// When [initiallyObscured] is set (password fields) the widget owns a
/// reveal toggle: a 48dp icon button carrying an explicit semantics label,
/// so the state change is announced and never conveyed by the icon alone.
/// Password fields also opt out of autocorrect and suggestions, and expose
/// an [autofillHint] so password managers fill the right field.
class AuthTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String label;
  final IconData icon;

  /// Shows the reveal toggle, starts the field obscured, and disables
  /// autocorrect and suggestions.
  final bool initiallyObscured;

  /// Client-side validation message, shown in the field's error slot.
  final String? errorText;
  final String? helperText;
  final String? hintText;
  final TextInputType? keyboardType;
  final String? autofillHint;
  final TextInputAction? textInputAction;
  final bool enabled;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Completes the reveal button's semantics label. Defaults to
  /// "password", so the toggle reads "Show password"; the confirm field
  /// passes its own qualifier.
  final String revealLabel;

  const AuthTextField({
    super.key,
    this.controller,
    this.focusNode,
    required this.label,
    required this.icon,
    this.initiallyObscured = false,
    this.errorText,
    this.helperText,
    this.hintText,
    this.keyboardType,
    this.autofillHint,
    this.textInputAction,
    this.enabled = true,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.revealLabel = 'password',
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured = widget.initiallyObscured;

  @override
  Widget build(BuildContext context) {
    final passwordManager = widget.autofillHint == null
        ? null
        : <String>[widget.autofillHint!];

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      obscureText: _obscured,
      // Passwords are literals: never mangled by autocorrect or filtered by
      // suggestions. Everything else keeps the platform defaults.
      autocorrect: !widget.initiallyObscured,
      enableSuggestions: !widget.initiallyObscured,
      autofillHints: passwordManager,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        prefixIcon: Icon(widget.icon),
        suffixIcon:
            widget.initiallyObscured ? _revealButton(context) : null,
      ),
    );
  }

  Widget _revealButton(BuildContext context) {
    final revealed = !_obscured;
    return Semantics(
      button: true,
      label: '${revealed ? 'Hide' : 'Show'} ${widget.revealLabel}',
      // The explicit label replaces the icon-only reading order, so a
      // screen reader never has to guess the glyph.
      excludeSemantics: true,
      child: IconButton(
        onPressed: () => setState(() => _obscured = revealed),
        icon: Icon(
          revealed
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
        ),
      ),
    );
  }
}
