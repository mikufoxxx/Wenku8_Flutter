import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'local_platform.dart';
import 'reader_preferences.dart';
import 'font_settings_page.dart';
import 'background_settings_page.dart';
import 'glass_choices.dart';
import 'setting_menu.dart';

sealed class ReaderToolAction {
  const ReaderToolAction();
}

class ReaderSeekProgress extends ReaderToolAction {
  const ReaderSeekProgress(this.fraction);
  final double fraction;
}

class ReaderOpenBookmark extends ReaderToolAction {
  const ReaderOpenBookmark(this.bookmark);
  final ReaderBookmark bookmark;
}

class ReaderEnterFocus extends ReaderToolAction {
  const ReaderEnterFocus();
}

class ReaderOpenFind extends ReaderToolAction {
  const ReaderOpenFind();
}

class ReaderStartAutoScroll extends ReaderToolAction {
  const ReaderStartAutoScroll();
}

class ReaderOpenIllustrations extends ReaderToolAction {
  const ReaderOpenIllustrations();
}

/// The chapter drawer owns scrubbing and text navigation; settings only owns
/// typography, behavior, bookmarks and audio.
class ReaderChapterProgress extends StatefulWidget {
  const ReaderChapterProgress({
    super.key,
    required this.position,
    required this.onSeek,
    required this.onFind,
    this.onPreview,
    this.onCommitted,
    this.onPreviewChanged,
  });
  final ReadingPosition? position;
  final ValueChanged<double> onSeek;
  final VoidCallback onFind;
  final ValueChanged<double>? onPreview, onCommitted;
  final ValueChanged<bool>? onPreviewChanged;
  @override
  State<ReaderChapterProgress> createState() => _ReaderChapterProgressState();
}

