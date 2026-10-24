import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'archive_motion.dart';
import 'loading_handoff.dart';
import 'loading_ui.dart';
import 'wk_tokens.dart';

export 'archive_motion.dart';
export 'loading_handoff.dart';

/// One motion vocabulary for controls, menus, sheets and in-place expansion.
/// The paper flight/reveal are choreographed sequences, not repeating effects.
abstract final class NovelMotion {
  static const contact = WkMotion.contact;
  static const quick = WkMotion.quick;
  static const enter = WkMotion.enter;
  static const exit = WkMotion.exit;
  static const coverFlight = WkMotion.coverFlight;
  static const coverReturn = Duration(milliseconds: 470);
  static const reveal = enter;
  static const ease = Curves.easeOutCubic;
  static const retract = Curves.easeInCubic;
  static const settle = Cubic(.2, 1.08, .34, 1);
  static const spring = SpringDescription(
    mass: .64,
    stiffness: 270,
    damping: 19,
  );

  static double jelly(double t) =>
      math.sin(t * math.pi * 3) * (1 - t) * (1 - t);

  static double progress(Animation<double> animation) =>
      (animation.status == AnimationStatus.reverse ? retract : ease).transform(
        animation.value,
      );
}

/// A peel front travels from the upper edge to the lower edge. Near the end
/// of the flight a diagonal contact front travels from bottom-left to top-right.
/// Depth is exactly zero at both endpoints; arrival has no continuing ticker.
class PaperFlightPose {
  const PaperFlightPose(this.progress);
  final double progress;

  static double _smooth(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double travel(double progress) =>
      Curves.easeInOutCubic.transform(((progress - .12) / .46).clamp(0.0, 1.0));

  /// Hero adds fastOutSlowIn itself. Undo that clock before applying our
  /// choreography, otherwise the travel and contact get eased twice.
  static double heroTimeline(double value) {
    if (value <= 0 || value >= 1) return value.clamp(0.0, 1.0);
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 18; i++) {
      final parameter = (low + high) / 2;
      if (_smooth(parameter) < value) {
        low = parameter;
      } else {
        high = parameter;
      }
    }
    final t = (low + high) / 2;
    final remaining = 1 - t;
    // x of Cubic(.4, 0, .2, 1), after solving its y above.
    return 1.2 * remaining * remaining * t + .6 * remaining * t * t + t * t * t;
  }

  double depthAt(double row, {double column = .5}) {
    if (progress <= 0 || progress >= 1) return 0;
    final v = row.clamp(0.0, 1.0);
    final peel = _smooth((progress - .025 - v * .11) / .11);
    final landing = ((progress - .58) / .42).clamp(0.0, 1.0);
    // The lower-left corner settles first, then the contact sweeps across the
    // face. A row-only field would flatten the entire bottom edge at once.
    final contact = (1 - v) * .66 + column.clamp(0.0, 1.0) * .34;
    final floating = 1 - _smooth((landing - contact * .70) / .30);
    final breeze = math.sin((v * 1.3 - progress * 1.6) * math.pi * 2);
    return peel *
        floating *
        (17 +
            7 * math.sin(v * math.pi) +
            3 * breeze * math.sin(progress * math.pi));
  }

  double get lift =>
      18 * _smooth(progress / .18) * (1 - _smooth((progress - .42) / .16));

  double get roll =>
      -.045 *
      math.sin(progress.clamp(0.0, 1.0) * math.pi) *
      (1 - _smooth((progress - .42) / .16));
}

/// The flat Hero bounds remain a valid layout box. Travel waits briefly for
/// the peel, and reaches the target before the diagonal landing finishes.
class PaperCoverRectTween extends RectTween {
  PaperCoverRectTween({
    super.begin,
    super.end,
    required this.returning,
    this.heroCurve = false,
    this.endPaintOffset = Offset.zero,
  });
  final bool returning;
  final bool heroCurve;
  final Offset endPaintOffset;

  /// Hero tracks its destination's local origin on every tick, but initially
  /// measures a transformed bounding rectangle. Those differ on a slanted
  /// cover. Keep the tracked endpoint at the origin, and apply its exact
  /// bounds correction only when painting the flight.
  factory PaperCoverRectTween.toHero({
    required BuildContext context,
    required Rect? begin,
    required Rect? end,
    required bool returning,
  }) {
    final box = context.findRenderObject();
    final route = ModalRoute.of(context)?.subtreeContext?.findRenderObject();
    var offset = Offset.zero;
    if (box is RenderBox && box.hasSize && route != null && end != null) {
      final matrix = box.getTransformTo(route);
      final bounds = MatrixUtils.transformRect(matrix, Offset.zero & box.size);
      final origin = MatrixUtils.transformPoint(matrix, Offset.zero);
      offset = bounds.topLeft - origin;
      end = origin & bounds.size;
    }
    return PaperCoverRectTween(
      begin: begin,
      end: end,
      returning: returning,
      heroCurve: true,
      endPaintOffset: offset,
    );
  }

