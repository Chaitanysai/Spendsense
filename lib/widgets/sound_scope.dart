import 'dart:async';

import 'package:flutter/widgets.dart';

import '../providers/sound_provider.dart';
import '../services/sound_service.dart';

/// Publishes the app's [SoundProvider] to the widget tree and gives every call
/// site a null-safe way to fire a cue.
///
/// Two reasons this exists rather than a plain `context.read<SoundProvider>()`:
///
/// * Sound is a cross-cutting garnish. Any widget must be able to emit a cue
///   without the app having to guarantee a provider in scope, which keeps
///   existing screens and widget tests working untouched.
/// * [play] must not create a rebuild dependency. It resolves the provider
///   *without* subscribing, so a cue can never trigger a rebuild, and firing one
///   inside `build` (which the code deliberately never does) could not loop.
class SoundScope extends InheritedNotifier<SoundProvider> {
  const SoundScope({
    super.key,
    required SoundProvider provider,
    required super.child,
  }) : super(notifier: provider);

  /// The current provider, or `null` when no [SoundScope] is above [context]
  /// (for example a widget test that does not care about audio).
  ///
  /// Resolves *without* subscribing, so firing a cue never creates a rebuild
  /// dependency.
  static SoundProvider? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SoundScope>()?.notifier;

  /// Like [maybeOf], but subscribes: the caller rebuilds when a preference
  /// changes. For settings surfaces that must reflect the live switch state.
  static SoundProvider? watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SoundScope>()?.notifier;

  /// Fires [event] if a scope is in range. A no-op otherwise.
  ///
  /// Never awaited by design: audio must not be able to delay or fail the
  /// interaction that triggered it.
  static void play(BuildContext context, SoundEventType event) =>
      playOn(maybeOf(context), event);

  /// Fires [event] on an already-resolved [provider].
  ///
  /// Use this after an `await`, where [context] may have been deactivated by
  /// the time the action completes (a save that pops its own route).
  static void playOn(SoundProvider? provider, SoundEventType event) {
    if (provider == null) return;
    unawaited(provider.play(event));
  }
}
