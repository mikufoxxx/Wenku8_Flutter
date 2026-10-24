import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'app_ui.dart';
import 'performance_preferences.dart';

class GlassDockItem {
  const GlassDockItem(
    this.icon,
    this.label, {
    this.enabled = true,
    this.semanticLabel,
    this.selectableOnDrag = true,
    this.id,
    this.symbol,
    this.haptic = HapticCue.selection,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final String? semanticLabel;
  final bool selectableOnDrag;
  final Object? id;
  final ArchiveSymbol? symbol;
  final HapticCue haptic;
  Object get identity => id ?? (icon, label);
}

class _DockSlot {
  _DockSlot(this.item, this.fromWidth, this.present);
  GlassDockItem item;
  double fromWidth;
  bool present;
  double width(double progress) =>
      fromWidth + ((present ? 184 / 3 : 0) - fromWidth) * progress;
}

/// The touch preview is local to the dock: pages only change on release.
class GlassDock extends StatefulWidget {
  const GlassDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.onReselected,
    this.reduceMotion = false,
    this.animateInactiveIcons = false,
    this.items = const [
      GlassDockItem(CupertinoIcons.house, '发现'),
      GlassDockItem(CupertinoIcons.book, '书架', symbol: ArchiveSymbol.shelf),
      GlassDockItem(CupertinoIcons.settings, '设置'),
    ],
  }) : assert(items.length >= 2 && items.length <= 5);

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// A deliberate tap on the selected item, not a drag ending in its lane.
  final ValueChanged<int>? onReselected;
  final bool reduceMotion;

  /// Navigation only animates the destination. Action docks (previous/next
  /// chapter) can also animate invoked controls without selecting their lane.
  final bool animateInactiveIcons;
  final List<GlassDockItem> items;

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock> with TickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _stretch = AnimationController.unbounded(
    vsync: this,
  );
  late final _membership = AnimationController(
    vsync: this,
    duration: NovelMotion.enter,
    value: 1,
  );
  late List<_DockSlot> _slots;
  late final Listenable _motion = Listenable.merge([
    _position,
    _press,
    _stretch,
    _membership,
  ]);
  late int _targetIndex = widget.selectedIndex;
  double _segmentWidth = 1;
  double _lastX = 0;
  Duration _lastTime = Duration.zero;
  int? _pointer;
  final Map<Object, int> _iconActivations = {};
  Timer? _restTimer;
  bool _dragging = false;
  bool _reduceMotion = false;
  bool _pointerCancelled = false;

  @override
  void initState() {
    super.initState();
    _slots = [for (final item in widget.items) _DockSlot(item, 184 / 3, true)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _membership.isAnimating) _membership.value = 1;
  }

  @override
  void didUpdateWidget(GlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reduceMotion =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final membershipChanged =
        oldWidget.items.length != widget.items.length ||
        oldWidget.items.indexed.any(
          (entry) => entry.$2.identity != widget.items[entry.$1].identity,
        );
    if (membershipChanged) {
      _restTimer?.cancel();
      _pointer = null;
      _pointerCancelled = true;
      _dragging = false;
      _position.stop();
      _press.stop();
      _stretch.stop();
      _targetIndex = widget.selectedIndex;
      _position.value = widget.selectedIndex.toDouble();
      _press.value = _stretch.value = 0;
      final progress = NovelMotion.ease.transform(_membership.value);
      _slots = [
        for (final slot in _slots)
          if (slot.width(progress) > .001)
            _DockSlot(slot.item, slot.width(progress), false),
      ];
      for (var index = 0; index < widget.items.length; index++) {
        final item = widget.items[index];
        final existing = _slots.indexWhere(
          (slot) => slot.item.identity == item.identity,
        );
        if (existing >= 0) {
          _slots[existing]
            ..item = item
            ..present = true;
        } else {
          // Insert before the next surviving destination: retained controls
          // travel with the opening capsule instead of cross-fading as a row.
          final following = widget.items.skip(index + 1).map((i) => i.identity);
          final before = _slots.indexWhere(
            (slot) => following.contains(slot.item.identity),
          );
          _slots.insert(
            before < 0 ? _slots.length : before,
            _DockSlot(item, 0, true),
          );
        }
      }
      if (_reduceMotion) {
        _membership.value = 1;
      } else {
        _membership.forward(from: 0);
      }
    } else if (widget.selectedIndex != _targetIndex) {
      _settlePosition(widget.selectedIndex);
    }
    if (!membershipChanged) {
      for (final slot in _slots.where((slot) => slot.present)) {
        slot.item = widget.items.firstWhere(
          (item) => item.identity == slot.item.identity,
        );
      }
    }
    if (_reduceMotion) {
      _press.value = 0;
      _stretch.value = 0;
      _membership.value = 1;
    }
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _position.dispose();
    _press.dispose();
    _stretch.dispose();
    _membership.dispose();
    super.dispose();
  }