  @override
  Rect lerp(double t) {
    final target = end!.shift(endPaintOffset);
    if (t <= 0) return begin!;
    if (t >= 1) return target;
    if (heroCurve) t = PaperFlightPose.heroTimeline(t);
    final travel = returning
        ? 1 - PaperFlightPose.travel(1 - t)
        : PaperFlightPose.travel(t);
    if (travel <= 0) return begin!;
    if (travel >= 1) return target;
    final center = Offset.lerp(begin!.center, target.center, travel)!;
    final distance = (target.center - begin!.center).distance;
    final lift =
        math.min(32.0, 12 + distance * .075) * math.sin(travel * math.pi);
    return Rect.fromCenter(
      center: center + Offset(0, -lift),
      width: begin!.width + (target.width - begin!.width) * travel,
      height: begin!.height + (target.height - begin!.height) * travel,
    );
  }
}

/// A Hero's bounding rectangle is not its painted face when the source sits
/// on an oblique archive file. Retain that face's actual affine projection so
/// takeoff and return meet the artwork, not a suddenly flattened rectangle.
@immutable
class PaperCoverPlane {
  const PaperCoverPlane(this.origin, this.horizontal, this.vertical);
  static const flat = PaperCoverPlane(Offset.zero, Offset(1, 0), Offset(0, 1));
  final Offset origin;
  final Offset horizontal;
  final Offset vertical;

  static PaperCoverPlane fromHero(BuildContext context) {
    final box = context.findRenderObject();
    final overlay = Navigator.maybeOf(
      context,
    )?.overlay?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        box.size.isEmpty ||
        overlay == null) {
      return flat;
    }
    final matrix = box.getTransformTo(overlay);
    final bounds = MatrixUtils.transformRect(matrix, Offset.zero & box.size);
    if (bounds.isEmpty || !bounds.width.isFinite || !bounds.height.isFinite) {
      return flat;
    }
    Offset point(Offset local) {
      final world = MatrixUtils.transformPoint(matrix, local);
      return Offset(
        (world.dx - bounds.left) / bounds.width,
        (world.dy - bounds.top) / bounds.height,
      );
    }

    final origin = point(Offset.zero);
    return PaperCoverPlane(
      origin,
      point(Offset(box.size.width, 0)) - origin,
      point(Offset(0, box.size.height)) - origin,
    );
  }

  static Path? occlusionFromHero(BuildContext context) {
    final face = context.findRenderObject();
    if (face is! RenderBox || !face.hasSize) return null;
    RenderObject? ancestor = face.parent;
    while (ancestor != null) {
      if (ancestor is PaperCoverOcclusionSource) {
        final path = (ancestor as PaperCoverOcclusionSource).coverOcclusion(
          face,
        );
        final route = ModalRoute.of(
          context,
        )?.subtreeContext?.findRenderObject();
        final overlay = Navigator.maybeOf(
          context,
        )?.overlay?.context.findRenderObject();
        if (path == null || route == null || overlay == null) return path;
        // The covered shelf is still under Cupertino's outgoing parallax at
        // pop start. Retain its final scene mask, not that temporary offset.
        final inverse = Matrix4.tryInvert(route.getTransformTo(null));
        if (inverse == null) return path;
        return path.transform(
          (overlay.getTransformTo(null)..multiply(inverse)).storage,
        );
      }
      ancestor = ancestor.parent;
    }
    return null;
  }

  Offset point(double u, double v) => origin + horizontal * u + vertical * v;

  static PaperCoverPlane lerp(PaperCoverPlane a, PaperCoverPlane b, double t) =>
      PaperCoverPlane(
        Offset.lerp(a.origin, b.origin, t)!,
        Offset.lerp(a.horizontal, b.horizontal, t)!,
        Offset.lerp(a.vertical, b.vertical, t)!,
      );

  Matrix4 matrix(Size size) => Matrix4.identity()
    ..setEntry(0, 0, horizontal.dx)
    ..setEntry(1, 0, horizontal.dy * size.height / size.width)
    ..setEntry(0, 1, vertical.dx * size.width / size.height)
    ..setEntry(1, 1, vertical.dy)
    ..setEntry(0, 3, origin.dx * size.width)
    ..setEntry(1, 3, origin.dy * size.height);
}

/// Source scenes provide physical foreground silhouettes, not page snapshots.
abstract interface class PaperCoverOcclusionSource {
  Path? coverOcclusion(RenderBox face);
}