class _ReaderChapterProgressState extends State<ReaderChapterProgress> {
  bool _adjusting = false;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          painter: _AdjustmentPlate(
            _adjusting
                ? Theme.of(context).colorScheme.surface.withValues(alpha: .98)
                : Colors.transparent,
          ),
          child: ReaderValueSlider(
            sliderKey: const ValueKey('reader-progress-slider'),
            label: '本章进度',
            value: widget.position?.fraction ?? 0,
            min: 0,
            max: 1,
            divisions: 500,
            hapticSteps: 100,
            format: (v) => '${(v * 100).round()}%',
            onPreview: widget.onPreview,
            onCommitted: widget.position == null
                ? null
                : widget.onCommitted ?? widget.onSeek,
            onInteractionChanged: (active) {
              setState(() => _adjusting = active);
              widget.onPreviewChanged?.call(active);
            },
          ),
        ),
        Visibility(
          visible: !_adjusting,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  GlassTextButton(
                    onPressed: widget.position == null
                        ? null
                        : () => widget.onSeek(0),
                    child: const AppText('回到章首'),
                  ),
                  GlassTextButton(
                    onPressed: widget.position == null
                        ? null
                        : () => widget.onSeek(1),
                    child: const AppText('跳至章末'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GlassTextButton(
                key: const ValueKey('reader-open-find'),
                onPressed: widget.position == null ? null : widget.onFind,
                child: const AppText('章内查找'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A bounded settings sheet. Typography drafts preview the article while
/// preferences are committed once, when the gesture ends.
class ReaderTools extends StatefulWidget {
  const ReaderTools({
    super.key,
    required this.novel,
    required this.state,
    required this.position,
    required this.onAddBookmark,
    required this.onFontSize,
    required this.onLineHeight,
    required this.onReset,
    this.initialBookmarks = false,
    this.onFontPreview,
    this.onLineHeightPreview,
    this.onPreviewChanged,
    this.onPreferencesChanged,
    this.onIllustrations,
    this.listeningBuilder,
    this.initialTab,
  });
  final Novel novel;
  final LibraryState state;
  final ReadingPosition? position;
  final Future<ReaderBookmark?> Function() onAddBookmark;
  final ValueChanged<double> onFontSize;
  final ValueChanged<double> onLineHeight;
  final VoidCallback onReset;
  final VoidCallback? onIllustrations;
  final bool initialBookmarks;
  final WidgetBuilder? listeningBuilder;
  final String? initialTab;
  final ValueChanged<double>? onFontPreview, onLineHeightPreview;
  final ValueChanged<bool>? onPreviewChanged;
  final void Function(ReaderPreferences, bool persist)? onPreferencesChanged;

  @override
  State<ReaderTools> createState() => _ReaderToolsState();
}

class _ReaderToolsState extends State<ReaderTools> {
  late String _tab =
      widget.initialTab ?? (widget.initialBookmarks ? 'bookmarks' : 'layout');
  bool _adding = false;
  bool _added = false;
  String? _addedId;
  String? _storageError;
  Key? _activeAdjustment;
  String _marginEdge = '左右';
  double _marginValue(ReaderPreferences p) => switch (_marginEdge) {
    '左' => p.leftMargin,
    '右' => p.rightMargin,
    '上' => p.marginTop,
    '下' => p.marginBottom,
    _ => p.bindingMargin,
  };
  ReaderPreferences _withMargin(double v) {
    final p = widget.state.readerPreferences;
    return switch (_marginEdge) {
      '左' => p.copyWith(marginLeft: v),
      '右' => p.copyWith(marginRight: v),
      '上' => p.copyWith(marginTop: v),
      '下' => p.copyWith(marginBottom: v),
      _ => p.copyWith(margin: v),
    };
  }

  void _preferences(ReaderPreferences value, {bool persist = true}) {
    if (widget.onPreferencesChanged != null) {
      widget.onPreferencesChanged!(value, persist);
    } else {
      unawaited(
        widget.state.setReaderPreferences(value, persist: persist).catchError((
          Object _,
        ) {
          if (mounted) showNovelFeedback(context, '阅读偏好保存失败，请重试');
        }),
      );
    }
  }

  void _preview(Key key, bool active) {
    if (!mounted) return;
    setState(() => _activeAdjustment = active ? key : null);
    widget.onPreviewChanged?.call(active);
  }

  Widget _adjustment(Widget child, [Key? key]) {
    final active = _activeAdjustment != null;
    final visible = !active || key == _activeAdjustment;
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: CustomPaint(
        painter: _AdjustmentPlate(
          active && visible
              ? Theme.of(context).colorScheme.surface.withValues(alpha: .98)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  Future<void> _add() async {
    if (_adding || widget.position == null) return;
    setState(() {
      _adding = true;
      _storageError = null;
    });
    try {
      final mark = await widget.onAddBookmark();
      if (mounted) {
        setState(() {
          _added = mark != null;
          _addedId = mark?.id;
          if (mark == null) _storageError = '阅读位置正在恢复，请稍后再试';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _storageError = '书签保存失败，请重试');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(ReaderBookmark mark) async {
    setState(() => _storageError = null);
    try {
      await widget.state.removeBookmark(widget.novel.id, mark.id);
      if (mounted && mark.id == _addedId) setState(() => _added = false);
    } catch (_) {
      if (mounted) setState(() => _storageError = '书签删除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // In landscape/keyboard + large text, scrolling only the body can leave a
      // zero-height viewport below the title/tabs. Let the entire panel scroll.
      final compact = constraints.maxHeight < 260;
      Widget body() {
        if (_tab == 'bookmarks') return _bookmarks(context);
        if (_tab == 'listening' && widget.listeningBuilder != null) {
          return widget.listeningBuilder!(context);
        }
        final content = _tab == 'layout'
            ? _layout(context)
            : _behavior(context);
        return compact
            ? content
            : SingleChildScrollView(
                key: const ValueKey('reader-settings-scroll'),
                primary: false,
                child: content,
              );
      }

      final contents = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 14, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: AppText(
                      '阅读设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: CupertinoIcons.xmark,
                    label: '关闭阅读设置',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          _adjustment(
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: AppControls.segments<String>(
                context,
                groupValue: _tab,
                children: {
                  'layout': const AppText('排版'),
                  'behavior': const AppText('操作'),
                  'bookmarks': const AppText('书签'),
                  if (widget.listeningBuilder != null)
                    'listening': const AppText('听书'),
                },
                onValueChanged: (tab) {
                  if (tab != null) setState(() => _tab = tab);
                },
              ),
            ),
          ),
          if (compact) body() else Flexible(child: body()),
        ],
      );
      return compact
          ? SingleChildScrollView(
              key: const ValueKey('reader-settings-scroll'),
              primary: false,
              child: contents,
            )
          : contents;
    },
  );

  Widget _layout(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
    child: AnimatedBuilder(
      animation: widget.state.readerSettingsChanges,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReaderChoicePicker<ReaderMode>(
                  name: 'reader-mode',
                  label: '阅读方式',
                  value: widget.state.readerPreferences.mode,
                  options: {
                    for (final mode in ReaderMode.values) mode: mode.label,
                  },
                  onChanged: (mode) => _preferences(
                    widget.state.readerPreferences.copyWith(mode: mode),
                  ),
                ),
                AnimatedOptionSection(
                  expanded:
                      widget.state.readerPreferences.mode ==
                      ReaderMode.vertical,
                  child: const AppText(
                    '文字由上往下，列由右往左；向右滑动翻到下一页。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
                AnimatedOptionSection(
                  expanded: widget.state.readerPreferences.mode.paginated,
                  child: ReaderChoicePicker<ReaderPageEffect>(
                    name: 'reader-page-effect',
                    label: '翻页效果',
                    value: widget.state.readerPreferences.pageEffect,
                    options: {
                      for (final effect in ReaderPageEffect.values)
                        effect: effect.label,
                    },
                    onChanged: (effect) => _preferences(
                      widget.state.readerPreferences.copyWith(
                        pageEffect: effect,
                      ),
                    ),
                  ),
                ),
                ReaderChoicePicker<ReaderPaper>(
                  name: 'reader-paper',
                  label: '阅读配色',
                  value: widget.state.readerPreferences.paper,
                  options: {
                    for (final paper in ReaderPaper.values) paper: paper.label,
                  },
                  onChanged: (paper) => _preferences(
                    widget.state.readerPreferences.copyWith(paper: paper),
                  ),
                ),
              ],
            ),
          ),
          _adjustment(
            GlassTextButton(
              key: const ValueKey('reader-background-choice'),
              onPressed: () => pushNovelPage<void>(
                context,
                ReaderBackgroundPage(state: widget.state),
                reduceMotion: widget.state.reduceMotion,
              ),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.photo, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: AppText('阅读背景图片')),
                  Icon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
          _adjustment(
            GlassTextButton(
              key: const ValueKey('reader-font-choice'),
              onPressed: () => pushNovelPage<void>(
                context,
                FontSettingsPage(state: widget.state, readerOnly: true),
                reduceMotion: widget.state.reduceMotion,
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.textformat, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: AppText(
                      '阅读字体',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _adjustment(
            LanguageSettingMenu(
              key: const ValueKey('reader-language'),
              state: widget.state,
            ),
          ),
          const SizedBox(height: 12),
          _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-font-slider'),
              label: '字体大小',
              value: widget.state.fontSize,
              min: 15,
              max: 27,
              divisions: 12,
              format: (value) => '${value.round()} pt',
              onCommitted: widget.onFontSize,
              onPreview: widget.onFontPreview,
              onInteractionChanged: (value) =>
                  _preview(const ValueKey('reader-font-slider'), value),
            ),
            const ValueKey('reader-font-slider'),
          ),
          const SizedBox(height: 8),
          _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-line-height-slider'),
              label: widget.state.readerPreferences.mode == ReaderMode.vertical
                  ? '列距'
                  : '行距',
              value: widget.state.lineHeight,
              min: 1.3,
              max: 2.2,
              format: (value) => '${value.toStringAsFixed(2)} 倍',
              onCommitted: widget.onLineHeight,
              onPreview: widget.onLineHeightPreview,
              onInteractionChanged: (value) =>
                  _preview(const ValueKey('reader-line-height-slider'), value),
            ),
            const ValueKey('reader-line-height-slider'),
          ),
          _adjustment(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                AppControls.segments<String>(
                  context,
                  groupValue: _marginEdge,
                  children: {
                    for (final edge in ['左右', '左', '右', '上', '下'])
                      edge: AppText(
                        edge,
                        key: ValueKey('reader-margin-edge-$edge'),
                        style: const TextStyle(fontSize: 12),
                      ),
                  },
                  onValueChanged: (edge) {
                    if (edge != null) setState(() => _marginEdge = edge);
                  },
                ),
                ReaderValueSlider(
                  key: ValueKey('reader-margin-control-$_marginEdge'),
                  sliderKey: const ValueKey('reader-margin-slider'),
                  label: '页边距 · $_marginEdge',
                  value: _marginValue(widget.state.readerPreferences),
                  min: 0,
                  max: 80,
                  divisions: 40,
                  format: (v) => '${v.round()} px',
                  onPreview: (v) =>
                      _preferences(_withMargin(v), persist: false),
                  onInteractionChanged: (v) =>
                      _preview(const ValueKey('reader-margin-slider'), v),
                  onCommitted: (v) => _preferences(_withMargin(v)),
                ),
              ],
            ),
            const ValueKey('reader-margin-slider'),
          ),
          _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-paragraph-gap-slider'),
              label: '段落间距',
              value: widget.state.readerPreferences.paragraphGap,
              min: 0,
              max: 32,
              divisions: 16,
              format: (v) => '${v.round()} px',
              onPreview: (v) => _preferences(
                widget.state.readerPreferences.copyWith(paragraphGap: v),
                persist: false,
              ),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-paragraph-gap-slider'), v),
              onCommitted: (v) => _preferences(
                widget.state.readerPreferences.copyWith(paragraphGap: v),
              ),
            ),
            const ValueKey('reader-paragraph-gap-slider'),
          ),
          _adjustment(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _switch(
                  context,
                  '首行缩进',
                  widget.state.readerPreferences.indent,
                  (v) => _preferences(
                    widget.state.readerPreferences.copyWith(indent: v),
                  ),
                ),
                _switch(
                  context,
                  widget.state.readerPreferences.mode == ReaderMode.vertical
                      ? '上下对齐'
                      : '两端对齐',
                  widget.state.readerPreferences.justify,
                  (v) => _preferences(
                    widget.state.readerPreferences.copyWith(justify: v),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: GlassTextButton(
                    onPressed: widget.onReset,
                    child: const AppText('恢复默认排版'),
                  ),
                ),
                const Divider(height: 24),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _bookmarks(BuildContext context) => SizedBox(
    height: math.min(420, MediaQuery.sizeOf(context).height * .46),
    child: AnimatedBuilder(
      animation: widget.state.bookmarkChanges,
      builder: (context, _) {
        final marks = widget.state.bookmarksFor(widget.novel.id);
        return CustomScrollView(
          key: const ValueKey('reader-bookmarks-scroll'),
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassTextButton(
                      key: const ValueKey('reader-add-bookmark'),
                      onPressed: widget.position == null || _adding
                          ? null
                          : _add,
                      child: AppText(
                        _adding
                            ? '正在保存…'
                            : _added
                            ? '已添加书签'
                            : '添加当前位置书签',
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      widget.position == null
                          ? '章节加载完成后，可保存当前阅读位置。'
                          : '先添加当前位置，再点按下方书签即可回到这里。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      '本书 ${marks.length} 个书签',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_storageError != null)
                      AppText(
                        _storageError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (marks.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 28),
                sliver: SliverToBoxAdapter(
                  child: AppText('将喜欢的位置存成书签，下次直接回到这里。'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                sliver: SliverList.builder(
                  itemCount: marks.length,
                  itemBuilder: (context, index) {
                    final mark = marks[index];
                    final chapter = widget.state.chapterForPosition(
                      widget.novel,
                      mark.position,
                    );
                    return Row(
                      children: [
                        Expanded(
                          child: JellyTapSurface(
                            key: ValueKey('reader-bookmark-${mark.id}'),
                            onTap: chapter == null
                                ? null
                                : () {
                                    Navigator.pop(
                                      context,
                                      ReaderOpenBookmark(mark),
                                    );
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (mark.quote.isNotEmpty) ...[
                                    AppText(
                                      mark.quote,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.7,
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                  ],
                                  AppText(
                                    mark.chapterTitle,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  AppText(
                                    chapter == null
                                        ? '章节已从目录移除'
                                        : '第 ${chapter + 1} 章 · ${(mark.position.fraction * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        GlassIconButton(
                          icon: CupertinoIcons.trash,
                          label: '删除书签 ${mark.id}',
                          onPressed: () => _remove(mark),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _switch(
    BuildContext context,
    String title,
    bool value,
    ValueChanged<bool> changed,
  ) => Row(
    children: [
      Expanded(child: AppText(title)),
      AppControls.toggle(context, value: value, onChanged: changed),
    ],
  );

  Widget _behavior(BuildContext context) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    builder: (context, _) {
      final prefs = widget.state.readerPreferences;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _adjustment(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _switch(
                    context,
                    '隐藏系统状态栏',
                    prefs.hideSystemStatus,
                    (v) => _preferences(prefs.copyWith(hideSystemStatus: v)),
                  ),
                  const AppText(
                    '时间与电量保留在原状态栏位置',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                  if (LocalPlatform.android)
                    AnimatedBuilder(
                      animation: widget.state.readerBehaviorChanges,
                      builder: (context, _) => Row(
                        children: [
                          const Expanded(child: AppText('阅读时保持亮屏')),
                          AppControls.toggle(
                            context,
                            key: const ValueKey('reader-keep-screen-on'),
                            value: widget.state.keepScreenOn,
                            onChanged: (value) async {
                              try {
                                await widget.state.setKeepScreenOn(value);
                              } catch (_) {
                                if (context.mounted) {
                                  showNovelFeedback(context, '亮屏设置保存失败，请重试');
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  GlassTextButton(
                    onPressed: () =>
                        Navigator.pop(context, const ReaderEnterFocus()),
                    child: const AppText('专注阅读 · 隐藏控件'),
                  ),
                  const Divider(height: 24),
                  _switch(
                    context,
                    '分区点按翻页',
                    prefs.tapPaging,
                    (v) => _preferences(prefs.copyWith(tapPaging: v)),
                  ),
                  const AppText(
                    '常规布局点按中间显示控件；竖排左右翻页方向相反。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                  AnimatedOptionSection(
                    expanded: prefs.tapPaging,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final layout in ReaderTapLayout.values)
                          Semantics(
                            selected: prefs.tapLayout == layout,
                            child: GlassTextButton(
                              key: ValueKey('reader-tap-layout-${layout.name}'),
                              compact: true,
                              selected: prefs.tapLayout == layout,
                              onPressed: () => _preferences(
                                prefs.copyWith(tapLayout: layout),
                              ),
                              child: AppText(
                                layout.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedOptionSection(
                    expanded:
                        prefs.tapPaging &&
                        prefs.tapLayout != ReaderTapLayout.standard,
                    child: AppText(
                      '${prefs.tapLayout == ReaderTapLayout.rightHand ? '右' : '左'}半屏上部回退、下部前进，另一侧显示控件。',
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
                  if (LocalPlatform.android)
                    _switch(
                      context,
                      '音量键翻页',
                      prefs.volumePaging,
                      (v) => _preferences(prefs.copyWith(volumePaging: v)),
                    ),
                  const Divider(height: 24),
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-auto-scroll-speed'),
                    label: prefs.mode.paginated ? '自动翻页间隔' : '自动滚动速度',
                    value: prefs.mode.paginated
                        ? 600 / prefs.autoScrollSpeed
                        : prefs.autoScrollSpeed,
                    min: prefs.mode.paginated ? 7.5 : 8,
                    max: prefs.mode.paginated ? 75 : 80,
                    divisions: 36,
                    format: (v) => prefs.mode.paginated
                        ? '${v.round()} 秒'
                        : '${v.round()} px/s',
                    onCommitted: (v) => _preferences(
                      prefs.copyWith(
                        autoScrollSpeed: prefs.mode.paginated ? 600 / v : v,
                      ),
                    ),
                  ),
                  GlassTextButton(
                    key: const ValueKey('reader-auto-scroll-start'),
                    onPressed: widget.position == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            const ReaderStartAutoScroll(),
                          ),
                    child: AppText(prefs.mode.paginated ? '开始自动翻页' : '开始自动滚动'),
                  ),
                  const AppText(
                    '点按正文、手动滑动或切到后台即可暂停。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                  const Divider(height: 24),
                  if (LocalPlatform.android)
                    _switch(
                      context,
                      '左边缘滑动调亮度',
                      prefs.edgeBrightness,
                      (v) => _preferences(prefs.copyWith(edgeBrightness: v)),
                    ),
                  if (LocalPlatform.android)
                    _switch(
                      context,
                      '亮度跟随系统',
                      prefs.brightness == null,
                      (v) => _preferences(
                        prefs.copyWith(brightness: .7, systemBrightness: v),
                      ),
                    ),
                ],
              ),
            ),
            if (LocalPlatform.android)
              AnimatedOptionSection(
                expanded: prefs.brightness != null,
                child: _adjustment(
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-brightness'),
                    label: '阅读亮度',
                    value: prefs.brightness ?? .7,
                    min: .03,
                    max: 1,
                    format: (v) => '${(v * 100).round()}%',
                    onPreview: (v) => _preferences(
                      widget.state.readerPreferences.copyWith(brightness: v),
                      persist: false,
                    ),
                    onInteractionChanged: (v) =>
                        _preview(const ValueKey('reader-brightness'), v),
                    onCommitted: (v) => _preferences(
                      widget.state.readerPreferences.copyWith(brightness: v),
                    ),
                  ),
                  const ValueKey('reader-brightness'),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ReaderChoicePicker<T extends Enum> extends StatelessWidget {
  const ReaderChoicePicker({
    super.key,
    required this.name,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String name, label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => GlassChoiceGroup<T>(
    name: name,
    label: label,
    value: value,
    options: options,
    optionName: (option) => option.name,
    onChanged: onChanged,
    labelSize: 14,
    optionSize: 12,
    leading: value is ReaderPaper
        ? (option) {
            final paper = option as ReaderPaper;
            final dark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: ReaderPreferences(paper: paper).background(dark),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            );
          }
        : null,
  );
}

class _AdjustmentPlate extends CustomPainter {
  const _AdjustmentPlate(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(12),
        const Radius.circular(16),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_AdjustmentPlate oldDelegate) =>
      color != oldDelegate.color;
}

class ReaderValueSlider extends StatefulWidget {
  const ReaderValueSlider({
    super.key,
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onCommitted,
    this.divisions,
    this.onPreview,
    this.onInteractionChanged,
    this.hapticSteps,
  });
  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double>? onCommitted;
  final ValueChanged<double>? onPreview;
  final ValueChanged<bool>? onInteractionChanged;
  final int? hapticSteps;

  @override
  State<ReaderValueSlider> createState() => _ReaderValueSliderState();
}

class _ReaderValueSliderState extends State<ReaderValueSlider> {
  late double _draft = widget.value;
  bool _dragging = false;
  bool _pointerCancelled = false;
  bool _previewChanged = false;
  int? _detent;
  final _hapticClock = Stopwatch()..start();
  int _lastHaptic = -100;
  double get _unit => (widget.max - widget.min) / (widget.divisions ?? 20);

  void _change(double value) {
    final next = value.clamp(widget.min, widget.max);
    if (_dragging && next != _draft) _previewChanged = true;
    setState(() => _draft = next);
    if (_dragging && widget.hapticSteps != null) {
      final steps = widget.hapticSteps!;
      final notch = ((next - widget.min) / (widget.max - widget.min) * steps)
          .round();
      if (_detent != notch &&
          _hapticClock.elapsedMilliseconds - _lastHaptic >= 65) {
        _lastHaptic = _hapticClock.elapsedMilliseconds;
        unawaited(HapticFeedback.selectionClick());
      }
      _detent = notch;
    }
    // Accessibility increments have no pointer drag/end callback.
    if (_dragging) {
      widget.onPreview?.call(_draft);
    } else {
      widget.onCommitted?.call(_draft);
    }
  }

  void _adjust(double direction) {
    _change((_draft + direction * _unit).clamp(widget.min, widget.max));
  }

  void _finish() {
    if (!_dragging) return;
    _dragging = false;
    if (_previewChanged) widget.onCommitted?.call(_draft);
    widget.onInteractionChanged?.call(false);
  }

  @override
  void dispose() {
    if (_dragging && _previewChanged) {
      // Back navigation can remove the slider before the control's end callback.
      // Retain the last visible value without calling the disposed sheet.
      final commit = widget.onCommitted, draft = _draft;
      scheduleMicrotask(() => commit?.call(draft));
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(ReaderValueSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dragging) _draft = widget.value;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppText(
                widget.label,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            AppText(
              widget.format(_draft),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 52,
          child: Semantics(
            key: ValueKey('reader-slider-semantics-${widget.label}'),
            label: widget.label,
            value: widget.format(_draft),
            increasedValue: widget.format(
              (_draft + _unit).clamp(widget.min, widget.max),
            ),
            decreasedValue: widget.format(
              (_draft - _unit).clamp(widget.min, widget.max),
            ),
            slider: true,
            enabled: widget.onCommitted != null,
            onIncrease: widget.onCommitted == null || _draft >= widget.max
                ? null
                : () => _adjust(1),
            onDecrease: widget.onCommitted == null || _draft <= widget.min
                ? null
                : () => _adjust(-1),
            child: ExcludeSemantics(
              child: Listener(
                onPointerCancel: (_) {
                  _pointerCancelled = _dragging;
                  _finish();
                },
                child: AppControls.slider(
                  context,
                  key: widget.sliderKey,
                  value: _draft.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  onChanged: widget.onCommitted == null ? null : _change,
                  onChangeStart: (_) {
                    _pointerCancelled = false;
                    _dragging = true;
                    _previewChanged = false;
                    _detent = widget.hapticSteps == null
                        ? null
                        : ((_draft - widget.min) /
                                  (widget.max - widget.min) *
                                  widget.hapticSteps!)
                              .round();
                    widget.onInteractionChanged?.call(true);
                  },
                  onChangeEnd: (value) {
                    if (_pointerCancelled) return;
                    if (_dragging) {
                      _draft = value.clamp(widget.min, widget.max);
                      _finish();
                    } else {
                      widget.onCommitted?.call(value);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