  double _fingerPosition(double x) =>
      (x / _segmentWidth - .5).clamp(0.0, (widget.items.length - 1).toDouble());

  Future<void> _spring(
    AnimationController controller,
    double target, {
    double velocity = 0,
  }) async {
    if (_reduceMotion) {
      controller.value = target;
      return;
    }
    try {
      await controller
          .animateWith(
            SpringSimulation(
              NovelMotion.spring,
              controller.value,
              target,
              velocity.clamp(-5.0, 5.0),
            ),
          )
          .orCancel;
      if (mounted) controller.value = target;
    } on TickerCanceled {
      // A new touch/animation owns the controller after cancellation.
    }
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointerCancelled = false;
    _pointer = event.pointer;
    _lastX = event.localPosition.dx;
    _lastTime = event.timeStamp;
    _restTimer?.cancel();
    _position.stop();
    // Pointer-down, rather than tap recognition, starts the soft response.
    if (!_reduceMotion) {
      _press.animateTo(
        1,
        duration: NovelMotion.contact,
        curve: NovelMotion.ease,
      );
    }
    _spring(_position, _fingerPosition(event.localPosition.dx));
  }

  void _release() {
    _pointer = null;
    _restTimer?.cancel();
    _spring(_press, 0);
    _spring(_stretch, 0);
  }

  void _dragStart(DragStartDetails details) {
    _dragging = true;
    _position.stop();
    _lastX = details.localPosition.dx;
    _lastTime = details.sourceTimeStamp ?? _lastTime;
    _position.value = _fingerPosition(_lastX);
  }