class PaperCoverFlight extends StatefulWidget {
  const PaperCoverFlight({
    super.key,
    required this.animation,
    required this.child,
    this.imageProvider,
    this.faceSize = const Size(120, 164),
    this.beginPlane = PaperCoverPlane.flat,
    this.endPlane = PaperCoverPlane.flat,
    this.backingColor = const Color(0xFF202020),
    this.beginOcclusion,
    this.endOcclusion,
  });
  final Animation<double> animation;
  final Widget child;
  final ImageProvider? imageProvider;
  final Size faceSize;
  final PaperCoverPlane beginPlane;
  final PaperCoverPlane endPlane;
  final Color backingColor;
  final Path? beginOcclusion;
  final Path? endOcclusion;

  @override
  State<PaperCoverFlight> createState() => _PaperCoverFlightState();
}

class _PaperCoverFlightState extends State<PaperCoverFlight> {
  final _face = GlobalKey();
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  ui.Image? _fallback;
  bool _snapshotRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(PaperCoverFlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) _resolveImage();
  }

  void _resolveImage() {
    final provider = widget.imageProvider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronous) {
        if (!mounted) {
          info.dispose();
          return;
        }
        _info?.dispose();
        _info = info;
        if (!synchronous && mounted) setState(() {});
      },
      onError: (Object error, StackTrace? stack) {
        // The normal cover already handles image failure. Its exact fallback
        // face is captured once, rather than decoded/requested a second time.
      },
    );
    stream.addListener(_listener!);
  }

  void _cacheFallback() {
    if (_snapshotRequested || _info != null || _fallback != null) return;
    _snapshotRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _info != null) return;
      final boundary = _face.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) return;
      // A small GPU-only cover texture, once per flight. No page readback,
      // screenshot, asynchronous decode or repeated subtree paint per frame.
      final scale =
          MediaQuery.devicePixelRatioOf(context) *
          math.max(
            1.0,
            widget.faceSize.longestSide / boundary.size.longestSide,
          );
      try {
        final image = boundary.toImageSync(pixelRatio: scale.clamp(1.0, 8.0));
        setState(() => _fallback = image);
      } on FlutterError {
        // Keep the original face on renderers without synchronous textures.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    _cacheFallback();
    return RepaintBoundary(
      child: PaperCoverBend(
        key: const ValueKey('paper-cover-transform'),
        animation: widget.animation,
        image: _info?.image ?? _fallback,
        imageIsFitted: _info == null,
        faceSize: widget.faceSize,
        beginPlane: widget.beginPlane,
        endPlane: widget.endPlane,
        backingColor: widget.backingColor,
        beginOcclusion: widget.beginOcclusion,
        endOcclusion: widget.endOcclusion,
        child: _info == null
            ? RepaintBoundary(key: _face, child: widget.child)
            : widget.child,
      ),
    );
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    _fallback?.dispose();
    super.dispose();
  }
}

/// One textured GPU mesh, not 24 paints/clips of the full cover subtree.
/// Animation ticks invalidate only this paint, without rebuilding widgets.
class PaperCoverBend extends SingleChildRenderObjectWidget {
  const PaperCoverBend({
    super.key,
    this.progress = 0,
    this.animation,
    this.image,
    this.imageIsFitted = false,
    this.faceSize = const Size(120, 164),
    this.beginPlane = PaperCoverPlane.flat,
    this.endPlane = PaperCoverPlane.flat,
    this.backingColor = const Color(0xFF202020),
    this.beginOcclusion,
    this.endOcclusion,
    required super.child,
  });
  final double progress;
  final Animation<double>? animation;
  final ui.Image? image;
  final bool imageIsFitted;
  final Size faceSize;
  final PaperCoverPlane beginPlane;
  final PaperCoverPlane endPlane;
  final Color backingColor;
  final Path? beginOcclusion;
  final Path? endOcclusion;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      PaperCoverRender(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as PaperCoverRender).update(this);
  }
}

class PaperCoverRender extends RenderProxyBox {
  PaperCoverRender(this.config);
  PaperCoverBend config;
  ui.ImageShader? _shader;
  ui.Image? _shaderImage;
  List<double> _rows = const [];
  Float32List _positions = Float32List(0);
  Float32List _texture = Float32List(0);
  Uint16List _indices = Uint16List(0);
  Int32List _faceColors = Int32List(0);
  final _paint = Paint()..isAntiAlias = true;
  final _fallbackLayer = LayerHandle<TransformLayer>();
  final _fallbackClipLayer = LayerHandle<ClipPathLayer>();
  int debugMeshDraws = 0;
  int debugChildPaints = 0;
  double get progress => config.animation?.value ?? config.progress;

  ({Path path, double alpha})? _occlusion() {
    final departing = config.beginOcclusion;
    final arriving = config.endOcclusion;
    if (departing != null && progress < .12) {
      return (
        path: departing,
        alpha: 1 - Curves.easeInOut.transform((progress / .12).clamp(0.0, 1.0)),
      );
    }
    if (arriving != null && progress > .88) {
      return (
        path: arriving,
        alpha: Curves.easeInOut.transform(
          ((progress - .88) / .12).clamp(0.0, 1.0),
        ),
      );
    }
    return null;
  }

