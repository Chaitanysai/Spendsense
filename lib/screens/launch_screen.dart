import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_logo.dart';

/// A short, branded launch moment shown while the local ledger opens.
///
/// The app is local-first: the first screen is composed from encrypted records
/// on disk. Until that read completes Home would be an empty shell showing ₹0.
/// This gate holds a dark, animated mark on screen for at least
/// [minimumDuration] and until [TransactionProvider.ready] settles, then fades
/// into the real app.
///
/// It is release-only by default. Widget tests run in debug and therefore keep
/// the direct path to the screen they are testing; [forceShow] exists for the
/// launch-screen test.
class AppLaunchGate extends StatefulWidget {
  final Widget child;
  final bool? forceShow;
  final Duration minimumDuration;

  const AppLaunchGate({
    super.key,
    required this.child,
    this.forceShow,
    this.minimumDuration = const Duration(milliseconds: 1400),
  });

  @override
  State<AppLaunchGate> createState() => _AppLaunchGateState();
}

class _AppLaunchGateState extends State<AppLaunchGate> {
  bool _started = false;
  bool _ready = false;

  bool get _enabled => widget.forceShow ?? kReleaseMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled || _started) return;
    _started = true;
    unawaited(_hold());
  }

  Future<void> _hold() async {
    final started = DateTime.now();

    TransactionProvider? transactions;
    try {
      transactions = context.read<TransactionProvider>();
    } catch (_) {
      // Embedded previews may not publish the provider; fall through to the
      // minimum hold rather than trapping the gate.
    }

    try {
      await transactions?.ready.timeout(const Duration(seconds: 8));
    } catch (_) {
      // A failed ledger still opens the app; Home renders its error state.
    }

    final elapsed = DateTime.now().difference(started);
    final remaining = widget.minimumDuration - elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: AppMotion.emphasized,
      switchOutCurve: AppMotion.emphasized,
      child: _ready
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : const SpendSenseLaunchScreen(key: ValueKey('launch')),
    );
  }
}

/// The visual half of the launch gate. Kept public so it can be rendered
/// directly in a widget test and in the device preview.
class SpendSenseLaunchScreen extends StatefulWidget {
  const SpendSenseLaunchScreen({super.key});

  @override
  State<SpendSenseLaunchScreen> createState() => _SpendSenseLaunchScreenState();
}

class _SpendSenseLaunchScreenState extends State<SpendSenseLaunchScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _entrance,
    curve: AppMotion.emphasized,
  );
  late final Animation<double> _lift = Tween<double>(
    begin: 14,
    end: 0,
  ).animate(CurvedAnimation(parent: _entrance, curve: AppMotion.emphasized));

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (reduced == _reduced && _entrance.isAnimating) return;
    _reduced = reduced;
    if (reduced) {
      _entrance.value = 1;
      _spin.stop();
      _spin.value = 0.18;
    } else {
      _entrance.forward();
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The launch canvas follows the selected palette instead of a fixed navy.
    //
    // It used to paint Premium Blue's ramp literally (#021024 → #052659 →
    // #0A3468), so a user on Paper, Plum, or any of the new themes got a navy
    // flash before their own world appeared — the one screen that ignored the
    // theme. The stops below are the palette's own deep → brand → bright ramp,
    // pushed dark enough that the white wordmark keeps its 4.5:1 on every stop
    // (the same `_holdWhite` idea the hero gradients use).
    final deep = _holdWhite(AppColors.darkBackground);
    final mid =
        _holdWhite(Color.lerp(AppColors.navyDeep, AppColors.azure, 0.30)!);
    final light =
        _holdWhite(Color.lerp(AppColors.brand, AppColors.navyDeep, 0.55)!);
    final glow = AppColors.brandBright;

    return Scaffold(
      backgroundColor: deep,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deep, mid, light],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -140,
              left: -80,
              child: _Glow(color: glow, size: 380),
            ),
            Positioned(
              bottom: -160,
              right: -100,
              child: _Glow(color: AppColors.cyan, size: 340),
            ),
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: AnimatedBuilder(
                    animation: _lift,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _lift.value),
                      child: child,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 168,
                          height: 168,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _spin,
                                builder: (context, _) => Transform.rotate(
                                  angle: _spin.value * math.pi * 2,
                                  child: CustomPaint(
                                    size: const Size.square(168),
                                    painter: _LaunchRingPainter(
                                      arcColors: [
                                        deep.withValues(alpha: 0),
                                        light,
                                        AppColors.brandBright,
                                      ],
                                      dotColor: light,
                                    ),
                                  ),
                                ),
                              ),
                              const AppLogo(size: 66),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'SpendSense',
                          style: AppText.weight(
                                  AppText.display(context), FontWeight.w800)
                              .copyWith(
                            color: Colors.white,
                            fontSize: 30,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'SMART MONEY COPILOT',
                          style: AppText.overline(context).copyWith(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 9.5,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 42,
              child: FadeTransition(
                opacity: _fade,
                child: Center(
                  child: Text(
                    'LOCAL-FIRST · PRIVATE BY DEFAULT',
                    style: AppText.overline(context).copyWith(
                      // 0.38 white measured ~3.4:1 on the old navy and falls
                      // under 3:1 on brighter palettes. 0.62 holds the 3:1
                      // large-text bar on every palette's held-dark canvas
                      // while staying visually quiet.
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 8.5,
                      letterSpacing: 1.8,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchRingPainter extends CustomPainter {
  /// Ring colours read the active palette, so the launch ring is lit by the
  /// user's own world rather than a fixed ice-blue brand ramp. Held opaque
  /// enough to stay visible on the palette's darkest canvas stop.
  const _LaunchRingPainter({
    required this.arcColors,
    required this.dotColor,
  });

  final List<Color> arcColors;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: arcColors,
        stops: const [0.0, 0.65, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.25,
      false,
      arc,
    );

    final dot = Offset(
      center.dx + math.cos(-math.pi / 2 + math.pi * 1.25) * radius,
      center.dy + math.sin(-math.pi / 2 + math.pi * 1.25) * radius,
    );
    canvas.drawCircle(
      dot,
      3.4,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(covariant _LaunchRingPainter oldDelegate) =>
      oldDelegate.arcColors != arcColors || oldDelegate.dotColor != dotColor;
}

/// [c] darkened toward black only as far as white text on it reaches 4.5:1.
///
/// The launch canvas must stay legible for the white wordmark whichever palette
/// is active — a bright brand stop (Orange + milk, Warm Amber) would otherwise
/// put white text under the AA bar.
Color _holdWhite(Color c) {
  if (AppColors.contrastRatio(Colors.white, c) >= 4.5) return c;
  for (var t = 0.05; t < 1.0; t += 0.05) {
    final candidate = Color.lerp(c, Colors.black, t) ?? c;
    if (AppColors.contrastRatio(Colors.white, candidate) >= 4.5) {
      return candidate;
    }
  }
  return Colors.black;
}
