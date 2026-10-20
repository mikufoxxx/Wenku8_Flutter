import 'dart:async';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'library_state.dart';
import 'reader_book_layout.dart';
import 'reader_content.dart';
import 'reader_pagination.dart';
import 'reader_preferences.dart';
import 'reader_background.dart';
import 'reader_reflow.dart';
import 'reader_turn_motion.dart';
import 'reader_illustrations.dart';
import 'reader_page_anchor.dart';
import 'reader_page_physics.dart';
import 'reader_sheet_motion.dart';

TextStyle _chapterHeadingStyle(TextStyle style) => style.copyWith(
  fontSize: 13,
  height: 1.4,
  color: style.color?.withValues(alpha: .6),
);

Offset _bodyOrigin(
  BuildContext context,
  String title,
  TextStyle style,
  EdgeInsets padding,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: title, style: _chapterHeadingStyle(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: width);
  final origin = Offset(padding.left, padding.top + painter.height + 8);
  painter.dispose();
  return origin;
}

class ReaderPagedController {
  _ReaderPagedViewState? _owner;
  bool get ready => _owner?._pagination != null && _owner?._layingOut == false;
  ReaderTextAnchor? get anchor => _owner?._leaf?.anchor;
  double get fraction {
    final owner = _owner, count = owner?._spreadCount ?? 0;
    return count < 2 ? 0 : owner!._spreadFor(owner._page) / (count - 1);
  }

  int get page => _owner?._page ?? 0;
  int get pageCount => _owner?._pagination?.pages.length ?? 0;
  Size? get pageSize => _owner?._pagination?.size;
  int get pagesPerSpread => _owner?._bookLayout?.count ?? 1;
  List<int> get visiblePages => _owner?._visiblePages ?? const [];
  @visibleForTesting
  int get debugLayoutGeneration => _owner?._generation ?? 0;
  @visibleForTesting
  int get debugParagraphMeasurements =>
      _owner?._textLayout.paragraphMeasurements ?? 0;
  @visibleForTesting
  ReaderLeaf? get debugLeaf => _owner?._leaf;
  @visibleForTesting
  ReaderBookLayout? get debugBookLayout => _owner?._bookLayout;
  @visibleForTesting
  ReaderTextAnchor? get debugFirstVisibleAnchor {
    final owner = _owner;
    if (owner == null || owner._visiblePages.isEmpty) return null;
    return owner._firstVisibleAnchor;
  }

  bool pageBy(int direction) {
    final owner = _owner;
    if (owner == null || !ready) return false;
    final spread = owner._spreadFor(owner._target) + direction;
    if (spread < 0 || spread >= owner._spreadCount) return false;
    final target = (spread * pagesPerSpread - owner._leadingPages).clamp(
      0,
      pageCount - 1,
    );
    owner._move(target, animate: true);
    return true;
  }

  void seek(double fraction) {
    if (!ready) return;
    final owner = _owner!;
    owner._pendingFraction = fraction.clamp(0, 1);
    owner._move(
      owner._pendingFraction == 1
          ? pageCount - 1
          : (owner._pendingFraction! * (owner._spreadCount - 1)).round() *
                    pagesPerSpread -
                owner._leadingPages,
    );
    // Keep the requested fraction through any coalesced viewport reflow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (owner.mounted && !owner._layingOut) owner._pendingFraction = null;
    });
  }

  void restore(ReadingPosition position) => _owner?._restore(position);
  void reveal(ReaderTextAnchor anchor) {
    final owner = _owner;
    if (owner?._pagination != null) {
      owner!._pendingFraction = null;
      owner._pendingAnchor = anchor;
      owner._move(owner._pagination!.pageFor(anchor), animate: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (owner.mounted && !owner._layingOut) owner._pendingAnchor = null;
      });
    }
  }
}