  PaperCoverPlane get debugPlane {
    if (progress <= 0) return config.beginPlane;
    if (progress >= 1) return config.endPlane;
    final depart = Curves.easeInOutCubic.transform(
      ((progress - .02) / .32).clamp(0.0, 1.0),
    );
    final contact = Curves.easeInOutCubic.transform(
      ((progress - .58) / .42).clamp(0.0, 1.0),
    );
    return PaperCoverPlane.lerp(
      PaperCoverPlane.lerp(config.beginPlane, PaperCoverPlane.flat, depart),
      config.endPlane,
      contact,
    );
  }

  void update(PaperCoverBend value) {
    if (config.animation != value.animation) {
      if (attached) config.animation?.removeListener(markNeedsPaint);
      if (attached) value.animation?.addListener(markNeedsPaint);
    }
    if (config.faceSize != value.faceSize) _rows = const [];
    config = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    config.animation?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    config.animation?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  Rect get paintBounds => (Offset.zero & size).inflate(28);

  void _prepareMesh(ui.Image image, PaperFlightPose pose) {
    if (_shaderImage != image) {
      _shader?.dispose();
      _shaderImage = image;
      _shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.low,
      );
      _paint.shader = _shader;
    }
    final face = config.faceSize;
    final radiusY = (8 / face.height).clamp(0.0, .5);
    final radiusX = (8 / face.width).clamp(0.0, .5);
    if (_rows.isEmpty) {
      final rows = <double>{for (var i = 0; i <= 32; i++) i / 32};
      for (var i = 1; i <= 8; i++) {
        final v = radiusY * (1 - math.cos(i / 8 * math.pi / 2));
        rows.add(v);
        rows.add(1 - v);
      }
      _rows = rows.toList()..sort();
      const columns = 17;
      _positions = Float32List(_rows.length * columns * 2);
      _texture = Float32List(_positions.length);
      _indices = Uint16List((_rows.length - 1) * (columns - 1) * 6);
      var triangle = 0;
      for (var row = 0; row < _rows.length - 1; row++) {
        for (var column = 0; column < columns - 1; column++) {
          final topLeft = row * columns + column;
          final bottomLeft = topLeft + columns;
          for (final index in [
            topLeft,
            bottomLeft,
            topLeft + 1,
            topLeft + 1,
            bottomLeft,
            bottomLeft + 1,
          ]) {
            _indices[triangle++] = index;
          }
        }
      }
      _faceColors = Int32List(_positions.length ~/ 2);
    }
    // Transparent artwork keeps the same milk-white substrate during flight.
    _faceColors.fillRange(
      0,
      _faceColors.length,
      config.backingColor.toARGB32(),
    );
    final input = Size(image.width.toDouble(), image.height.toDouble());
    final source = config.imageIsFitted
        ? Offset.zero & input
        : Alignment.center.inscribe(
            applyBoxFit(BoxFit.cover, input, face).source,
            Offset.zero & input,
          );
    final plane = debugPlane;
    for (var index = 0; index < _rows.length; index++) {
      final v = _rows[index];
      final corner = math.min(v, 1 - v) / radiusY;
      final inset = corner >= 1
          ? 0.0
          : radiusX *
                (1 - math.sqrt(math.max(0, 1 - (1 - corner) * (1 - corner))));
      const columns = 17;
      for (var column = 0; column < columns; column++) {
        final u = inset + (1 - 2 * inset) * column / (columns - 1);
        final scale = 300 / (300 - pose.depthAt(v, column: u));
        final base = (index * columns + column) * 2;
        final projected = plane.point(
          .5 + (u - .5) * scale,
          .5 + (v - .5) * scale,
        );
        _positions[base] = size.width * projected.dx;
        _positions[base + 1] = size.height * projected.dy;
        _texture[base] = source.left + source.width * u;
        _texture[base + 1] = source.top + source.height * v;
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty || child == null) return;
    final pose = PaperFlightPose(progress);
    final image = config.image;
    final occlusion = _occlusion();
    final mask = occlusion?.path.transform(
      Matrix4.inverted(getTransformTo(null)).storage,
    );
    if (image == null) {
      // Only the first frame (or an unsupported renderer) uses the original
      // face. It is never replayed in bands, even for a composited fallback.
      debugChildPaints++;
      final matrix = Matrix4.identity()
        ..translateByDouble(size.width / 2, size.height / 2 - pose.lift, 0, 1)
        ..rotateZ(pose.roll)
        ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1)
        ..multiply(debugPlane.matrix(size));
      void paintFace(PaintingContext context, Offset offset) {
        _fallbackLayer.layer = context.pushTransform(
          needsCompositing,
          offset,
          matrix,
          (context, offset) => super.paint(context, offset),
          oldLayer: _fallbackLayer.layer,
        );
      }

      if (mask == null) {
        _fallbackClipLayer.layer = null;
        paintFace(context, offset);
      } else {
        _fallbackClipLayer.layer = context.pushClipPath(
          needsCompositing,
          offset,
          paintBounds,
          Path.combine(
            PathOperation.difference,
            Path()..addRect(paintBounds),
            mask,
          ),
          paintFace,
          oldLayer: _fallbackClipLayer.layer,
        );
      }
      return;
    }
    _fallbackLayer.layer = null;
    _fallbackClipLayer.layer = null;
    _prepareMesh(image, pose);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions,
      textureCoordinates: _texture,
      colors: config.imageIsFitted ? null : _faceColors,
      indices: _indices,
    );
    final canvas = context.canvas;
    if (mask != null) canvas.saveLayer(paintBounds.shift(offset), Paint());
    canvas.save();
    canvas.translate(
      offset.dx + size.width / 2,
      offset.dy + size.height / 2 - pose.lift,
    );
    canvas.rotate(pose.roll);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
    canvas.restore();
    if (mask != null) {
      canvas.drawPath(
        mask.shift(offset),
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Colors.black.withValues(alpha: occlusion!.alpha),
      );
      canvas.restore();
    }
    vertices.dispose();
    debugMeshDraws++;
  }

  @override
  void dispose() {
    _fallbackLayer.layer = null;
    _fallbackClipLayer.layer = null;
    _shader?.dispose();
    super.dispose();
  }
}

