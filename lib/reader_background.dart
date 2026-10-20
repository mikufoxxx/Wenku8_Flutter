import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'reader_preferences.dart';

class ReaderBackgroundStore {
  ReaderBackgroundStore({Directory? directory}) : _directory = directory;
  static const maxBytes = 32 * 1024 * 1024;
  static const maxDimension = 2048;
  Directory? _directory;
  Future<void> _operations = Future.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Directory> _root() async => _directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-backgrounds',
  );

  Future<File?> fileFor(String? id) async {
    if (!validReaderBackground(id)) return null;
    try {
      final file = File('${(await _root()).path}/$id.png');
      return await file.exists() ? file : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<String> importFile(String path) => _serialize(() => _importFile(path));

  Future<String> _importFile(String path) async {
    final source = File(path);
    final length = await source.length();
    if (length == 0 || length > maxBytes) {
      throw const FormatException('请选择 32 MiB 以内的图片');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length > maxBytes) throw const FormatException('图片超过 32 MiB');
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > 64 * 1024 * 1024) {
        throw const FormatException('图片尺寸过大，请选择 6400 万像素以内的图片');
      }
      final scale = math.min(
        1.0,
        maxDimension / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw const FormatException('无法读取这张图片');
      final normalized = encoded.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
      final id = 'background_${sha256.convert(normalized)}';
      final root = await _root();
      await root.create(recursive: true);
      final target = File('${root.path}/$id.png');
      if (!await target.exists()) {
        final temporary = File('${target.path}.part');
        try {
          await temporary.writeAsBytes(normalized, flush: true);
          await temporary.rename(target.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }
      return id;
    } on FormatException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (_) {
      throw const FormatException('图片无法解码，请选择有效的 JPG、PNG 或 WebP 图片');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<void> remove(String? id) => _serialize(() async {
    final file = await fileFor(id);
    if (file != null) {
      await FileImage(file).evict();
      await file.delete();
    }
  });
}

class ReaderBackgroundScope extends InheritedWidget {
  const ReaderBackgroundScope({
    super.key,
    required this.store,
    required super.child,
  });
  final ReaderBackgroundStore store;
  static ReaderBackgroundStore? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReaderBackgroundScope>()
      ?.store;
  @override
  bool updateShouldNotify(ReaderBackgroundScope oldWidget) =>
      store != oldWidget.store;
}

/// A stationary, bounded image layer, independent of text layout and gestures.
class ReaderBackgroundSurface extends StatefulWidget {
  const ReaderBackgroundSurface({
    super.key,
    required this.preferences,
    required this.paper,
    required this.child,
    this.store,
  });
  final ReaderPreferences preferences;
  final Color paper;
  final Widget child;
  final ReaderBackgroundStore? store;
  @override
  State<ReaderBackgroundSurface> createState() =>
      _ReaderBackgroundSurfaceState();
}

class _ReaderBackgroundSurfaceState extends State<ReaderBackgroundSurface> {
  final _canvasKey = GlobalKey();
  String? _id;
  ReaderBackgroundStore? _store;
  Future<File?>? _file;
  @override
  Widget build(BuildContext context) {
    final store = widget.store ?? ReaderBackgroundScope.maybeOf(context);
    final id = widget.preferences.backgroundImage;
    if (id != _id || store != _store) {
      _id = id;
      _store = store;
      _file = id == null ? null : store?.fileFor(id);
    }
    if (id == null) return ColoredBox(color: widget.paper, child: widget.child);
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_BackgroundCanvas>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = inherited?.size ?? constraints.biggest;
        final background = FutureBuilder<File?>(
          future: _file,
          builder: (context, snapshot) => snapshot.data == null
              ? const SizedBox.shrink()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      snapshot.data!,
                      fit: widget.preferences.backgroundFit.fit,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    ColoredBox(
                      color: widget.paper.withValues(
                        alpha: widget.preferences.backgroundOverlay,
                      ),
                    ),
                  ],
                ),
        );
        final surface = ColoredBox(
          key: inherited == null ? _canvasKey : null,
          color: widget.paper,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (_file != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: RepaintBoundary(
                        child: inherited == null
                            ? background
                            : _BackgroundSlice(
                                anchor: inherited.anchor,
                                canvasSize: canvasSize,
                                child: background,
                              ),
                      ),
                    ),
                  ),
                ),
              widget.child,
            ],
          ),
        );
        return inherited == null
            ? _BackgroundCanvas(
                anchor: _canvasKey,
                size: canvasSize,
                child: surface,
              )
            : surface;
      },
    );
  }
}

class _BackgroundCanvas extends InheritedWidget {
  const _BackgroundCanvas({
    required this.anchor,
    required this.size,
    required super.child,
  });
  final GlobalKey anchor;
  final Size size;
  @override
  bool updateShouldNotify(_BackgroundCanvas oldWidget) =>
      anchor != oldWidget.anchor || size != oldWidget.size;
}

/// Moving/reconfigured pages use a crop of the same full reader canvas. Fitting
/// the image to each inset page independently would create seams at its edges.
class _BackgroundSlice extends SingleChildRenderObjectWidget {
  const _BackgroundSlice({
    required this.anchor,
    required this.canvasSize,
    required super.child,
  });
  final GlobalKey anchor;
  final Size canvasSize;
  @override
  _BackgroundSliceRender createRenderObject(BuildContext context) =>
      _BackgroundSliceRender(anchor, canvasSize);
  @override
  void updateRenderObject(
    BuildContext context,
    _BackgroundSliceRender renderObject,
  ) => renderObject.update(anchor, canvasSize);
}

class _BackgroundSliceRender extends RenderProxyBox {
  _BackgroundSliceRender(this.anchor, this.canvasSize);
  GlobalKey anchor;
  Size canvasSize;
  void update(GlobalKey nextAnchor, Size nextSize) {
    if (canvasSize != nextSize) {
      canvasSize = nextSize;
      markNeedsLayout();
    }
    anchor = nextAnchor;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(BoxConstraints.tight(canvasSize));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final viewport = anchor.currentContext?.findRenderObject();
    if (child == null || viewport is! RenderBox || !viewport.attached) return;
    final translation = getTransformTo(viewport).getTranslation();
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      context.paintChild(child!, offset - Offset(translation.x, translation.y));
    });
  }
}