  void _dragUpdate(DragUpdateDetails details) {
    final time = details.sourceTimeStamp ?? _lastTime;
    final micros = (time - _lastTime).inMicroseconds;
    final speed = micros > 0
        ? (details.localPosition.dx - _lastX) * 1e6 / micros
        : details.delta.dx * 60;
    _lastX = details.localPosition.dx;
    _lastTime = time;
    final finger = _fingerPosition(details.localPosition.dx);
    // Never restart a time-based tween for every pointer event: high-rate
    // input can keep resetting it before its first frame. Follow immediately,
    // with a small spatial lag; the spring takes over only after release.
    _position.value = _reduceMotion
        ? finger
        : _position.value + (finger - _position.value) * .8;
    if (!_reduceMotion) {
      // Deform from motion, not total distance. Reversing reverses the meniscus;
      // holding still lets it relax without moving the touch preview.
      _stretch.stop();
      final target = (speed * .028).clamp(-24.0, 24.0);
      _stretch.value += (target - _stretch.value) * .55;
      _restTimer?.cancel();
      _restTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) _spring(_stretch, 0);
      });
    }
  }

  void _settlePosition(int index, {double velocity = 0}) {
    _targetIndex = index;
    _spring(_position, index.toDouble(), velocity: velocity);
  }

  void _commit(int index, {double velocity = 0, bool fromDrag = false}) {
    if (!widget.items[index].enabled ||
        (fromDrag && !widget.items[index].selectableOnDrag)) {
      _cancel();
      return;
    }
    _dragging = false;
    AppHaptics.play(context, widget.items[index].haptic);
    setState(() {
      final identity = widget.items[index].identity;
      _iconActivations[identity] = (_iconActivations[identity] ?? 0) + 1;
    });
    _release();
    _settlePosition(index, velocity: velocity);
    if (!fromDrag &&
        index == widget.selectedIndex &&
        widget.onReselected != null) {
      widget.onReselected!(index);
    } else {
      widget.onSelected(index);
    }
  }

  void _dragEnd(DragEndDetails details) {
    if (_pointerCancelled) {
      _cancel();
      return;
    }
    final velocity = (details.primaryVelocity ?? 0) / _segmentWidth;
    final projected =
        _fingerPosition(_lastX) + (velocity * .055).clamp(-.22, .22);
    _commit(
      projected.round().clamp(0, widget.items.length - 1),
      velocity: velocity,
      fromDrag: true,
    );
  }

  void _cancel() {
    if (!mounted) return;
    _dragging = false;
    _release();
    _settlePosition(widget.selectedIndex);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (context, child) {
      final progress = NovelMotion.ease.transform(_membership.value);
      final width = _membership.isCompleted
          ? widget.items.length * (184 / 3) + 12
          : _slots.fold<double>(12, (sum, slot) => sum + slot.width(progress));
      final pressure = _reduceMotion ? 0.0 : _press.value.clamp(0.0, 1.0);
      final flow = _reduceMotion ? 0.0 : _stretch.value;
      return SizedBox(
        height: 54,
        width: width,
        child: Transform.translate(
          offset: Offset(flow * .16, -pressure * .6),
          child: Transform.scale(
            key: const ValueKey('dock-whole-capsule-transform'),
            scaleX: 1 + pressure * .022 + flow.abs() * .00125,
            scaleY: 1 + pressure * .065 - flow.abs() * .0006,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: LiquidGlass(
                      key: const ValueKey('dock-fluid-surface'),
                      radius: 27,
                      thickness: 16 + pressure * 2,
                      activation: pressure,
                      touchPosition:
                          (_position.value.clamp(
                                0.0,
                                (widget.items.length - 1).toDouble(),
                              ) +
                              .5) /
                          widget.items.length,
                      elevated: false,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GlassForeground(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _segmentWidth =
                              constraints.maxWidth / widget.items.length;
                          return IgnorePointer(
                            ignoring: _membership.isAnimating,
                            child: Listener(
                              onPointerDown: _down,
                              onPointerUp: (event) {
                                if (event.pointer == _pointer) _release();
                              },
                              onPointerCancel: (event) {
                                if (event.pointer == _pointer) {
                                  _pointerCancelled = true;
                                  _cancel();
                                }
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) {
                                  if (!_dragging && !_pointerCancelled) {
                                    _commit(
                                      _fingerPosition(details.localPosition.dx)
                                          .round()
                                          .clamp(0, widget.items.length - 1),
                                    );
                                  }
                                },
                                onHorizontalDragStart: _dragStart,
                                onHorizontalDragUpdate: _dragUpdate,
                                onHorizontalDragEnd: _dragEnd,
                                onHorizontalDragCancel: _cancel,
                                child: _foreground(progress),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _foreground(double progress) {
    var left = 0.0;
    final children = <Widget>[];
    for (final slot in _slots) {
      final width = slot.width(progress);
      if (width <= .001) continue;
      children.add(
        Positioned(
          key: ValueKey(slot.item.identity),
          left: left,
          top: 0,
          bottom: 0,
          width: width,
          child: ClipRect(
            clipBehavior: width >= 184 / 3 - .001 ? Clip.none : Clip.hardEdge,
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: 184 / 3,
              maxWidth: 184 / 3,
              child: ExcludeSemantics(
                excluding: !slot.present,
                child: _nav(
                  widget.items.indexWhere(
                    (item) => item.identity == slot.item.identity,
                  ),
                  slot.item,
                ),
              ),
            ),
          ),
        ),
      );
      left += width;
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _nav(int index, GlassDockItem item) {
    final proximity = (1 - (_position.value - index).abs()).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    final color = !item.enabled && index != widget.selectedIndex
        ? scheme.onSurfaceVariant.withValues(alpha: .4)
        : Color.lerp(scheme.onSurfaceVariant, scheme.primary, proximity);
    return SizedBox(
      width: 184 / 3,
      child: Semantics(
        key: ValueKey(
          index < 0 ? 'dock-outgoing-${item.identity}' : 'dock-tab-$index',
        ),
        button: item.enabled,
        enabled: item.enabled,
        selected: widget.selectedIndex == index,
        label: item.semanticLabel ?? item.label,
        onTap: item.enabled && index >= 0 ? () => _commit(index) : null,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (proximity > .04)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 3,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(
                            alpha: .09 * proximity,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArchiveIconContact(
                      pressed:
                          _pointer != null &&
                          index >= 0 &&
                          item.enabled &&
                          _fingerPosition(_lastX).round() == index,
                      activation: _iconActivations[item.identity] ?? 0,
                      child: ArchiveIcon(
                        item.icon,
                        symbol: item.symbol,
                        size: 20,
                        color: color,
                        active: widget.selectedIndex == index,
                        animate:
                            !widget.reduceMotion &&
                            !PerformanceScope.reduceMotionOf(context) &&
                            (widget.animateInactiveIcons ||
                                widget.selectedIndex == index),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AppText(
                          item.label,
                          maxLines: 1,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: widget.selectedIndex == index
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 16,
                        height: 2,
                        child: ColoredBox(
                          color: scheme.primary.withValues(alpha: proximity),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