enum GlassOverlayKind { menu, sheet }

/// One live glass plane grows out of the original control. Layout and widget
/// construction stay at the final size; only the retained paint transform moves.
class GlassMenuStretch extends SingleChildRenderObjectWidget {
  const GlassMenuStretch({
    super.key,
    required this.animation,
    required this.anchor,
    required super.child,
    this.coordinateSpace,
  });

  final Animation<double> animation;
  final Rect anchor;
  final RenderBox? coordinateSpace;

  @override
  GlassMenuStretchRender createRenderObject(BuildContext context) =>
      GlassMenuStretchRender(animation, anchor, coordinateSpace);

  @override
  void updateRenderObject(
    BuildContext context,
    GlassMenuStretchRender renderObject,
  ) => renderObject.update(animation, anchor, coordinateSpace);
}

class GlassMenuStretchRender extends RenderProxyBox {
  GlassMenuStretchRender(this._animation, this._anchor, this._coordinateSpace);

  Animation<double> _animation;
  Rect _anchor;
  RenderBox? _coordinateSpace;
  final _transformLayer = LayerHandle<TransformLayer>();
  int debugLayoutCount = 0;
  int debugPaintCount = 0;

  double get progress => Curves.easeOutCubic.transform(_animation.value);

  Rect get anchor => _anchor;

  Rect get targetRect => MatrixUtils.transformRect(
    getTransformTo(_coordinateSpace),
    Offset.zero & size,
  );

  Rect get localCurrentRect {
    final inverse = Matrix4.tryInvert(getTransformTo(_coordinateSpace));
    return inverse == null
        ? Offset.zero & size
        : MatrixUtils.transformRect(inverse, currentRect);
  }

  Offset sourceOffset(Size sourceSize) {
    final inverse = Matrix4.tryInvert(getTransformTo(_coordinateSpace));
    final center = inverse == null
        ? _anchor.center
        : MatrixUtils.transformPoint(inverse, _anchor.center);
    return center -
        localCurrentRect.topLeft -
        Offset(sourceSize.width / 2, sourceSize.height / 2);
  }

  Rect get currentRect {
    final target = targetRect;
    final rect = Rect.lerp(_anchor, target, progress)!;
    // The bubble opens promptly, width first, with one small elastic settle.
    // This clock is direction-independent, so reversing a partly open menu
    // follows the same continuous path rather than jumping to another curve.
    final widthProgress = const Cubic(
      .18,
      1.10,
      .30,
      1,
    ).transform(_animation.value);
    final heightProgress = const Cubic(
      .22,
      1.04,
      .32,
      1,
    ).transform(_animation.value);
    final width = ui.lerpDouble(_anchor.width, target.width, widthProgress)!;
    final height = ui.lerpDouble(
      _anchor.height,
      target.height,
      heightProgress,
    )!;
    final growsDown = target.center.dy >= _anchor.center.dy;
    return Rect.fromLTWH(
      rect.right - width,
      growsDown ? rect.top : rect.bottom - height,
      width,
      height,
    );
  }

  Matrix4 get _paintTransform {
    // Convert back before painting: deltas in view/Overlay coordinates are
    // not local deltas when a Navigator is translated or scaled.
    final current = localCurrentRect;
    return Matrix4.identity()
      ..translateByDouble(current.left, current.top, 0, 1)
      ..scaleByDouble(
        current.width / size.width,
        current.height / size.height,
        1,
        1,
      );
  }

