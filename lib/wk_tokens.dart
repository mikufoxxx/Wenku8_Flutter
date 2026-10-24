import 'package:flutter/material.dart';

/// Archive tokens converged from the existing palette. Pages should prefer
/// these values, [ThemeData.textTheme], or the shared widgets that already
/// read them, instead of inventing another inline size or gray.
abstract final class WkColor {
  static const background = Color(0xFFF4F3EF);
  static const surface = Color(0xFFFDFCFA);
  static const milk = Color(0xFFFEFDF8);
  static const ink = Color(0xFF181818);
  static const muted = Color(0xFF5F655D);
  static const code = Color(0xFF858B82);
  static const hairline = Color(0xFFD8DBD5);
  static const cover = Color(0xFF202020);
  static const error = Color(0xFFB3261E);
  static const success = Color(0xFF3E6B52);
  static const warnBg = Color(0xFFEFEADF);

  static const darkBackground = Color(0xFF191919);
  static const darkSurface = Color(0xFF242424);
  static const darkRaised = Color(0xFF2D2D2D);
  static const darkRaisedHigh = Color(0xFF3A3A3A);
  static const darkOutline = Color(0xFF3C3C3C);
  static const darkInk = Color(0xFFF2F2F2);
  static const darkMuted = Color(0xFFBDBDBD);
  static const darkCode = Color(0xFF8F8F8F);

  static const seeds = <String, Color>{
    '雾松': Color(0xFF607D71),
    '浅海': Color(0xFF547D98),
    '鸢尾': Color(0xFF887AA5),
    '胭脂': Color(0xFFA06A77),
    '麦穗': Color(0xFF9B8452),
    '石墨': Color(0xFF72767D),
  };

  static String seedName(int seed) {
    for (final entry in seeds.entries) {
      if (entry.value.toARGB32() == seed) return entry.key;
    }
    final hex = seed.toRadixString(16).padLeft(8, '0').substring(2);
    return '#${hex.toUpperCase()}';
  }
}

abstract final class WkType {
  static const display = TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w800,
    height: 1.18,
    letterSpacing: -.7,
  );
  static const titleL = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.25,
    letterSpacing: -.5,
  );
  static const titleM = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -.3,
  );
  static const titleS = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );
  static const bodyS = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const code = TextStyle(
    fontFamily: 'monospace',
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: .9,
  );

  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
    headlineSmall: display.copyWith(color: ink),
    titleLarge: titleL.copyWith(color: ink),
    titleMedium: titleM.copyWith(color: ink),
    titleSmall: titleS.copyWith(color: ink),
    bodyMedium: body.copyWith(color: ink),
    bodySmall: bodyS.copyWith(color: muted),
    labelMedium: caption.copyWith(color: muted),
  );
}

abstract final class WkSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const page = 24.0;
  static const s32 = 32.0;
}

abstract final class WkRadius {
  static const paper = 4.0;
  static const float = 16.0;
  static const sheet = 28.0;
  static BorderRadius capsule(double height) =>
      BorderRadius.circular(height / 2);
}

abstract final class WkMotion {
  static const contact = Duration(milliseconds: 100);
  static const quick = Duration(milliseconds: 180);
  static const exit = Duration(milliseconds: 240);
  static const enter = Duration(milliseconds: 320);
  static const coverFlight = Duration(milliseconds: 560);
  static const settle = Curves.easeOutCubic;
}

extension WkTonal on ColorScheme {
  Color get selectedFill => primary;
  Color get onSelected => onPrimary;
}
