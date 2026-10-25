import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Broadcasts "this page has just been entered" to every animation in one
/// page subtree.
///
/// A route that is popped back to, or a bottom-navigation tab that is selected
/// again, is **not** rebuilt from scratch: its State (and therefore every
/// `initState`-driven entrance animation) survives. Instead of remounting the
/// page, the owner calls [replay] and every [PageEntrance],
/// [AnimatedProgressBar] and animated amount in the subtree restarts from its
/// initial visual state.
///
/// [generation] is monotonic so widgets can distinguish a genuine page-entry
/// from an unrelated parent rebuild. Rebuilding without a new generation must
/// leave completed animations untouched.
class PageEntryController extends ChangeNotifier {
  int _generation = 0;
  bool _disposed = false;

  /// Increments on every page entry. Starts at zero for the first build.
  int get generation => _generation;

  /// Signals a new page entry. Safe to call from a post-frame callback; a
  /// controller disposed in the meantime simply ignores the call.
  void replay() {
    if (_disposed) return;
    _generation++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Makes the nearest [PageEntryController] available to a page subtree.
class PageEntryScope extends InheritedNotifier<PageEntryController> {
  const PageEntryScope({
    super.key,
    required PageEntryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Subscribes the caller to page-entry generations.
  static PageEntryController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageEntryScope>()?.notifier;
}

/// Observer that tells a page it has been revealed again after a pushed route
/// was popped. Registered once on the app's navigator.
class PageEntryRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  PageEntryRouteObserver._();

  static final PageEntryRouteObserver instance = PageEntryRouteObserver._();
}

/// Owns the page-entry lifecycle for one page and publishes it to descendants.
///
/// It does not rebuild or remount the page. It only bumps a generation:
/// * on the first build (descendants animate themselves from zero);
/// * when a retained tab becomes [active] again;
/// * when a pushed page route above this one is popped (`didPopNext`).
///
/// Replays are scheduled after the current frame. That keeps the notification
/// out of Flutter's build phase and, on a tab switch, happens while the tab
/// cross-fade is still at zero opacity, so the reset is never visible as a
/// flash of the finished layout.
class PageEntryHost extends StatefulWidget {
  final Widget child;

  /// False for an off-screen retained tab. A tab only replays when it is
  /// actually visible, so background tabs never animate unseen.
  final bool active;

  /// Optional externally owned controller (used by tests and hosts that need
  /// to trigger a replay imperatively). When omitted the host owns one.
  final PageEntryController? controller;

  /// Set false when a host is used outside a navigator (or when route-return
  /// replay is not wanted). First-entry and tab replay still work.
  final bool replayOnRouteReturn;

  const PageEntryHost({
    super.key,
    required this.child,
    this.active = true,
    this.controller,
    this.replayOnRouteReturn = true,
  });

  @override
  State<PageEntryHost> createState() => _PageEntryHostState();
}

class _PageEntryHostState extends State<PageEntryHost> with RouteAware {
  PageEntryController? _owned;
  ModalRoute<dynamic>? _subscribedRoute;
  bool _replayScheduled = false;

  PageEntryController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _owned = PageEntryController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachRoute();
  }

  void _attachRoute() {
    if (!widget.replayOnRouteReturn) {
      if (_subscribedRoute != null) {
        PageEntryRouteObserver.instance.unsubscribe(this);
        _subscribedRoute = null;
      }
      return;
    }
    final route = ModalRoute.of(context);
    if (identical(route, _subscribedRoute)) return;
    if (_subscribedRoute != null) {
      PageEntryRouteObserver.instance.unsubscribe(this);
    }
    _subscribedRoute = route;
    if (route is PageRoute<dynamic>) {
      PageEntryRouteObserver.instance.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant PageEntryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _owned?.dispose();
        _owned = null;
      }
      if (widget.controller == null) _owned = PageEntryController();
    }
    if (!oldWidget.active && widget.active) _scheduleReplay();
    if (widget.replayOnRouteReturn != oldWidget.replayOnRouteReturn) {
      _attachRoute();
    }
  }

  @override
  void didPopNext() => _scheduleReplay();

  void _scheduleReplay() {
    if (_replayScheduled) return;
    _replayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _replayScheduled = false;
      if (!mounted || !widget.active) return;
      _controller.replay();
    });
  }

  @override
  void dispose() {
    if (_subscribedRoute != null) {
      PageEntryRouteObserver.instance.unsubscribe(this);
    }
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageEntryScope(
      controller: _controller,
      child: PageEntrance(child: widget.child),
    );
  }
}

/// Fade + restrained upward glide that replays on every page entry.
///
/// Place it once at the page level, or with [index] for a staggered card/row.
/// Without an enclosing [PageEntryHost] it still plays its first-entry
/// animation; there is simply no later replay signal to listen to.
class PageEntrance extends StatefulWidget {
  final Widget child;
  final double offset;
  final Duration duration;
  final Curve curve;

  /// Position in a list. Used for a subtle, bounded stagger (40 ms per item,
  /// capped at six steps so a long list never delays its last row for seconds).
  final int? index;

  /// Explicit delay override. Takes precedence over [index].
  final Duration? delay;

  const PageEntrance({
    super.key,
    required this.child,
    this.offset = 0.03,
    this.duration = AppMotion.slow,
    this.curve = AppMotion.emphasized,
    this.index,
    this.delay,
  });

  @override
  State<PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<PageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late Animation<double> _curved =
      CurvedAnimation(parent: _controller, curve: widget.curve);
  Timer? _delayTimer;
  int? _generation;
  bool _initialised = false;
  bool _reduced = false;

  Duration get _staggerDelay {
    final explicit = widget.delay;
    if (explicit != null) return explicit;
    final index = widget.index;
    if (index == null || index <= 0) return Duration.zero;
    return Duration(milliseconds: 40 * (index > 6 ? 6 : index));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final generation = PageEntryScope.maybeOf(context)?.generation;
    final reducedChanged = reduced != _reduced;
    _reduced = reduced;

    if (!_initialised) {
      _initialised = true;
      _generation = generation;
      _play();
      return;
    }

    if (generation != null && generation != _generation) {
      _generation = generation;
      _play();
      return;
    }

    if (reducedChanged && reduced) _settle();
  }

  @override
  void didUpdateWidget(covariant PageEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve) {
      _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    }
  }

  void _play() {
    _delayTimer?.cancel();
    _delayTimer = null;
    if (_reduced || widget.duration == Duration.zero) {
      _settle();
      return;
    }
    _controller.stop();
    _controller.value = 0;
    final delay = _staggerDelay;
    if (delay <= Duration.zero) {
      _controller.forward();
      return;
    }
    _delayTimer = Timer(delay, () {
      if (!mounted) return;
      _delayTimer = null;
      _controller.forward();
    });
  }

  void _settle() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _controller.value = 1;
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion inserts no transition layer at all, matching the rest of
    // the app (and keeping the settled page on the cheap direct-paint path).
    if (_reduced) return widget.child;

    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.offset),
          end: Offset.zero,
        ).animate(_curved),
        child: widget.child,
      ),
    );
  }
}