  void _tick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(
    Animation<double> animation,
    Rect anchor,
    RenderBox? coordinateSpace,
  ) {
    if (_animation != animation) {
      if (attached) _animation.removeListener(_tick);
      _animation = animation;
      if (attached) _animation.addListener(_tick);
    }
    _anchor = anchor;
    _coordinateSpace = coordinateSpace;
    _tick();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_tick);
  }

  @override
  void detach() {
    _animation.removeListener(_tick);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    assert(() {
      debugLayoutCount++;
      return true;
    }());
  }

  @override
  Rect get paintBounds => (Offset.zero & size).inflate(24);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty || child == null) return;
    assert(() {
      debugPaintCount++;
      return true;
    }());
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _paintTransform,
      super.paint,
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_paintTransform);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.isEmpty || progress < .15) return false;
    return result.addWithPaintTransform(
      transform: _paintTransform,
      position: position,
      hitTest: (result, position) => super.hitTest(result, position: position),
    );
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }
}

/// The glass changes shape, but its contents are not squeezed into that shape.
/// Retained foreground layers move with the bubble and are revealed
/// by its rounded viewport. A source glyph occupies the initial button frame.
class GlassMenuContents extends MultiChildRenderObjectWidget {
  GlassMenuContents({
    super.key,
    required this.animation,
    required this.sourceSize,
    required this.sourceRadius,
    required Widget child,
    Widget source = const SizedBox.shrink(),
    this.radius = 28,
  }) : super(
         children: [
           RepaintBoundary(child: child),
           ExcludeSemantics(child: RepaintBoundary(child: source)),
         ],
       );

  final Animation<double> animation;
  final Size sourceSize;
  final double sourceRadius;
  final double radius;

  @override
  GlassMenuContentsRender createRenderObject(BuildContext context) =>
      GlassMenuContentsRender(animation, sourceSize, sourceRadius, radius);

  @override
  void updateRenderObject(
    BuildContext context,
    GlassMenuContentsRender renderObject,
  ) => renderObject.update(animation, sourceSize, sourceRadius, radius);
}

class _GlassMenuParentData extends ContainerBoxParentData<RenderBox> {}

class GlassMenuContentsRender extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GlassMenuParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GlassMenuParentData> {
  GlassMenuContentsRender(
    this._animation,
    this._sourceSize,
    this._sourceRadius,
    this._radius,
  );

  Animation<double> _animation;
  Size _sourceSize;
  double _sourceRadius;
  double _radius;
  GlassMenuStretchRender? _stretch;
  final _viewportLayer = LayerHandle<TransformLayer>();
  final _clipLayer = LayerHandle<ClipRRectLayer>();
  final _menuLayer = LayerHandle<TransformLayer>();
  final _sourceLayer = LayerHandle<TransformLayer>();
  final _menuOpacity = LayerHandle<OpacityLayer>();
  final _sourceOpacity = LayerHandle<OpacityLayer>();
  int debugLayoutCount = 0;

  double get _phase => _animation.value.clamp(0.0, 1.0);
  Size get _viewport => _stretch?.localCurrentRect.size ?? size;
  Offset get _menuOffset => Offset(
    // Keep leading labels inside the growing material. Centring a full-width
    // menu here would clip the first characters of every row until it settles.
    0,
    (_viewport.height - size.height) / 2,
  );
  Offset get _sourceOffset =>
      _stretch?.sourceOffset(_sourceSize) ?? Offset.zero;

  double get debugMenuOpacity =>
      const Interval(.06, .34, curve: Curves.easeOut).transform(_phase);
  double get debugSourceOpacity =>
      1 - const Interval(0, .22, curve: Curves.easeInOut).transform(_phase);

  Matrix4 get _unscale => Matrix4.diagonal3Values(
    size.width / _viewport.width,
    size.height / _viewport.height,
    1,
  );

  Matrix4 _foregroundTransform(Offset offset) =>
      _unscale..translateByDouble(offset.dx, offset.dy, 0, 1);

  RRect get _viewportClip => RRect.fromRectAndRadius(
    Offset.zero & _viewport,
    Radius.circular(
      math.min(
        _viewport.shortestSide / 2,
        ui.lerpDouble(
          _sourceRadius,
          _radius,
          Curves.easeOutCubic.transform(_phase),
        )!,
      ),
    ),
  );