class ReaderPageSkeleton extends StatelessWidget {
  const ReaderPageSkeleton({
    super.key,
    required this.title,
    required this.padding,
    required this.style,
    required this.vertical,
    this.margin = 26,
  });
  final String title;
  final EdgeInsets padding;
  final TextStyle style;
  final bool vertical;
  final double margin;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _chapterHeadingStyle(style),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = ReaderBookLayout.resolve(
                viewport: constraints.biggest,
                margin: margin,
                features: MediaQuery.displayFeaturesOf(context),
                origin: _bodyOrigin(
                  context,
                  title,
                  style,
                  padding,
                  constraints.maxWidth,
                ),
              );
              return ReaderBookSpread(
                layout: layout,
                rightToLeft: vertical,
                pages: [
                  for (var i = 0; i < layout.count; i++)
                    ReaderSkeleton(vertical: vertical, expand: true),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ReaderPagedView extends StatefulWidget {
  const ReaderPagedView({
    super.key,
    required this.content,
    required this.preferences,
    required this.style,
    required this.controller,
    required this.title,
    required this.padding,
    required this.pageBuilder,
    required this.onReady,
    required this.onChanged,
    required this.onUserScroll,
    required this.onBoundary,
    this.position,
    this.reduceMotion = false,
    this.showPageCount = true,
  });
  final ReaderContent content;
  final ReaderPreferences preferences;
  final TextStyle style;
  final ReaderPagedController controller;
  final String title;
  final EdgeInsets padding;
  final Widget Function(ReaderLeaf page) pageBuilder;
  final VoidCallback onReady, onChanged, onUserScroll;
  final ValueChanged<int> onBoundary;
  final ReadingPosition? position;
  final bool reduceMotion;
  final bool showPageCount;
  @override
  State<ReaderPagedView> createState() => _ReaderPagedViewState();
}

class _ReaderPagedViewState extends State<ReaderPagedView>
    with TickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: ReaderTurnScope.duration,
    value: 1,
  );
  bool _programmaticTurn = false;
  int? _turnSpread, _swipeOrigin;
  double _turnDirection = 1;
  late final _arrival =
      AnimationController(vsync: this, duration: NovelMotion.enter, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              (_previousPage != null ||
                  _previousSize != null ||
                  _initialArrival)) {
            setState(() {
              _previousPage = null;
              _previousSize = null;
              _previousLeaves = const [];
              _previousLeafSize = null;
              _initialArrival = false;
              _modeReconfiguration = false;
            });
          }
        });
  Widget? _previousPage;
  Size? _previousSize;
  Size? _previousLeafSize;
  List<ReaderLeaf> _previousLeaves = const [];
  ReaderBookLayout? _bookLayout;
  bool _bookReconfiguration = false;
  bool _modeReconfiguration = false;
  double _modeDirection = 1;
  ReaderMode? _publishedMode;
  Offset _originDelta = Offset.zero;
  EdgeInsets? _publishedPadding;
  TextStyle? _publishedStyle;
  late TextStyle _layoutStyle;
  Object? _publishedPreferences;
  bool _initialArrival = false;
  ReaderPagination? _pagination;
  PageController? _pager;
  Object? _layoutKey;
  ReadingPosition? _pendingPosition;
  ReaderTextAnchor? _pendingAnchor;
  double? _pendingFraction;
  int _generation = 0, _page = 0, _target = 0;
  int _leadingPages = 0;
  double _overscroll = 0;
  bool _crossedBoundary = false;
  bool _layoutFailed = false;
  bool _layingOut = false;
  final _pageBodies = <int, Widget>{};
  final _textLayout = ReaderTextLayoutCache();
  ReaderLeaf? get _leaf => _pagination?.pages[_page];
  bool get _motionEnabled =>
      !widget.reduceMotion && !MediaQuery.disableAnimationsOf(context);
  ReaderPageEffect get _effect =>
      _motionEnabled ? widget.preferences.pageEffect : ReaderPageEffect.none;
  EdgeInsets get _pageInsets => EdgeInsets.only(
    left: (_publishedPadding ?? widget.padding).left,
    right: (_publishedPadding ?? widget.padding).right,
  );
  Size get _frameSize => Size(
    _bookLayout!.viewport.width + _pageInsets.horizontal,
    _bookLayout!.viewport.height,
  );
  int get _perSpread => _bookLayout?.count ?? 1;
  double get _reflowOverflow =>
      _previousSize == null || _bookReconfiguration || _modeReconfiguration
      ? 0
      : ((_previousLeafSize?.height ?? 0) - (_pagination?.size.height ?? 0))
                .clamp(0.0, double.infinity) +
            _originDelta.dy.abs();
  int get _spreadCount =>
      (((_pagination?.pages.length ?? 0) + _leadingPages) / _perSpread).ceil();
  int _spreadFor(int page) => (page + _leadingPages) ~/ _perSpread;
  List<int> get _visiblePages {
    final first = _spreadFor(_page) * _perSpread - _leadingPages;
    return [
      for (var i = first; i < first + _perSpread; i++)
        if (i >= 0 && i < (_pagination?.pages.length ?? 0)) i,
    ];
  }

  ReaderTextAnchor? get _firstVisibleAnchor => _visiblePages.isEmpty
      ? null
      : _pagination!.pages[_visiblePages.first].anchor;

  @override
  void initState() {
    super.initState();
    widget.controller._owner = this;
    _layoutStyle = widget.style;
    _pendingPosition = widget.position;
  }

  @override
  void didUpdateWidget(ReaderPagedView old) {
    super.didUpdateWidget(old);
    final styleLayout =
        old.style.compareTo(widget.style) == RenderComparison.layout;
    if (styleLayout) _layoutStyle = widget.style;
    final reflow =
        styleLayout ||
        old.preferences.layoutKey != widget.preferences.layoutKey ||
        old.padding != widget.padding ||
        !identical(old.content, widget.content);
    if ((old.pageBuilder != widget.pageBuilder || old.style != widget.style) &&
        !reflow) {
      _pageBodies.clear();
    }
    if (old.controller != widget.controller) {
      old.controller._owner = null;
      widget.controller._owner = this;
    }
    if (!identical(old.content, widget.content)) {
      _pendingAnchor = null;
      _pendingPosition = widget.position;
    } else if (!identical(old.position, widget.position) &&
        widget.position != null) {
      _restore(widget.position!);
    }
  }

  @override
  void dispose() {
    _generation++;
    if (widget.controller._owner == this) widget.controller._owner = null;
    _pager?.dispose();
    _arrival.dispose();
    _turn.dispose();
    super.dispose();
  }

  ReaderTextAnchor? _anchorFor(ReadingPosition? position) {
    if (position == null || position.paragraphIndex == null) return null;
    final paragraph = position.paragraphIndex!;
    if (paragraph < 0 || paragraph >= widget.content.paragraphs.length) {
      return null;
    }
    final text = widget.content.paragraphs[paragraph];
    return ReaderTextAnchor(
      paragraph,
      (position.textOffset ??
              (position.paragraphFraction * text.length).round())
          .clamp(0, text.length),
    );
  }

  void _restore(ReadingPosition position) {
    _pendingFraction = null;
    _pendingPosition = position;
    final layout = _pagination;
    if (layout == null) return;
    final anchor = _anchorFor(position);
    _move(
      anchor == null
          ? position.fraction == 1
                ? layout.pages.length - 1
                : (position.fraction * (_spreadCount - 1)).round() *
                          _perSpread -
                      _leadingPages
          : layout.pageFor(anchor),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  void _move(int page, {bool animate = false}) {
    final pager = _pager;
    if (_pagination == null || pager == null) return;
    final previousPage = _page;
    _target = page.clamp(0, _pagination!.pages.length - 1);
    if (!pager.hasClients) return;
    final destination = _spreadFor(_target);
    final current = pager.page ?? _spreadFor(previousPage).toDouble();
    if ((destination - current).abs() < .00001) {
      if (!animate) {
        _programmaticTurn = false;
        _turn.stop();
        _turn.value = 1;
      }
      setState(() {
        _page = _target;
        if (!animate) {
          _turnSpread = null;
          _swipeOrigin = null;
        }
      });
      widget.onChanged();
      return;
    }
    if (animate && _effect != ReaderPageEffect.none) {
      setState(() {
        _swipeOrigin ??= current.round();
        _programmaticTurn = true;
      });
      // Keep both existing leaves mounted. No duplicate outgoing text tree,
      // reshaping the current spread, or independent drag/animation clock.
      unawaited(
        pager.animateToPage(
          destination,
          duration: _effect.duration,
          curve: Curves.linear,
        ),
      );
    } else {
      _programmaticTurn = false;
      _turn.stop();
      _swipeOrigin = null;
      _turn.value = 1;
      setState(() {
        _turnSpread = null;
      });
      pager.jumpToPage(destination);
    }
  }

  void _scrubTurn(PageMetrics metrics) {
    final origin = _swipeOrigin, position = metrics.page;
    if (origin == null ||
        position == null ||
        _effect == ReaderPageEffect.none) {
      return;
    }
    final delta = position - origin;
    if (delta.abs() < .00001) {
      _turn.value = 0;
      return;
    }
    final forward = delta > 0;
    final incoming = (forward ? position.ceil() : position.floor()).clamp(
      0,
      _spreadCount - 1,
    );
    final progress = forward
        ? position - incoming + 1
        : incoming + 1 - position;
    final direction =
        (forward ? 1.0 : -1.0) *
        (widget.preferences.mode == ReaderMode.vertical ? -1 : 1);
    if (_turnSpread != incoming || _turnDirection != direction) {
      setState(() {
        _turnSpread = incoming;
        _turnDirection = direction;
      });
    }
    _turn.value = progress.clamp(0.0, 1.0);
  }

  Future<void> _layout(ReaderBookLayout bookLayout, TextScaler scaler) async {
    final size = bookLayout.pageSize;
    final ticket = ++_generation;
    final content = widget.content;
    final preferences = widget.preferences;
    final style = widget.style;
    final padding = widget.padding;
    final oldAnchor = _pendingAnchor ?? _firstVisibleAnchor;
    final preserveStart =
        _pagination != null &&
        _pagination!.size != size &&
        _pagination!.size.width == size.width &&
        _publishedStyle?.compareTo(style) != RenderComparison.layout &&
        _publishedPreferences == preferences.layoutKey &&
        _pendingPosition == null &&
        _pendingFraction == null;
    // Keep the last fully laid-out page while a slider previews the next
    // typography. Replacing it with skeletons on every drag tick flickers and
    // hides the very text the transparent settings panel is meant to preview.
    _layingOut = true;
    _layoutFailed = false;
    ReaderPagination? result;
    try {
      final imageSizes = await ReaderIllustrationCache.shared
          .measureLocalImages(
            content.illustrations,
            current: () => mounted && ticket == _generation,
          );
      if (!mounted || ticket != _generation) return;
      result = await paginateReader(
        content: content,
        size: size,
        style: _layoutStyle,
        preferences: preferences,
        scaler: scaler,
        current: () => mounted && ticket == _generation,
        pageBreak: preserveStart ? oldAnchor : null,
        cache: _textLayout,
        localImageSizes: imageSizes,
      );
    } catch (_) {
      if (mounted && ticket == _generation) {
        setState(() {
          _layoutFailed = true;
          _layingOut = false;
        });
      }
      return;
    }
    if (!mounted || ticket != _generation || result == null) return;
    final position = _pendingPosition;
    final anchor = _anchorFor(position) ?? _pendingAnchor ?? oldAnchor;
    final anchorPage = anchor == null ? null : result.pageFor(anchor);
    // Keep the visible spread's first source anchor on the same leaf after a
    // height change. Prefix pages may now be odd; align the book at its start,
    // rather than jumping the current paragraph across the spine.
    final leadingPages = preserveStart && anchorPage != null
        ? (bookLayout.count - anchorPage % bookLayout.count) % bookLayout.count
        : 0;
    final spreadCount =
        ((result.pages.length + leadingPages) / bookLayout.count).ceil();
    final page = _pendingFraction != null
        ? _pendingFraction == 1
              ? result.pages.length - 1
              : (_pendingFraction! * (spreadCount - 1)).round() *
                        bookLayout.count -
                    leadingPages
        : anchor != null
        ? anchorPage!
        : position?.fraction == 1
        ? result.pages.length - 1
        : ((position?.fraction ?? 0) * (spreadCount - 1)).round() *
                  bookLayout.count -
              leadingPages;
    final oldPager = _pager;
    final firstLayout = _pagination == null;
    final viewportChanged =
        _pagination != null && _bookLayout?.key != bookLayout.key;
    final modeChanged =
        _publishedMode != null && _publishedMode != preferences.mode;
    final bookReconfiguration =
        viewportChanged &&
        (_bookLayout?.count != bookLayout.count ||
            _pagination?.size.width != result.size.width);
    final animate =
        !widget.reduceMotion && !MediaQuery.disableAnimationsOf(context);
    final modeDirection = (_publishedMode?.index ?? 0) < preferences.mode.index
        ? 1.0
        : -1.0;
    Widget? previous = animate && (bookReconfiguration || modeChanged)
        ? _spreadBody(
            _spreadFor(_page),
            reflow: false,
            turn: false,
            mode: _publishedMode,
          )
        : null;
    if (previous != null && modeChanged) {
      previous = ReaderTurnScope(
        animation: _arrival,
        direction: modeDirection,
        outgoing: true,
        child: previous,
      );
    }
    final previousSize = _bookLayout == null ? null : _frameSize;
    final previousLeafSize = _pagination?.size;
    final previousLeaves = [
      for (final i in _visiblePages) _pagination!.pages[i],
    ];
    final previousPadding = _publishedPadding ?? padding;
    _turn.stop();
    _swipeOrigin = null;
    _programmaticTurn = false;
    setState(() {
      _turnSpread = null;
      _pagination = result;
      _previousPage = previous;
      _previousSize = animate && viewportChanged ? previousSize : null;
      _previousLeafSize = animate && viewportChanged ? previousLeafSize : null;
      _previousLeaves = animate && viewportChanged ? previousLeaves : const [];
      _bookReconfiguration = bookReconfiguration;
      _modeReconfiguration = modeChanged && animate;
      _modeDirection = modeDirection;
      _bookLayout = bookLayout;
      _leadingPages = leadingPages;
      _originDelta = Offset(0, previousPadding.top - padding.top);
      _publishedPadding = padding;
      _publishedStyle = style;
      _publishedPreferences = preferences.layoutKey;
      _publishedMode = preferences.mode;
      _initialArrival = firstLayout && animate;
      _layingOut = false;
      _pageBodies.clear();
      _page = _target = page;
      _pager = PageController(initialPage: _spreadFor(page));
      _pendingAnchor = null;
      _pendingPosition = null;
      _pendingFraction = null;
    });
    if ((firstLayout || viewportChanged || modeChanged) && animate) {
      _arrival.forward(from: 0);
    } else {
      _arrival.value = 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldPager?.dispose();
      if (mounted && ticket == _generation) {
        widget.onReady();
        widget.onChanged();
      }
    });
  }

  Widget _spreadBody(
    int spread, {
    bool reflow = true,
    bool turn = true,
    ReaderMode? mode,
  }) {
    final pagination = _pagination!, layout = _bookLayout!;
    final first = spread * layout.count - _leadingPages;
    final pages = <Widget>[];
    for (var slot = 0; slot < layout.count; slot++) {
      final index = first + slot;
      if (index < 0) {
        pages.add(const SizedBox.shrink());
        continue;
      }
      if (index >= pagination.pages.length) break;
      final body = _pageBodies.putIfAbsent(
        index,
        () =>
            RepaintBoundary(child: widget.pageBuilder(pagination.pages[index])),
      );
      Widget page =
          reflow &&
              spread == _spreadFor(_page) &&
              spread != _turnSpread &&
              !_bookReconfiguration &&
              slot < _previousLeaves.length &&
              _previousLeafSize != null
          ? ReaderReflowScope(
              animation: _arrival,
              previous: _previousLeaves[slot],
              size: pagination.size,
              previousSize: _previousLeafSize!,
              originDelta: _originDelta,
              child: body,
            )
          : body;
      final entering =
          (_initialArrival || _modeReconfiguration) &&
          spread == _spreadFor(_page);
      final outgoing =
          _swipeOrigin != null &&
          spread == _swipeOrigin &&
          spread != _turnSpread &&
          _turnSpread != null;
      final showPlaceholder =
          turn && _initialArrival && spread == _spreadFor(_page);
      final skeleton = <Widget>[];
      if (showPlaceholder) {
        final leaf = pagination.pages[index];
        final vertical = widget.preferences.mode == ReaderMode.vertical;
        final divisions = vertical
            ? (leaf.glyphs
                  .map((g) => pagination.size.width - g.rect.right)
                  .toSet()
                  .toList()
                ..sort())
            : leaf.fragments.map((f) => f.rect.top).toList();
        skeleton.add(
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ReaderTurnPlaceholder(
                  divisions: divisions,
                  vertical: vertical,
                  child: ReaderSkeleton(vertical: vertical, expand: true),
                ),
              ),
            ),
          ),
        );
      }
      // Keep the retained article under the same parent when its skeleton
      // finishes; selection/render caches must not remount at the handoff.
      page = Stack(
        fit: StackFit.expand,
        children: [
          ...skeleton,
          KeyedSubtree(
            key: ValueKey('reader-retained-leaf-$index'),
            child: page,
          ),
        ],
      );
      page = ReaderTurnScope(
        animation: entering ? _arrival : _turn,
        direction: entering
            ? (_modeReconfiguration
                  ? _modeDirection
                  : widget.preferences.mode == ReaderMode.vertical
                  ? -1
                  : 1)
            : _turnDirection,
        enabled:
            turn &&
            (entering ||
                _effect == ReaderPageEffect.staggered &&
                    (spread == _turnSpread || outgoing)),
        outgoing: outgoing,
        relay: !entering && (outgoing || spread == _turnSpread),
        vertical:
            (_publishedMode ?? widget.preferences.mode) == ReaderMode.vertical,
        leafSize: pagination.size,
        slot: slot,
        slots: layout.count,
        child: page,
      );
      pages.add(page);
    }
    return Padding(
      key: ValueKey('reader-page-frame-$spread'),
      padding: _pageInsets,
      child: ReaderBookSpread(
        key: ValueKey('reader-book-spread-$spread'),
        layout: layout,
        verticalOverflow: _reflowOverflow,
        rightToLeft:
            (mode ?? _publishedMode ?? widget.preferences.mode) ==
            ReaderMode.vertical,
        pages: pages,
      ),
    );
  }

  Widget _edgeText(Widget child) => AnimatedBuilder(
    animation: _arrival,
    child: child,
    builder: (context, child) {
      final published = _publishedPadding;
      final pending = published != null && published != widget.padding;
      final delta = pending
          ? published.top - widget.padding.top
          : _previousSize == null
          ? 0.0
          : _originDelta.dy *
                (1 - Curves.easeOutCubic.transform(_arrival.value));
      return Transform.translate(offset: Offset(0, delta), child: child);
    },
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: widget.padding.top,
      bottom: widget.padding.bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _edgeText(
          SelectionContainer.disabled(
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.padding.left,
                right: widget.padding.right,
              ),
              child: Row(
                key: const ValueKey('reader-chapter-location'),
                children: [
                  Expanded(
                    child: AppText(
                      widget.title,
                      key: const ValueKey('reader-chapter-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _chapterHeadingStyle(widget.style),
                    ),
                  ),
                  if (widget.showPageCount) ...[
                    const SizedBox(width: 12),
                    AppText(
                      _pagination == null
                          ? ''
                          : _perSpread == 1
                          ? '${_page + 1}/${_pagination!.pages.length}页'
                          : '${_visiblePages.first + 1}–${_visiblePages.last + 1}/${_pagination!.pages.length}页',
                      key: const ValueKey('reader-page-count'),
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: widget.style.copyWith(
                        fontSize: 11,
                        height: 1.3,
                        color: widget.style.color?.withValues(alpha: .55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final bookLayout = ReaderBookLayout.resolve(
                viewport: Size(
                  (size.width - widget.padding.horizontal).clamp(
                    1,
                    double.infinity,
                  ),
                  size.height,
                ),
                margin: widget.preferences.bindingMargin,
                features: MediaQuery.displayFeaturesOf(context),
                origin: _bodyOrigin(
                  context,
                  widget.title,
                  widget.style,
                  widget.padding,
                  (size.width - widget.padding.horizontal).clamp(
                    1,
                    double.infinity,
                  ),
                ),
              );
              final scaler = MediaQuery.textScalerOf(context);
              final key = (
                widget.content,
                bookLayout.key,
                _layoutStyle,
                widget.preferences.layoutKey,
                scaler.scale(widget.style.fontSize ?? 19),
              );
              if (_layoutKey != key) {
                _pendingAnchor ??= _firstVisibleAnchor;
                _layoutKey = key;
                unawaited(_layout(bookLayout, scaler));
              }
              final pagination = _pagination;
              if (_layoutFailed) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppText('本章排版失败'),
                      GlassTextButton(
                        key: const ValueKey('reader-pagination-retry'),
                        onPressed: () => setState(() => _layoutKey = null),
                        child: const AppText('重试'),
                      ),
                    ],
                  ),
                );
              }
              if (pagination == null) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: widget.padding.left,
                    right: widget.padding.right,
                  ),
                  child: ReaderBookSpread(
                    layout: bookLayout,
                    rightToLeft: widget.preferences.mode == ReaderMode.vertical,
                    pages: [
                      for (var i = 0; i < bookLayout.count; i++)
                        ReaderSkeleton(
                          vertical:
                              widget.preferences.mode == ReaderMode.vertical,
                          expand: true,
                        ),
                    ],
                  ),
                );
              }
              final pendingViewport =
                  _layingOut && _bookLayout!.key != bookLayout.key;
              final previousPadding = _publishedPadding ?? widget.padding;
              final pendingDelta = Offset(
                0,
                previousPadding.top - widget.padding.top,
              );
              final pageView = NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth != 0) return false;
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _turn.stop();
                    setState(() {
                      _turnSpread = null;
                      _swipeOrigin = _spreadFor(_page);
                      _programmaticTurn = false;
                    });
                    _overscroll = 0;
                    _crossedBoundary = false;
                    _target = _page;
                    widget.onUserScroll();
                  }
                  if (notification is ScrollUpdateNotification &&
                      notification.metrics is PageMetrics) {
                    _scrubTurn(notification.metrics as PageMetrics);
                  }
                  if (notification is ScrollEndNotification &&
                      _swipeOrigin != null) {
                    setState(() {
                      _swipeOrigin = null;
                      _programmaticTurn = false;
                      _target = _page;
                      _turn.value = 1;
                      _turnSpread = null;
                    });
                  }
                  if (notification is OverscrollNotification &&
                      notification.dragDetails != null &&
                      !_crossedBoundary) {
                    _overscroll += notification.overscroll;
                    if (_overscroll.abs() > 36) {
                      _crossedBoundary = true;
                      widget.onBoundary(_overscroll > 0 ? 1 : -1);
                    }
                  }
                  return false;
                },
                child: PageView.builder(
                  key: GlobalObjectKey(pagination),
                  controller: _pager,
                  reverse:
                      (_publishedMode ?? widget.preferences.mode) ==
                      ReaderMode.vertical,
                  clipBehavior: Clip.none,
                  pageSnapping: false,
                  physics: ReaderPagePhysics(
                    // The short-stroke limit belongs to finger gestures. A
                    // follow/bookmark landing can cross several spreads; its
                    // final ballistic phase must not snap back to origin + 1.
                    origin: () => _programmaticTurn ? null : _swipeOrigin,
                    parent: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                  ),
                  itemCount: _spreadCount,
                  onPageChanged: (value) {
                    setState(() {
                      _page = _spreadFor(_target) == value
                          ? _target
                          : (value * _perSpread - _leadingPages).clamp(
                              0,
                              _pagination!.pages.length - 1,
                            );
                      if (!_programmaticTurn) _target = _page;
                    });
                    _pageBodies.removeWhere(
                      (index, _) => (_spreadFor(index) - value).abs() > 1,
                    );
                    widget.onChanged();
                  },
                  itemBuilder: (context, index) {
                    final content = _spreadBody(index);
                    final body = widget.preferences.backgroundImage == null
                        ? content
                        : ReaderBackgroundSurface(
                            preferences: widget.preferences,
                            paper: widget.preferences.background(
                              Theme.of(context).brightness == Brightness.dark,
                            ),
                            child: content,
                          );
                    final incoming = index == _turnSpread;
                    final turning = _swipeOrigin != null && _turnSpread != null;
                    final visible =
                        _effect == ReaderPageEffect.none || _swipeOrigin == null
                        ? index == _spreadFor(_page)
                        : index == _swipeOrigin || incoming;
                    final sheet =
                        _effect == ReaderPageEffect.cover ||
                            _effect == ReaderPageEffect.paper
                        ? ReaderSheetMotion(
                            animation: _turn,
                            effect: _effect,
                            direction: _turnDirection,
                            incoming: incoming,
                            front:
                                incoming ==
                                ((_turnSpread ?? 0) > (_swipeOrigin ?? 0)),
                            active: turning,
                            paper: widget.preferences.background(
                              Theme.of(context).brightness == Brightness.dark,
                            ),
                            child: body,
                          )
                        : body;
                    final anchored = _effect == ReaderPageEffect.slide
                        ? body
                        : ReaderPageAnchor(
                            offset: Scrollable.of(context).position,
                            index: index,
                            reverse:
                                (_publishedMode ?? widget.preferences.mode) ==
                                ReaderMode.vertical,
                            visible: visible,
                            child: sheet,
                          );
                    return ExcludeSemantics(
                      excluding: index != _spreadFor(_page),
                      child: ReaderPageSelection(
                        enabled: index == _spreadFor(_page),
                        child: anchored,
                      ),
                    );
                  },
                ),
              );
              final turning = KeyedSubtree(
                key: const ValueKey('reader-turn-incoming'),
                child: ClipRect(
                  clipper: ReaderPageMarginClipper(
                    _pageInsets,
                    verticalOverflow: _reflowOverflow,
                  ),
                  child: pageView,
                ),
              );
              final reconfigured = _modeReconfiguration && _previousPage != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          child: ExcludeSemantics(
                            child: SelectionContainer.disabled(
                              child: KeyedSubtree(
                                key: const ValueKey('reader-mode-outgoing'),
                                child: _previousPage!,
                              ),
                            ),
                          ),
                        ),
                        ReaderTurnScope(
                          key: const ValueKey('reader-mode-incoming'),
                          animation: _arrival,
                          direction: _modeDirection,
                          child: turning,
                        ),
                      ],
                    )
                  : _bookReconfiguration && _previousPage != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          child: ExcludeSemantics(
                            child: SelectionContainer.disabled(
                              child: ArchivePlaneTransition(
                                key: const ValueKey('reader-book-outgoing'),
                                animation: _arrival,
                                kind: ArchivePlaneKind.outgoing,
                                child: OverflowBox(
                                  alignment: Alignment.topLeft,
                                  minWidth: _previousSize!.width,
                                  maxWidth: _previousSize!.width,
                                  minHeight: _previousSize!.height,
                                  maxHeight: _previousSize!.height,
                                  child: _previousPage!,
                                ),
                              ),
                            ),
                          ),
                        ),
                        ArchivePlaneTransition(
                          key: const ValueKey('reader-book-incoming'),
                          animation: _arrival,
                          child: ReaderBackgroundSurface(
                            preferences: widget.preferences,
                            paper: widget.preferences.background(
                              Theme.of(context).brightness == Brightness.dark,
                            ),
                            child: turning,
                          ),
                        ),
                      ],
                    )
                  : turning;
              final viewport = ReaderIncrementalViewport(
                key: const ValueKey('reader-incremental-viewport'),
                animation: pendingViewport
                    ? const AlwaysStoppedAnimation(0)
                    : _previousSize == null
                    ? const AlwaysStoppedAnimation(1)
                    : _arrival,
                fromSize: pendingViewport ? _frameSize : _previousSize ?? size,
                toSize: size,
                originDelta: pendingViewport
                    ? pendingDelta
                    : _previousSize == null
                    ? Offset.zero
                    : _originDelta,
                // Each paragraph/vertical column owns its outgoing ink. A
                // second full-page tail paints the same glyphs twice while
                // the viewport shrinks, darkening them for one transition.
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: _frameSize.width,
                  maxWidth: _frameSize.width,
                  minHeight: _frameSize.height,
                  maxHeight: _frameSize.height,
                  child: reconfigured,
                ),
              );
              return viewport;
            },
          ),
        ),
      ],
    ),
  );
}
