import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as easy;
import 'app_haptics.dart';

/// App adapters add controlled values, disabled states and accessibility to the
/// package's own glass controls; the package still owns touch and lens motion.
class AppGlassSwitch extends StatefulWidget {
  const AppGlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.style,
    required this.reduceMotion,
    this.haptics = true,
  });
  final bool value, reduceMotion, haptics;
  final FutureOr<void> Function(bool)? onChanged;
  final Color activeColor, inactiveColor, thumbColor;
  final easy.LiquidGlassStyle style;
  @override
  State<AppGlassSwitch> createState() => _AppGlassSwitchState();
}

class _AppGlassSwitchState extends State<AppGlassSwitch> {
  bool? _pending;
  int _request = 0;
  bool get _value => _pending ?? widget.value;
  Future<void> _change(bool value) async {
    final action = widget.onChanged;
    if (action == null || value == _value) return;
    if (widget.haptics) AppHaptics.play(context, HapticCue.selection);
    final request = ++_request;
    setState(() => _pending = value);
    try {
      await action(value);
    } finally {
      if (mounted && request == _request) setState(() => _pending = null);
    }
  }

  void _released(PointerEvent _) {
    // A cancelled save can finish while the package still lets the finger own
    // the thumb. Reconcile the controlled value after it releases that ownership.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return Semantics(
      toggled: _value,
      enabled: enabled,
      onTap: enabled ? () => _change(!_value) : null,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (enabled) _change(!_value);
          },
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (enabled) _change(!_value);
          },
        },
        child: Focus(
          canRequestFocus: enabled,
          child: IgnorePointer(
            ignoring: !enabled,
            child: ExcludeSemantics(
              child: Listener(
                onPointerUp: _released,
                onPointerCancel: _released,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: easy.LiquidGlassSwitch(
                    value: _value,
                    enableHaptics: false,
                    horizontalDragOnly: true,
                    onChanged: _change,
                    activeColor: enabled
                        ? widget.activeColor
                        : widget.activeColor.withValues(alpha: .4),
                    inactiveColor: enabled
                        ? widget.inactiveColor
                        : widget.inactiveColor.withValues(alpha: .5),
                    thumbColor: enabled
                        ? widget.thumbColor
                        : widget.thumbColor.withValues(alpha: .55),
                    style: widget.style,
                    layout: const easy.LiquidGlassSwitchLayout().scaled(.9),
                    reserveSwellRoom: true,
                    reduceMotion: widget.reduceMotion,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassSlider extends StatefulWidget {
  const AppGlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.haptics = true,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.style,
    required this.reduceMotion,
  });
  final double value, min, max;
  final int? divisions;
  final bool haptics;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final Color activeColor, inactiveColor, thumbColor;
  final easy.LiquidGlassStyle style;
  final bool reduceMotion;
  @override
  State<AppGlassSlider> createState() => _AppGlassSliderState();
}

class _AppGlassSliderState extends State<AppGlassSlider> {
  late double _draft = widget.value;
  bool _dragging = false;
  bool _changedInGesture = false;
  double _quantize(double value) {
    final span = widget.max - widget.min;
    final steps = widget.divisions;
    if (steps != null && steps > 0 && span > 0) {
      value =
          widget.min +
          ((value - widget.min) / span * steps).round() / steps * span;
    }
    return value.clamp(widget.min, widget.max);
  }

  void _change(double value) {
    final next = _quantize(value);
    if (next == _draft) return;
    final span = widget.max - widget.min;
    final steps = widget.divisions ?? 20;
    if (widget.haptics && span > 0) {
      final previousTick = ((_draft - widget.min) / span * steps).round();
      final nextTick = ((next - widget.min) / span * steps).round();
      if (next == widget.min || next == widget.max) {
        AppHaptics.play(context, HapticCue.boundary);
      } else if (!_changedInGesture || nextTick != previousTick) {
        AppHaptics.play(context, HapticCue.detent);
      }
    }
    _changedInGesture = true;
    setState(() => _draft = next);
    widget.onChanged?.call(next);
  }

  void _start(double _) {
    _dragging = true;
    _changedInGesture = false;
    widget.onChangeStart?.call(_draft);
  }

  void _end(double value) {
    final next = _quantize(value);
    _change(next);
    setState(() => _dragging = false);
    widget.onChangeEnd?.call(next);
  }

  void _adjust(double direction) {
    if (widget.onChanged == null) return;
    _start(_draft);
    _change(_adjusted(direction));
    _end(_draft);
  }

  double _adjusted(double direction) => _quantize(
    _draft + (widget.max - widget.min) / (widget.divisions ?? 20) * direction,
  );

  @override
  void didUpdateWidget(AppGlassSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) _draft = _quantize(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final span = widget.max - widget.min;
    String percent(double value) =>
        '${(span > 0 ? (value - widget.min) / span * 100 : 0).round()}%';
    return Semantics(
      slider: true,
      enabled: enabled,
      value: percent(_draft),
      increasedValue: enabled && _draft < widget.max
          ? percent(_adjusted(1))
          : null,
      decreasedValue: enabled && _draft > widget.min
          ? percent(_adjusted(-1))
          : null,
      onIncrease: enabled && _draft < widget.max ? () => _adjust(1) : null,
      onDecrease: enabled && _draft > widget.min ? () => _adjust(-1) : null,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _adjust(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _adjust(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _adjust(-1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _adjust(-1),
        },
        child: Focus(
          canRequestFocus: enabled,
          child: IgnorePointer(
            ignoring: !enabled,
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) => easy.LiquidGlassSlider(
                  value: _draft,
                  enableHaptics: false,
                  horizontalDragOnly: true,
                  minimumValue: widget.min,
                  maximumValue: widget.max,
                  onChanged: _change,
                  onChangeStart: _start,
                  onChangeEnd: _end,
                  width: constraints.maxWidth,
                  height: 52,
                  minimumTouchHeight: 48,
                  activeColor: enabled
                      ? widget.activeColor
                      : widget.activeColor.withValues(alpha: .4),
                  inactiveColor: widget.inactiveColor,
                  thumbColor: enabled
                      ? widget.thumbColor
                      : widget.thumbColor.withValues(alpha: .55),
                  style: widget.style,
                  reduceMotion: widget.reduceMotion,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassSegments<T extends Object> extends StatelessWidget {
  const AppGlassSegments({
    super.key,
    required this.groupValue,
    required this.children,
    required this.onValueChanged,
    required this.style,
    required this.pillStyle,
    required this.foregroundColor,
    this.selectedForegroundColor,
    this.disabledChildren = const {},
    this.haptics = true,
  });
  final T? groupValue;
  final bool haptics;
  final Map<T, Widget> children;
  final ValueChanged<T?> onValueChanged;
  final Set<T> disabledChildren;
  final easy.LiquidGlassStyle style;
  final easy.LiquidGlassSegmentedPillStyle pillStyle;
  final Color foregroundColor;
  final Color? selectedForegroundColor;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final keys = children.keys.toList();
      final labels = [
        for (final child in children.values)
          child is Text ? child.data ?? '' : '',
      ];
      final textOnly = children.values.every((child) => child is Text);
      final selectedColor = selectedForegroundColor ?? foregroundColor;
      final textStyle = DefaultTextStyle.of(
        context,
      ).style.copyWith(fontSize: 14, height: 1.4, color: foregroundColor);
      // Reserve the package pill's complete bulge, including two-item selectors.
      final growth = pillStyle.growHeight;
      final gutter = math
          .max(
            4.0,
            (growth * (constraints.maxWidth - 8) / (2 * keys.length * 40) - 4) /
                (1 + growth / (keys.length * 40)),
          )
          .ceilToDouble();
      final width = math.max(1.0, constraints.maxWidth - gutter * 2);
      final cellWidth = math.max(1.0, (width - 8) / keys.length);
      var height = 48.0;
      for (final label in labels) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout(maxWidth: cellWidth);
        height = math.max(height, painter.height + 12);
        painter.dispose();
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
        child: easy.LiquidGlassSegmented(
          segments: labels,
          selectedIndex: math.max(
            0,
            keys.indexWhere((key) => key == groupValue),
          ),
          disabledIndices: {
            for (var index = 0; index < keys.length; index++)
              if (disabledChildren.contains(keys[index])) index,
          },
          onChanged: (index) {
            if (!disabledChildren.contains(keys[index])) {
              if (haptics && keys[index] != groupValue) {
                AppHaptics.play(context, HapticCue.selection);
              }
              onValueChanged(keys[index]);
            }
          },
          width: width,
          height: height,
          style: style,
          pillStyle: pillStyle,
          labelStyle: easy.LiquidGlassSegmentedLabelStyle(
            selectedColor: selectedColor,
            unselectedColor: foregroundColor,
            fontSize: 14,
            selectedFontWeight: FontWeight.w700,
          ),
          segmentBuilder: textOnly
              ? null
              : (context, index, selected, color) => IconTheme(
                  data: IconThemeData(
                    color: selected ? selectedColor : foregroundColor,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: selected ? selectedColor : foregroundColor,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: children[keys[index]]!,
                  ),
                ),
        ),
      );
    },
  );
}