  void _tick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(
    Animation<double> animation,
    Size sourceSize,
    double sourceRadius,
    double radius,
  ) {
    if (_animation != animation) {
      if (attached) _animation.removeListener(_tick);
      _animation = animation;
      if (attached) _animation.addListener(_tick);
    }
    if (_sourceSize != sourceSize) {
      _sourceSize = sourceSize;
      markNeedsLayout();
    }
    _sourceRadius = sourceRadius;
    _radius = radius;
    _tick();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GlassMenuParentData) {
      child.parentData = _GlassMenuParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? ancestor = parent;
    while (ancestor != null && ancestor is! GlassMenuStretchRender) {
      ancestor = ancestor.parent;
    }
    _stretch = ancestor as GlassMenuStretchRender?;
    _animation.addListener(_tick);
  }

  @override
  void detach() {
    _animation.removeListener(_tick);
    _stretch = null;
    super.detach();
  }

  @override
  void performLayout() {
    firstChild!.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(firstChild!.size);
    lastChild!.layout(BoxConstraints.tight(_sourceSize));
    assert(() {
      debugLayoutCount++;
      return true;
    }());
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(firstChild!.getDryLayout(constraints));

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty || _viewport.isEmpty) return;
    _viewportLayer.layer = context.pushTransform(true, offset, _unscale, (
      context,
      offset,
    ) {
      _clipLayer.layer = context.pushClipRRect(
        true,
        offset,
        Offset.zero & _viewport,
        _viewportClip,
        (context, offset) {
          void foreground(
            RenderBox child,
            double opacity,
            Offset translation,
            LayerHandle<OpacityLayer> opacityLayer,
            LayerHandle<TransformLayer> transformLayer,
          ) {
            final alpha = (opacity * 255).round();
            if (alpha == 0) return;
            opacityLayer.layer = context.pushOpacity(offset, alpha, (
              context,
              offset,
            ) {
              transformLayer.layer = context.pushTransform(
                true,
                offset,
                Matrix4.translationValues(translation.dx, translation.dy, 0),
                (context, offset) => context.paintChild(child, offset),
                oldLayer: transformLayer.layer,
              );
            }, oldLayer: opacityLayer.layer);
          }

          foreground(
            firstChild!,
            debugMenuOpacity,
            _menuOffset,
            _menuOpacity,
            _menuLayer,
          );
          foreground(
            lastChild!,
            debugSourceOpacity,
            _sourceOffset,
            _sourceOpacity,
            _sourceLayer,
          );
        },
        oldLayer: _clipLayer.layer,
      );
    }, oldLayer: _viewportLayer.layer);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(
        _foregroundTransform(child == firstChild ? _menuOffset : _sourceOffset),
      );

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.isEmpty || _phase < .34) return false;
    final visiblePosition = Offset(
      position.dx * _viewport.width / size.width,
      position.dy * _viewport.height / size.height,
    );
    if (!_viewportClip.contains(visiblePosition)) return false;
    return result.addWithPaintTransform(
      transform: _foregroundTransform(_menuOffset),
      position: position,
      hitTest: (result, position) =>
          firstChild!.hitTest(result, position: position),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_phase >= .34) visitor(firstChild!);
  }

  @override
  void dispose() {
    _viewportLayer.layer = null;
    _clipLayer.layer = null;
    _menuLayer.layer = null;
    _sourceLayer.layer = null;
    _menuOpacity.layer = null;
    _sourceOpacity.layer = null;
    super.dispose();
  }
}

/// Menus morph their live material; sheets retain their existing entrance.
class GlassOverlayTransition extends StatelessWidget {
  const GlassOverlayTransition({
    super.key,
    required this.animation,
    required this.kind,
    required this.child,
    this.reduceMotion = false,
    this.anchor,
    this.coordinateSpace,
  });
  final Animation<double> animation;
  final GlassOverlayKind kind;
  final Widget child;
  final bool reduceMotion;
  final Rect? anchor;
  final RenderBox? coordinateSpace;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion || MediaQuery.disableAnimationsOf(context)) return child;
    if (kind == GlassOverlayKind.menu) {
      assert(anchor != null);
      return GlassMenuStretch(
        key: const ValueKey('glass-menu-transition'),
        animation: animation,
        anchor: anchor!,
        coordinateSpace: coordinateSpace,
        // Retain the labels/selection paint, not a bitmap of the backdrop.
        // NativeBackdrop's layer still resolves the live scene on every frame.
        child: RepaintBoundary(child: child),
      );
    }
    return ArchivePlaneTransition(
      key: ValueKey('glass-${kind.name}-transition'),
      animation: animation,
      kind: ArchivePlaneKind.sheet,
      bottomClearance: MediaQuery.viewPaddingOf(context).bottom + 24,
      child: child,
    );
  }
}

/// One short clock per accepted batch, kept outside the loading/loaded branch.
/// Only the changed batch is revealed. Scroll rebuilds, failures and cached
/// route returns neither create a new clock nor replay the sequence.
class LoadedContentSequence extends StatefulWidget {
  const LoadedContentSequence({
    super.key,
    required this.generation,
    required this.child,
    this.firstIndex = 0,
  });
  final Object? generation;
  final int firstIndex;
  final Widget child;

