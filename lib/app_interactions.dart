import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'app_ui.dart';

final _routeSlots = Expando<Set<Object>>('novel-route-slots');
final _explorationOwners = Expando<_ExplorationHistory>('novel-exploration');

class _ExplorationHistory {
  final routes = <({Object key, PageRoute<dynamic> route})>[];
}

final _feedbackEntries = Expando<_FeedbackEntry>('novel-feedback');
final _feedbackHeaders = Expando<ValueListenable<double>>(
  'novel-feedback-header',
);

class _FeedbackEntry {
  _FeedbackEntry(this.close, this.route);
  final VoidCallback close;
  final ModalRoute<dynamic>? route;
}

/// Bind only while the reader route owns this animation. Overlays must release
/// it before the reader disposes its controller.
VoidCallback bindNovelFeedbackHeader(
  BuildContext context,
  ValueListenable<double> visibility,
) {
  final route = ModalRoute.of(context);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (route == null) return () {};
  _feedbackHeaders[route] = visibility;
  return () {
    if (identical(_feedbackHeaders[route], visibility)) {
      _feedbackHeaders[route] = null;
    }
    final notice = overlay == null ? null : _feedbackEntries[overlay];
    if (notice?.route == route) notice?.close();
  };
}

void dismissNovelFeedback(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) _feedbackEntries[overlay]?.close();
}

/// Coalesce from the originating route, not every page in its Navigator.
/// Related-book exploration retains at most four routes and reuses identities;
/// reader/settings flows keep their normal Back contract in separate chains.
Future<T?> pushNovelPage<T>(
  BuildContext context,
  Widget page, {
  required bool reduceMotion,
  Object? slot,
  bool paperFlight = false,
  Object? explorationKey,
}) async {
  if (!context.mounted) return null;
  final navigator = Navigator.of(context);
  final origin = ModalRoute.of(context);
  final history = explorationKey == null
      ? null
      : (origin == null ? null : _explorationOwners[origin]) ??
            _ExplorationHistory();
  if (history != null) {
    history.routes.removeWhere((entry) => !entry.route.isActive);
    for (final entry in history.routes) {
      if (entry.key == explorationKey) {
        dismissNovelFeedback(context);
        navigator.popUntil((route) => identical(route, entry.route));
        return null;
      }
    }
  }
  final slots = _routeSlots[origin ?? navigator] ??= <Object>{};
  final key = slot ?? page.runtimeType;
  if (!slots.add(key)) return null;
  final route = softRoute<T>(
    page,
    reduceMotion: reduceMotion || MediaQuery.disableAnimationsOf(context),
    paperFlight: paperFlight,
  );
  if (history != null) {
    history.routes.add((key: explorationKey!, route: route));
    _explorationOwners[route] = history;
  }
  void trimHistory(AnimationStatus status) {
    if (status != AnimationStatus.completed || history == null) return;
    route.animation?.removeStatusListener(trimHistory);
    // The old cover/source must survive the complete incoming Hero flight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted || !route.isActive) return;
      while (history.routes.length > 4) {
        final oldest = history.routes.removeAt(0).route;
        if (oldest.isActive && !oldest.isCurrent) navigator.removeRoute(oldest);
      }
    });
  }

  try {
    // Android back may hide the IME while its EditableText stays focused.
    // Clear that scope's focus history before the route can restore it on pop.
    FocusManager.instance.primaryFocus?.unfocus();
    dismissNovelFeedback(context);
    final resultFuture = navigator.push(route);
    route.animation?.addStatusListener(trimHistory);
    if (route.animation?.status == AnimationStatus.completed) {
      trimHistory(AnimationStatus.completed);
    }
    final result = await resultFuture;
    await route.completed;
    return result;
  } finally {
    slots.remove(key);
    route.animation?.removeStatusListener(trimHistory);
    history?.routes.removeWhere((entry) => identical(entry.route, route));
    _explorationOwners[route] = null;
  }
}

