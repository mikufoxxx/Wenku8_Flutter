import 'package:flutter/material.dart';

/// A two-dimensional saturation/value palette with a separate hue strip.
class BackgroundColorPalette extends StatelessWidget {
  const BackgroundColorPalette({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final HSVColor value;
  final ValueChanged<HSVColor>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('调色盘'),
      const SizedBox(height: 8),
      const Text('在色板上点选或拖动，下方彩虹条切换色相。'),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          const height = 200.0;
          final width = constraints.maxWidth;
          void select(Offset position) {
            onChanged?.call(
              value
                  .withSaturation((position.dx / width).clamp(0.0, 1.0))
                  .withValue((1 - position.dy / height).clamp(0.0, 1.0)),
            );
          }

          return Semantics(
            label: '颜色调色盘',
            child: GestureDetector(
              key: const ValueKey('home-color-palette'),
              behavior: HitTestBehavior.opaque,
              onTapDown: onChanged == null
                  ? null
                  : (details) => select(details.localPosition),
              onPanStart: onChanged == null
                  ? null
                  : (details) => select(details.localPosition),
              onPanUpdate: onChanged == null
                  ? null
                  : (details) => select(details.localPosition),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: height,
                  width: width,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white,
                              HSVColor.fromAHSV(1, value.hue, 1, 1).toColor(),
                            ],
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (value.saturation * width - 10).clamp(
                          0.0,
                          width - 20,
                        ),
                        top: ((1 - value.value) * height - 10).clamp(
                          0.0,
                          height - 20,
                        ),
                        child: IgnorePointer(
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: value.toColor(),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [
                  Colors.red,
                  Color(0xffffff00),
                  Color(0xff00ff00),
                  Color(0xff00ffff),
                  Colors.blue,
                  Color(0xffff00ff),
                  Colors.red,
                ],
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: HSVColor.fromAHSV(1, value.hue, 1, 1).toColor(),
              trackHeight: 16,
            ),
            child: Slider(
              key: const ValueKey('home-color-hue'),
              label: '色相',
              value: value.hue,
              max: 360,
              semanticFormatterCallback: (v) => '色相 ${v.round()} 度',
              onChanged: onChanged == null
                  ? null
                  : (hue) => onChanged!(value.withHue(hue)),
            ),
          ),
        ],
      ),
    ],
  );
}