  @override
  State<LoadedContentSequence> createState() => _LoadedContentSequenceState();
}

class _LoadedContentSequenceState extends State<LoadedContentSequence>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
    value: 1,
  )..addStatusListener(_completed);

  void _completed(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(() {});
  }

  bool get _static =>
      MediaQuery.disableAnimationsOf(context) ||
      !TickerMode.valuesOf(context).enabled;

  @override
  void didUpdateWidget(LoadedContentSequence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.generation == oldWidget.generation) return;
    if (widget.generation == null || _static) {
      _clock.value = 1;
    } else {
      _clock.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_static) _clock.value = 1;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LoadedSequenceScope(
    animation: _clock.isCompleted ? const AlwaysStoppedAnimation(1) : _clock,
    generation: widget.generation,
    firstIndex: widget.firstIndex,
    child: widget.child,
  );
}

class _LoadedSequenceScope extends InheritedWidget {
  const _LoadedSequenceScope({
    required this.animation,
    required this.generation,
    required this.firstIndex,
    required super.child,
  });
  final Animation<double> animation;
  final Object? generation;
  final int firstIndex;

  @override
  bool updateShouldNotify(_LoadedSequenceScope oldWidget) =>
      animation != oldWidget.animation ||
      generation != oldWidget.generation ||
      firstIndex != oldWidget.firstIndex;
}

/// Shares the existing top-down motion vocabulary. Delay is bounded to eight
/// bands, so long lists stay lazy and never wait seconds for offscreen rows.
class LoadedContentItem extends StatelessWidget {
  const LoadedContentItem({
    super.key,
    required this.index,
    required this.child,
    this.animation,
    this.placeholder = const LoadingSkeleton(layout: SkeletonLayout.actions),
  });
  final int index;
  final Widget child;
  final Animation<double>? animation;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final scope = animation == null
        ? context.dependOnInheritedWidgetOfExactType<_LoadedSequenceScope>()
        : null;
    final order = index - (scope?.firstIndex ?? 0);
    final clock = animation ?? scope?.animation;
    if (clock == null || order < 0) return child;
    final start = order.clamp(0, 8) * .055;
    return RevealFromTop(
      animation: clock,
      start: start,
      end: start + .52,
      placeholder: placeholder,
      child: child,
    );
  }
}

/// Small dependent controls expand in place, borrowing the page's finite
/// cut-in vocabulary. Live glass is clipped, never faded in an opacity layer.
class AnimatedOptionSection extends StatefulWidget {
  const AnimatedOptionSection({
    super.key,
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;
  @override
  State<AnimatedOptionSection> createState() => _AnimatedOptionSectionState();
}

class _AnimatedOptionSectionState extends State<AnimatedOptionSection>
    with SingleTickerProviderStateMixin {
  late final _clock =
      AnimationController(
        vsync: this,
        duration: NovelMotion.enter,
        reverseDuration: NovelMotion.exit,
        value: widget.expanded ? 1 : 0,
      )..addStatusListener((_) {
        if (mounted) setState(() {});
      });
  late final _size = _clock.drive(CurveTween(curve: NovelMotion.ease));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = widget.expanded ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(AnimatedOptionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = widget.expanded ? 1 : 0;
    } else {
      widget.expanded ? _clock.forward() : _clock.reverse();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_clock.isAnimating && _clock.value == 0
      ? const SizedBox.shrink()
      : IgnorePointer(
          ignoring: !widget.expanded,
          child: ExcludeSemantics(
            excluding: !widget.expanded,
            child: SizeTransition(
              sizeFactor: _size,
              axisAlignment: -1,
              child: RevealFromTop(animation: _clock, child: widget.child),
            ),
          ),
        );
}

class RevealFromTop extends StatelessWidget {
  const RevealFromTop({
    super.key,
    required this.animation,
    required this.child,
    this.start = 0,
    this.end = 1,
    this.axis = ArchiveRevealAxis.vertical,
    this.placeholder,
  });
  final Animation<double> animation;
  final Widget child;
  final double start;
  final double end;
  final ArchiveRevealAxis axis;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final revealed = ArchiveReveal(
      animation: animation,
      start: start,
      end: end,
      axis: axis,
      travel: axis == ArchiveRevealAxis.horizontal
          ? const Offset(-10, 0)
          : const Offset(-8, -6),
      child: child,
    );
    return placeholder == null
        ? revealed
        : LoadingHandoff(
            animation: animation,
            start: start,
            end: end,
            axis: axis == ArchiveRevealAxis.vertical
                ? Axis.vertical
                : Axis.horizontal,
            travel: axis == ArchiveRevealAxis.horizontal
                ? const Offset(-10, 0)
                : const Offset(-8, -6),
            placeholder: placeholder!,
            child: revealed,
          );
  }
}