/// A single app-wide glass notice, below the header rather than over the Dock.
/// The root overlay keeps feedback from a sheet visible above that sheet too.
VoidCallback? showNovelFeedback(
  BuildContext context,
  String message, {
  String? actionLabel,
  FutureOr<void> Function()? action,
  String actionFailure = '操作保存失败，请重试',
  ValueListenable<double>? headerVisibility,
  Duration? duration,
  HapticCue? haptic,
}) {
  if (!context.mounted) return null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  AppHaptics.play(context, haptic);
  _feedbackEntries[overlay]?.close();
  final sourceRoute = ModalRoute.of(context);
  final header =
      headerVisibility ??
      (sourceRoute == null ? null : _feedbackHeaders[sourceRoute]);
  final themes = InheritedTheme.capture(from: context, to: overlay.context);
  final appearance = GlassAppearance.of(context);
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
    entry.dispose();
    if (identical(_feedbackEntries[overlay]?.close, remove)) {
      _feedbackEntries[overlay] = null;
    }
  }

  entry = OverlayEntry(
    builder: (_) => themes.wrap(
      GlassAppearance(
        blur: appearance.blur,
        opacity: appearance.opacity,
        child: NovelFeedbackNotice(
          message: message,
          duration: duration,
          headerVisibility: header,
          actionLabel: actionLabel,
          onAction: action == null || actionLabel == null
              ? null
              : () async {
                  remove();
                  try {
                    await action();
                  } catch (_) {
                    if (context.mounted) {
                      showNovelFeedback(
                        context,
                        actionFailure,
                        haptic: HapticCue.error,
                      );
                    }
                  }
                },
          onDismiss: remove,
        ),
      ),
    ),
  );
  _feedbackEntries[overlay] = _FeedbackEntry(remove, sourceRoute);
  overlay.insert(entry);
  return remove;
}

class NovelFeedbackNotice extends StatefulWidget {
  const NovelFeedbackNotice({
    super.key,
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    this.headerVisibility,
    this.duration,
  });
  final String message;
  final String? actionLabel;
  final VoidCallback onDismiss;
  final Future<void> Function()? onAction;
  final ValueListenable<double>? headerVisibility;
  final Duration? duration;
  @override
  State<NovelFeedbackNotice> createState() => _NovelFeedbackNoticeState();
}

class _NovelFeedbackNoticeState extends State<NovelFeedbackNotice>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: NovelMotion.enter,
    reverseDuration: NovelMotion.contact,
  );
  Timer? _timer;
  bool _started = false, _closing = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
    } else {
      _motion.forward();
    }
    // Notices are transient even with a screen reader. Give long copy and
    // actions more reading time, but never require a separate close control.
    final milliseconds =
        widget.duration?.inMilliseconds ??
        (widget.onAction == null ? 2500 : 4000);
    _timer = Timer(
      Duration(
        milliseconds: MediaQuery.accessibleNavigationOf(context)
            ? math.max(10000, milliseconds)
            : milliseconds,
      ),
      _close,
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _motion.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.headerVisibility;
    return header == null
        ? _positioned(1)
        : ValueListenableBuilder<double>(
            valueListenable: header,
            builder: (context, value, _) => _positioned(value),
          );
  }

  Widget _positioned(double visibility) {
    final media = MediaQuery.of(context);
    final headerProgress = NovelMotion.ease.transform(visibility.clamp(0, 1));
    // Sit above the floating Dock (54 + 22) with a 12 dp gap. Reader chrome
    // reports its own visibility so the notice clears the taller tool bar.
    final bottom = math.max(
      media.viewInsets.bottom + 16,
      media.viewPadding.bottom + 22 + 54 + 12 + 72 * headerProgress,
    );
    return Positioned(
      bottom: bottom,
      left: media.viewPadding.left + 16,
      right: media.viewPadding.right + 16,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: (media.size.height - bottom - media.viewPadding.top)
                .clamp(0, double.infinity),
          ),
          child: AnimatedBuilder(
            animation: _motion,
            child: Semantics(
              liveRegion: true,
              container: true,
              child: LiquidGlass(
                key: const ValueKey('novel-feedback-surface'),
                radius: 24,
                elevated: false,
                blur: GlassAppearance.of(context).blur,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: AppText(
                          widget.message,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (widget.onAction != null && widget.actionLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GlassTextButton(
                          dense: true,
                          filled: true,
                          onPressed: widget.onAction,
                          child: AppText(widget.actionLabel!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            builder: (context, child) {
              final value = NovelMotion.ease.transform(_motion.value);
              // Reveal the actual glass rather than isolating its live backdrop
              // in a fractional-opacity layer.
              return ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: value,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - value)),
                    child: child,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
