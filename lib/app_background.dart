import 'package:flutter/material.dart';

/// Keeps the user's app background separate from the reader's paper palette.
class AppBackground extends ThemeExtension<AppBackground> {
  const AppBackground(this.color, this.originalBrightness);
  final Color color;
  final Brightness originalBrightness;

  @override
  AppBackground copyWith({Color? color, Brightness? originalBrightness}) =>
      AppBackground(
        color ?? this.color,
        originalBrightness ?? this.originalBrightness,
      );

  @override
  AppBackground lerp(AppBackground? other, double t) => other == null
      ? this
      : AppBackground(
          Color.lerp(color, other.color, t)!,
          other.originalBrightness,
        );
}

Color? parseBackgroundHex(String value) {
  final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
  return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
      ? Color(0xff000000 | int.parse(hex, radix: 16))
      : null;
}

String backgroundHex(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Brightness appOriginalBrightness(ThemeData theme) =>
    theme.extension<AppBackground>()?.originalBrightness ?? theme.brightness;

ThemeData withAppBackground(ThemeData base, Color? background) {
  if (background == null) return base;
  final dark =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  final ink = dark ? const Color(0xfff2f2f2) : const Color(0xff20251f);
  Color raised(double amount) => Color.lerp(background, ink, amount)!;
  final scheme = base.colorScheme.copyWith(
    // Custom color affects contrast, never the selected appearance mode.
    brightness: base.brightness,
    surface: background,
    onSurface: ink,
    onSurfaceVariant: raised(.72),
    primary: ink,
    onPrimary: background,
    surfaceDim: background,
    surfaceBright: raised(.12),
    surfaceContainerLowest: background,
    surfaceContainerLow: raised(.025),
    surfaceContainer: raised(.05),
    surfaceContainerHigh: raised(.08),
    surfaceContainerHighest: raised(.12),
    outline: raised(.45),
    outlineVariant: raised(.2),
    inverseSurface: ink,
    onInverseSurface: background,
    surfaceTint: Colors.transparent,
  );
  return base.copyWith(
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: base.iconTheme.copyWith(color: ink),
    cupertinoOverrideTheme: base.cupertinoOverrideTheme?.copyWith(
      brightness: scheme.brightness,
      primaryColor: ink,
      primaryContrastingColor: background,
      scaffoldBackgroundColor: background,
    ),
    dividerColor: scheme.outlineVariant,
    disabledColor: raised(.4),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: scheme.surfaceContainerLow,
    ),
    extensions: [
      ...base.extensions.values.where((e) => e is! AppBackground),
      AppBackground(background, base.brightness),
    ],
  );
}
