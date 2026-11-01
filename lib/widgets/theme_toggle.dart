import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'sound_scope.dart';

/// The Home appearance switch.
///
/// A sun/moon track with a spring-driven thumb. Tapping it writes an *explicit*
/// light or dark preference through [ThemeProvider], which also persists it, so a
/// later launch restores the user's choice rather than the system's. The
/// System option still lives in Settings → Appearance and is untouched here.
///
/// The control is one 60×34 visual inside a 44dp-tall target; the state is
/// exposed to assistive technology as a toggled switch, not as two icons.
class ThemeToggle extends StatefulWidget {
  const ThemeToggle({super.key});

  @override
  State<ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<ThemeToggle>
    with SingleTickerProviderStateMixin {
  static const double _trackWidth = 46;
  static const double _trackHeight = 28;
  static const double _thumbSize = 22;
  static const double _inset = 3;

  late final AnimationController _thumb = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  bool? _resolvedDark;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark == _resolvedDark) return;

    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final target = dark ? 1.0 : 0.0;
    _resolvedDark = dark;

    if (!_initialised || reduced) {
      _initialised = true;
      _thumb.value = target;
      return;
    }
    _thumb.animateWith(
      SpringSimulation(
        AppSpring.thumb,
        _thumb.value,
        target,
        _thumb.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  void _toggle(bool currentlyDark) {
    SoundScope.play(context, SoundEventType.buttonTap);
    context.read<ThemeProvider?>()?.setDarkMode(!currentlyDark);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = dark ? 'Switch to light theme' : 'Switch to dark theme';

    return Semantics(
      button: true,
      toggled: dark,
      label: 'Dark theme',
      value: dark ? 'On' : 'Off',
      hint: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: () => _toggle(dark),
          radius: 24,
          containedInkWell: false,
          child: SizedBox(
            width: _trackWidth,
            height: 44,
            child: Center(
              child: SizedBox(
                width: _trackWidth,
                height: _trackHeight,
                child: AnimatedBuilder(
                  animation: _thumb,
                  builder: (context, _) {
                    final t = _thumb.value.clamp(0.0, 1.0);
                    final travel = _trackWidth - _inset * 2 - _thumbSize;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                AppColors.surfaceAlt(context),
                                AppColors.isGlassPalette
                                    ? AppColors.darkSurfaceAlt
                                    : Colors.black,
                                t,
                              ),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: Color.lerp(
                                  AppColors.border(context),
                                  Colors.white.withValues(alpha: 0.16),
                                  t,
                                )!,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 7,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Icon(
                              Icons.light_mode_rounded,
                              size: 11,
                              color: dark
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : AppColors.textTertiary(context),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 7,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Icon(
                              Icons.dark_mode_rounded,
                              size: 11,
                              color: dark
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : AppColors.textTertiary(context),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _inset + travel * t,
                          top: (_trackHeight - _thumbSize) / 2,
                          width: _thumbSize,
                          height: _thumbSize,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              // The thumb has to be the brightest object in the
                              // control on a dark canvas and the darkest on a
                              // light one. A brand-tinted thumb disappeared into
                              // the tinted track on every dark palette.
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: dark
                                    ? [
                                        Colors.white,
                                        const Color(0xFFDDE4E9),
                                      ]
                                    : [
                                        AppColors.navyDeep,
                                        Color.lerp(
                                              AppColors.navyDeep,
                                              Colors.black,
                                              0.35,
                                            ) ??
                                            AppColors.navyDeep,
                                      ],
                              ),
                              border: Border.all(
                                color: dark
                                    ? Colors.black.withValues(alpha: 0.10)
                                    : Colors.white.withValues(alpha: 0.12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: dark ? 0.40 : 0.22,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              dark
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              size: 12,
                              color: dark ? AppColors.navyDeep : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
