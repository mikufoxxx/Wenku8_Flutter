import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_language.dart';

import 'archive_motion.dart';
import 'library_reflow.dart';
import 'wk_tokens.dart';

/// The archive vocabulary is foreground geometry, not another filter layer.
/// Codes, rules and registration marks are static and carry no idle ticker.
abstract final class ArchiveDesign {
  static const background = Color(0xFFF4F3EF);
  static const surface = Color(0xFFFDFCFA);
  static const milk = Color(0xFFFEFDF8);
  static const darkBackground = Color(0xFF191919);
  static const darkSurface = Color(0xFF242424);
  static const darkRaised = Color(0xFF2D2D2D);
  static const darkRaisedHigh = Color(0xFF3A3A3A);
  static const darkOutline = Color(0xFF3C3C3C);
  static const darkInk = WkColor.darkInk;
  static const darkMuted = WkColor.darkMuted;
  static const darkMilk = Color(0xFFF6F6F6);
  static const panelRadius = WkRadius.paper;
  static const coverRadius = WkRadius.paper;

  /// A thin neutral milk layer, not a white opaque sheet or another blur pass.
  static Color glassTint(Brightness brightness, {required double opacity}) =>
      brightness == Brightness.dark
      // Keep white labels legible even at the user's opaque endpoint.
      ? Color.lerp(darkMilk, darkSurface, opacity.clamp(0.0, 1.0))!
      : milk;

  static TextStyle codeStyle(BuildContext context, {Color? color}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return WkType.code.copyWith(
      color: color ?? (dark ? WkColor.darkCode : WkColor.code),
    );
  }

  static String fileCode(int id) => 'WK-${id.toString().padLeft(5, '0')}';
}

class ArchiveMasthead extends StatelessWidget {
  const ArchiveMasthead({
    super.key,
    required this.title,
    required this.code,
    this.brand = false,
  });
  final String title;
  final String code;
  final bool brand;

  @override
  Widget build(BuildContext context) => LibraryReflowPart(
    child: Row(
      children: [
        if (brand) ...[
          ExcludeSemantics(
            child: SizedBox(
              width: 30,
              height: 34,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    'assets/branding/app-icon.png',
                    key: const ValueKey('discovery-app-icon'),
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                    cacheWidth: (30 * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          // Keep the fixed 56 px toolbar usable with large system text, without
          // shrinking any reading content or enlarging its pinned hitbox plane.
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Keep the navigation landmark immediately readable; the
                  // archive address below it performs the terminal assembly.
                  AppText(
                    title,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                      shadows: [],
                    ),
                  ),
                  const SizedBox(height: 3),
                  ArchivePart(start: .16, end: .88, child: ArchiveCode(code)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class ArchiveCode extends StatelessWidget {
  const ArchiveCode(this.text, {super.key, this.inverse = false, this.color});
  final String text;
  final bool inverse;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = AppText(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: ArchiveDesign.codeStyle(
        context,
        color: color ?? (inverse ? scheme.surface : null),
      ),
    );
    return ExcludeSemantics(
      child: inverse
          ? ColoredBox(
              color: scheme.onSurface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: label,
              ),
            )
          : label,
    );
  }
}

class ArchiveSection extends StatelessWidget {
  const ArchiveSection({
    super.key,
    required this.title,
    required this.code,
    this.subtitle = '',
  });
  final String title;
  final String code;
  final String subtitle;

  @override
  Widget build(BuildContext context) => LibraryReflowPart(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, constraints.maxWidth - 17),
                ),
                child: ArchivePart(
                  start: .1,
                  end: .68,
                  child: ArchiveCode(code),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: const ArchivePart(
                  start: 0,
                  end: .46,
                  child: ExcludeSemantics(
                    child: Divider(height: 1, thickness: .6),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              ExcludeSemantics(
                child: SizedBox(
                  width: 3,
                  height: 3,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        ArchivePart(
          start: .16,
          end: .82,
          child: AppText(
            title,
            style: WkType.titleM,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 5),
          AppText(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Readable route title plus a restrained archive address below it.
class ArchiveRouteTitle extends StatelessWidget {
  const ArchiveRouteTitle({super.key, required this.title, required this.code});
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: constraints.maxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 3),
            ArchiveCode(code),
          ],
        ),
      ),
    ),
  );
}

class ArchiveRegistration extends StatelessWidget {
  const ArchiveRegistration({super.key, required this.child, this.inset = 0});
  final Widget child;
  final double inset;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _RegistrationPainter(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
      inset: inset,
    ),
    child: child,
  );
}

class _RegistrationPainter extends CustomPainter {
  const _RegistrationPainter({required this.color, required this.inset});
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    final r = (Offset.zero & size).deflate(inset + .5);
    final length = math.min(7.0, math.min(r.width, r.height) / 3);
    if (length <= 0) return;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx + dx * length, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + dy * length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RegistrationPainter oldDelegate) =>
      color != oldDelegate.color || inset != oldDelegate.inset;
}

/// The diagram is limited to the header margin. The reading canvas stays plain.
class ArchiveBackdrop extends StatelessWidget {
  const ArchiveBackdrop({super.key, this.filmColor = ArchiveDesign.milk});
  final Color filmColor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.topCenter,
        // Bound the raster-cache candidate to the diagram itself, rather than
        // allocating a full-screen layer for an almost empty static painter.
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.viewPaddingOf(context).top + 240,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ArchiveBackdropPainter(
                color: Theme.of(context).colorScheme.onSurface,
                filmColor: filmColor,
                top: MediaQuery.viewPaddingOf(context).top,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ArchiveBackdropPainter extends CustomPainter {
  const _ArchiveBackdropPainter({
    required this.color,
    required this.top,
    required this.filmColor,
  });
  final Color color;
  final Color filmColor;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = math.min(size.height, top + 240);
    final dark = color.computeLuminance() > .5;
    final film = Paint()
      ..color = filmColor.withValues(alpha: dark ? .018 : .42);
    // Two restrained frosted file planes in the existing small header raster.
    // They are paint geometry: no backdrop filter, full-screen layer or ticker.
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .42, top)
        ..lineTo(size.width, top)
        ..lineTo(size.width, bottom * .82)
        ..lineTo(size.width * .78, bottom * .82)
        ..close(),
      film,
    );
    film.color = filmColor.withValues(alpha: dark ? .012 : .28);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .60, top + 18)
        ..lineTo(size.width, top + 18)
        ..lineTo(size.width, bottom)
        ..lineTo(size.width * .92, bottom)
        ..close(),
      film,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .045)
      ..strokeWidth = .5;
    for (var x = 24.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, bottom), paint);
    }
    for (var y = top + 4; y < bottom; y += 48) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), paint);
    }
    paint.color = color.withValues(alpha: .15);
    final y = top + 60;
    for (final x in [24.0, size.width - 24]) {
      canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), paint);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_ArchiveBackdropPainter oldDelegate) =>
      color != oldDelegate.color ||
      top != oldDelegate.top ||
      filmColor != oldDelegate.filmColor;
}
