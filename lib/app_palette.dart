import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'archive_design.dart';
import 'wk_tokens.dart';

enum AppPaletteSource { original, system, custom }

@immutable
class AppPalettePreferences {
  const AppPalettePreferences({
    this.source = AppPaletteSource.original,
    this.seed = 0xff607d71,
    this.themedIcon = true,
  });
  static const key = 'appPalette';
  final AppPaletteSource source;
  final int seed;
  // Existing Android 13 icons already expose a monochrome layer. Keep that
  // behavior until the user explicitly opts out.
  final bool themedIcon;
  Color get color => Color(seed);
  AppPalettePreferences copyWith({
    AppPaletteSource? source,
    int? seed,
    bool? themedIcon,
  }) => AppPalettePreferences(
    source: source ?? this.source,
    seed: seed ?? this.seed,
    themedIcon: themedIcon ?? this.themedIcon,
  );
  Map<String, Object> toJson() => {
    'source': source.name,
    'seed': seed,
    'themedIcon': themedIcon,
  };
  String encode() => jsonEncode(toJson());
  static AppPalettePreferences decode(Object? record) {
    if (record == null) return const AppPalettePreferences();
    if (record is! String || record.length > 512) {
      throw const FormatException('配色记录有误');
    }
    final raw = jsonDecode(record);
    if (raw is! Map ||
        raw['source'] is! String ||
        !AppPaletteSource.values.any((s) => s.name == raw['source']) ||
        raw['seed'] is! int ||
        raw['seed'] < 0xff000000 ||
        raw['seed'] > 0xffffffff ||
        raw['themedIcon'] is! bool) {
      throw const FormatException('配色记录有误');
    }
    return AppPalettePreferences(
      source: AppPaletteSource.values.byName(raw['source']),
      seed: raw['seed'],
      themedIcon: raw['themedIcon'],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppPalettePreferences &&
      other.source == source &&
      other.seed == seed &&
      other.themedIcon == themedIcon;
  @override
  int get hashCode => Object.hash(source, seed, themedIcon);
}

/// The five Android tonal palettes, ordered by tone rather than resource suffix.
/// No wallpaper access or bitmap permission is needed.
@immutable
class SystemTonalColors {
  SystemTonalColors(List<List<int>> colors)
    : palettes = List.unmodifiable(
        colors.map((p) => List<int>.unmodifiable(p)),
      );
  final List<List<int>> palettes;
  static SystemTonalColors? fromMap(Object? raw) {
    if (raw is! List || raw.length != 5) return null;
    final colors = <List<int>>[];
    for (final p in raw) {
      if (p is! List ||
          p.length != 13 ||
          p.any((c) => c is! int || c < 0xff000000 || c > 0xffffffff)) {
        return null;
      }
      colors.add(p.cast<int>());
    }
    return SystemTonalColors(colors);
  }

  late final String signature = palettes.expand((p) => p).join(',');
  ColorScheme scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tonal = palettes.map(TonalPalette.fromList).toList();
    Color a(int palette, int tone) => Color(tonal[palette].get(tone));
    return ColorScheme.fromSeed(
      seedColor: a(0, 50),
      brightness: brightness,
    ).copyWith(
      primary: a(0, dark ? 80 : 40),
      onPrimary: a(0, dark ? 20 : 100),
      primaryContainer: a(0, dark ? 30 : 90),
      onPrimaryContainer: a(0, dark ? 90 : 10),
      secondary: a(1, dark ? 80 : 40),
      onSecondary: a(1, dark ? 20 : 100),
      secondaryContainer: a(1, dark ? 30 : 90),
      onSecondaryContainer: a(1, dark ? 90 : 10),
      tertiary: a(2, dark ? 80 : 40),
      onTertiary: a(2, dark ? 20 : 100),
      tertiaryContainer: a(2, dark ? 30 : 90),
      onTertiaryContainer: a(2, dark ? 90 : 10),
      surface: a(3, dark ? 6 : 98),
      onSurface: a(3, dark ? 90 : 10),
      onSurfaceVariant: a(4, dark ? 80 : 30),
      surfaceDim: a(3, dark ? 6 : 87),
      surfaceBright: a(3, dark ? 24 : 98),
      surfaceContainerLowest: a(3, dark ? 4 : 100),
      surfaceContainerLow: a(3, dark ? 10 : 96),
      surfaceContainer: a(3, dark ? 12 : 94),
      surfaceContainerHigh: a(3, dark ? 17 : 92),
      surfaceContainerHighest: a(3, dark ? 22 : 90),
      outline: a(4, dark ? 60 : 50),
      outlineVariant: a(4, dark ? 30 : 80),
      inverseSurface: a(3, dark ? 90 : 20),
      onInverseSurface: a(3, dark ? 20 : 95),
      inversePrimary: a(0, dark ? 40 : 80),
      surfaceTint: Colors.transparent,
    );
  }
}

/// A small, interpolated set of archive/glass colors. Classic values reproduce
/// the old material exactly; no additional blur layer or idle animation.
@immutable
class AppTonalColors extends ThemeExtension<AppTonalColors> {
  const AppTonalColors({
    required this.pageStart,
    required this.pageEnd,
    required this.milk,
    required this.darkMilk,
    required this.glassSurface,
    required this.active,
    required this.track,
    required this.thumb,
    required this.action,
  });
  final Color pageStart,
      pageEnd,
      milk,
      darkMilk,
      glassSurface,
      active,
      track,
      thumb,
      action;
  factory AppTonalColors.forScheme(ColorScheme s, {required bool original}) {
    final dark = s.brightness == Brightness.dark;
    return AppTonalColors(
      pageStart: original
          ? (dark ? ArchiveDesign.darkBackground : ArchiveDesign.surface)
          : s.surface,
      pageEnd: original
          ? (dark ? ArchiveDesign.darkSurface : ArchiveDesign.background)
          : s.surfaceContainerLow,
      milk: original
          ? ArchiveDesign.milk
          : Color.lerp(s.surfaceContainerLowest, s.primaryContainer, .18)!,
      darkMilk: original ? ArchiveDesign.darkMilk : s.onSurface,
      glassSurface: original
          ? ArchiveDesign.darkSurface
          : s.surfaceContainerLow,
      active: original
          ? (dark ? WkColor.darkInk : WkColor.ink)
          : s.primary,
      track: original
          ? Color.lerp(s.surface, s.onSurface, dark ? .16 : .10)!
          : s.surfaceContainerHighest,
      thumb: original
          ? ArchiveDesign.milk
          : dark
          ? s.onSurface
          : s.surfaceContainerLowest,
      action: original ? s.onSurface : s.primary,
    );
  }
  Color tint(Brightness brightness, double opacity) =>
      brightness == Brightness.dark
      ? Color.lerp(darkMilk, glassSurface, opacity.clamp(0, 1))!
      : milk;
  @override
  AppTonalColors copyWith({
    Color? pageStart,
    Color? pageEnd,
    Color? milk,
    Color? darkMilk,
    Color? glassSurface,
    Color? active,
    Color? track,
    Color? thumb,
    Color? action,
  }) => AppTonalColors(
    pageStart: pageStart ?? this.pageStart,
    pageEnd: pageEnd ?? this.pageEnd,
    milk: milk ?? this.milk,
    darkMilk: darkMilk ?? this.darkMilk,
    glassSurface: glassSurface ?? this.glassSurface,
    active: active ?? this.active,
    track: track ?? this.track,
    thumb: thumb ?? this.thumb,
    action: action ?? this.action,
  );
  @override
  AppTonalColors lerp(AppTonalColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTonalColors(
      pageStart: c(pageStart, other.pageStart),
      pageEnd: c(pageEnd, other.pageEnd),
      milk: c(milk, other.milk),
      darkMilk: c(darkMilk, other.darkMilk),
      glassSurface: c(glassSurface, other.glassSurface),
      active: c(active, other.active),
      track: c(track, other.track),
      thumb: c(thumb, other.thumb),
      action: c(action, other.action),
    );
  }
}
