import 'dart:async';
import 'dart:io';
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
import 'glass_choices.dart';
import 'setting_menu.dart';
import 'book_documents.dart';
import 'reader_languages.dart';
import 'bookmark_categories.dart';
import 'feature_pages.dart' show confirmNovelAction;

sealed class ReaderToolAction {
  const ReaderToolAction();
}

class ReaderSeekProgress extends ReaderToolAction {
  const ReaderSeekProgress(this.fraction);
  final double fraction;
}

class ReaderSeekBookProgress extends ReaderToolAction {
  const ReaderSeekBookProgress(this.chapter, this.fraction);
  final int chapter;
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

class ReaderOpenHandoff extends ReaderToolAction {
  const ReaderOpenHandoff();
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
    this.bookmarksOnly = false,
    this.onFontPreview,
    this.onLineHeightPreview,
    this.onPreviewChanged,
    this.onPreferencesChanged,
    this.onIllustrations,
    this.listeningBuilder,
    this.initialTab,
    this.onStyleScopeChanged,
    this.onReaderTypefaceChanged,
    this.languages = const {},
    this.onHiddenLanguagesChanged,
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
  final bool bookmarksOnly;
  final WidgetBuilder? listeningBuilder;
  final String? initialTab;
  final ValueChanged<double>? onFontPreview, onLineHeightPreview;
  final ValueChanged<bool>? onPreviewChanged;
  final void Function(ReaderPreferences, bool persist)? onPreferencesChanged;
  final Future<void> Function(bool)? onStyleScopeChanged;
  final Future<void> Function(String)? onReaderTypefaceChanged;
  final Set<String> languages;
  final Future<void> Function(Set<String>, {String? onlyLanguage})?
  onHiddenLanguagesChanged;

  @override
  State<ReaderTools> createState() => _ReaderToolsState();
}

class _ReaderToolsState extends State<ReaderTools> {
  static const _systemControls = MethodChannel(
    'org.mewx.wenku8/reader_controls',
  );
  late final Future<bool> _floatingNavigation = () async {
    if (!LocalPlatform.android) return false;
    try {
      return (await _systemControls.invokeMapMethod<String, Object?>(
            'navigationCapabilities',
          ))?['systemFloatingNavigation'] ==
          true;
    } catch (_) {
      return false;
    }
  }();
  ReaderPreferences get _readerPreferences =>
      widget.state.readerPreferencesFor(widget.novel.id);
  double get _fontSize => widget.state.readerFontSizeFor(widget.novel.id);
  double get _lineHeight => widget.state.readerLineHeightFor(widget.novel.id);
  bool _changingScope = false;
  bool _changingLanguages = false;
  bool _textDetails = false;
  bool _backgroundExpanded = false, _backgroundBusy = false;
  late Future<List<String>> _backgrounds = widget.state.backgrounds.list();
  final _backgroundFiles = <String, Future<File?>>{};
  late String _tab = switch (widget.initialTab) {
    'appearance' => 'appearance',
    'paging' || 'behavior' => 'paging',
    'display' => 'display',
    _ => widget.initialBookmarks ? 'layout' : 'layout',
  };
  bool _adding = false;
  bool _added = false;
  String? _addedId;
  String? _storageError;
  Key? _activeAdjustment;
  String _marginEdge = '左右';
  Future<void> _importBackground() async {
    if (_backgroundBusy) return;
    setState(() => _backgroundBusy = true);
    final documents = BookDocuments();
    try {
      final selected = await documents.pickImage();
      if (selected == null) return;
      try {
        final id = await widget.state.backgrounds.import(selected.path!);
        if (!mounted) return;
        _preferences(_readerPreferences.copyWith(backgroundImage: id));
        setState(() {
          _backgrounds = widget.state.backgrounds.list();
        });
      } finally {
        await documents.releaseBooks([selected]);
      }
    } catch (e) {
      if (mounted) {
        showNovelFeedback(
          context,
          e is FormatException ? e.message : '背景导入未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> _removeBackground() async {
    final id = _readerPreferences.backgroundImage;
    if (id == null || _backgroundBusy) return;
    if (!await confirmNovelAction(
      context,
      title: '删除这张阅读背景？',
      message: '使用它的书籍恢复纯色背景，原始图片不受影响。',
      confirmLabel: '删除背景',
      reduceMotion: widget.state.reduceMotion,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _backgroundBusy = true);
    try {
      await widget.state.removeReaderBackground(id);
      if (mounted) {
        setState(() {
          _backgrounds = widget.state.backgrounds.list();
        });
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '背景删除未完成，请重试');
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  List<Widget> _backgroundOptions() => [
    _adjustment(
      GlassTextButton(
        key: const ValueKey('reader-background-options'),
        onPressed: () =>
            setState(() => _backgroundExpanded = !_backgroundExpanded),
        child: Row(
          children: [
            const ArchiveIcon(CupertinoIcons.photo, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: AppText(
                '阅读背景',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            ArchiveIcon(
              _backgroundExpanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              size: 14,
            ),
          ],
        ),
      ),
    ),
    AnimatedOptionSection(
      expanded: _backgroundExpanded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                FutureBuilder<List<String>>(
                  future: _backgrounds,
                  builder: (context, snapshot) => SizedBox(
                    height: 76,
                    child: AppScrollHaptics(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 1 + (snapshot.data?.length ?? 0),
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final id = index == 0
                              ? null
                              : snapshot.data![index - 1];
                          return SizedBox(
                            width: 64,
                            child: GlassTextButton(
                              key: ValueKey(
                                'reader-background-${id ?? 'plain'}',
                              ),
                              selected:
                                  _readerPreferences.backgroundImage == id,
                              onPressed: _backgroundBusy
                                  ? null
                                  : () => _preferences(
                                      id == null
                                          ? _readerPreferences.copyWith(
                                              clearBackground: true,
                                            )
                                          : _readerPreferences.copyWith(
                                              backgroundImage: id,
                                            ),
                                    ),
                              child: id == null
                                  ? const AppText(
                                      '纯色',
                                      style: TextStyle(fontSize: 12),
                                    )
                                  : FutureBuilder(
                                      future: _backgroundFiles.putIfAbsent(
                                        id,
                                        () => widget.state.backgrounds.file(id),
                                      ),
                                      builder: (context, file) =>
                                          file.data == null
                                          ? const ArchiveIcon(
                                              CupertinoIcons.photo,
                                              size: 20,
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Image.file(
                                                file.data!,
                                                width: 44,
                                                height: 54,
                                                fit: BoxFit.cover,
                                                cacheWidth: 132,
                                                errorBuilder: (_, _, _) =>
                                                    const ArchiveIcon(
                                                      CupertinoIcons.photo,
                                                      size: 20,
                                                    ),
                                              ),
                                            ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: GlassTextButton(
                        key: const ValueKey('reader-import-background'),
                        onPressed: _backgroundBusy ? null : _importBackground,
                        child: AppText(
                          _backgroundBusy ? '正在处理图片' : '导入背景图片',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    if (_readerPreferences.backgroundImage != null)
                      GlassIconButton(
                        icon: CupertinoIcons.trash,
                        label: '删除当前背景',
                        onPressed: _backgroundBusy ? null : _removeBackground,
                      ),
                  ],
                ),
              ],
            ),
          ),
          AnimatedOptionSection(
            expanded: _readerPreferences.backgroundImage != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _adjustment(
                  ReaderChoicePicker<BoxFit>(
                    name: 'reader-background-fit',
                    label: '图片布局',
                    value: _readerPreferences.backgroundFit,
                    options: const {BoxFit.cover: '填满', BoxFit.contain: '完整'},
                    onChanged: (fit) => _preferences(
                      _readerPreferences.copyWith(backgroundFit: fit),
                    ),
                  ),
                ),
                _adjustment(
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-background-opacity'),
                    label: '背景浓度',
                    value: _readerPreferences.backgroundOpacity,
                    min: .05,
                    max: 1,
                    format: (v) => '${(v * 100).round()}%',
                    onPreview: (v) => _preferences(
                      _readerPreferences.copyWith(backgroundOpacity: v),
                      persist: false,
                    ),
                    onCommitted: (v) => _preferences(
                      _readerPreferences.copyWith(backgroundOpacity: v),
                    ),
                    onInteractionChanged: (v) => _preview(
                      const ValueKey('reader-background-opacity'),
                      v,
                    ),
                  ),
                  const ValueKey('reader-background-opacity'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ];
  double _marginValue(ReaderPreferences p) => switch (_marginEdge) {
    '左' => p.leftMargin,
    '右' => p.rightMargin,
    '上' => p.marginTop,
    '下' => p.marginBottom,
    _ => p.bindingMargin,
  };
  ReaderPreferences _withMargin(double v) {
    final p = _readerPreferences;
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
        widget.state
            .setReaderPreferences(
              value,
              persist: persist,
              bookId: widget.novel.id,
            )
            .catchError((Object _) {
              if (mounted) showNovelFeedback(context, '阅读偏好保存失败，请重试');
            }),
      );
    }
  }

  Future<void> _changeStyleScope(bool book) async {
    if (_changingScope) return;
    setState(() => _changingScope = true);
    try {
      if (widget.onStyleScopeChanged case final change?) {
        await change(book);
      } else {
        await widget.state.setIndependentReaderStyle(widget.novel.id, book);
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '排版范围未保存，请重试');
    } finally {
      if (mounted) setState(() => _changingScope = false);
    }
  }

  Future<void> _showLanguage(String? code) async {
    if (_changingLanguages) return;
    final next = <String>{
      if (code != null)
        for (final language in widget.languages)
          if (language != code) language,
    };
    setState(() => _changingLanguages = true);
    try {
      if (widget.onHiddenLanguagesChanged case final change?) {
        await change(next, onlyLanguage: code);
      } else {
        await widget.state.setHiddenReaderLanguages(
          widget.novel.id,
          next,
          onlyLanguage: code,
        );
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '语言显示设置未保存，请重试');
    } finally {
      if (mounted) setState(() => _changingLanguages = false);
    }
  }

  Widget _languageOptions() {
    final hidden = widget.state.hiddenReaderLanguagesFor(widget.novel.id);
    final languages = widget.languages.toList();
    final only = widget.state.onlyReaderLanguageFor(widget.novel.id);
    final visible = languages
        .where((code) => only == null ? !hidden.contains(code) : code == only)
        .toList();
    return Padding(
      key: const ValueKey('reader-book-languages'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText(
            '本书语言',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlassTextButton(
                key: const ValueKey('reader-language-all'),
                selected: visible.length == languages.length,
                onPressed: _changingLanguages
                    ? null
                    : () => _showLanguage(null),
                child: const AppText('全部语言'),
              ),
              for (final code in languages)
                GlassTextButton(
                  key: ValueKey('reader-language-only-$code'),
                  selected: visible.length == 1 && visible.single == code,
                  onPressed: _changingLanguages
                      ? null
                      : () => _showLanguage(code),
                  child: AppText('仅${readerLanguageLabel(code)}'),
                ),
            ],
          ),
        ],
      ),
    );
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
  Widget build(BuildContext context) {
    if (widget.bookmarksOnly) return _bookmarks(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // In landscape/keyboard + large text, scrolling only the body can leave a
        // zero-height viewport below the title/tabs. Let the entire panel scroll.
        final compact = constraints.maxHeight < 260;
        Widget body() {
          final content = switch (_tab) {
            'appearance' => _appearance(context),
            'paging' => Column(
              mainAxisSize: MainAxisSize.min,
              children: [_paging(context), _behavior(context, turn: true)],
            ),
            'display' => _behavior(context),
            _ => _layout(context),
          };
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
                  children: const {
                    'appearance': AppText('外观'),
                    'layout': AppText('排版'),
                    'paging': AppText('翻页'),
                    'display': AppText('显示'),
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
  }

  Widget _appearance(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
    child: AnimatedBuilder(
      animation: widget.state.readerSettingsChanges,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adjustment(
            ReaderChoicePicker<ReaderPaper>(
              name: 'reader-paper',
              label: '阅读配色',
              value: _readerPreferences.paper,
              options: {
                for (final paper in ReaderPaper.values) paper: paper.label,
              },
              onChanged: (paper) =>
                  _preferences(_readerPreferences.copyWith(paper: paper)),
            ),
          ),
          ..._backgroundOptions(),
          AnimatedOptionSection(
            expanded: _readerPreferences.darkPaper(
              Theme.of(context).brightness == Brightness.dark,
            ),
            child: _adjustment(
              ReaderValueSlider(
                sliderKey: const ValueKey('reader-night-text-brightness'),
                label: '夜读文字亮度',
                value: _readerPreferences.nightTextBrightness,
                min: .35,
                max: 1,
                format: (v) => '${(v * 100).round()}%',
                onPreview: (v) => _preferences(
                  _readerPreferences.copyWith(nightTextBrightness: v),
                  persist: false,
                ),
                onCommitted: (v) => _preferences(
                  _readerPreferences.copyWith(nightTextBrightness: v),
                ),
                onInteractionChanged: (v) =>
                    _preview(const ValueKey('reader-night-text-brightness'), v),
              ),
              const ValueKey('reader-night-text-brightness'),
            ),
          ),
          const SizedBox(height: 12),
          _adjustment(
            LanguageSettingMenu(
              key: const ValueKey('reader-language'),
              state: widget.state,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _paging(BuildContext context) => Padding(
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
                  value: _readerPreferences.mode,
                  options: {
                    for (final mode in ReaderMode.values) mode: mode.label,
                  },
                  onChanged: (mode) =>
                      _preferences(_readerPreferences.copyWith(mode: mode)),
                ),
                AnimatedOptionSection(
                  expanded: _readerPreferences.mode == ReaderMode.vertical,
                  child: const AppText(
                    '文字由上往下，列由右往左；向右滑动翻到下一页。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
                AnimatedOptionSection(
                  expanded: _readerPreferences.mode.paginated,
                  child: ReaderChoicePicker<ReaderPageEffect>(
                    name: 'reader-page-effect',
                    label: '翻页效果',
                    value: _readerPreferences.pageEffect,
                    options: {
                      for (final effect in ReaderPageEffect.values)
                        effect: effect.label,
                    },
                    onChanged: (effect) => _preferences(
                      _readerPreferences.copyWith(pageEffect: effect),
                    ),
                  ),
                ),
                AnimatedOptionSection(
                  expanded:
                      _readerPreferences.mode.paginated &&
                      _readerPreferences.pageEffect != ReaderPageEffect.none,
                  child: ReaderChoicePicker<ReaderPageSpeed>(
                    name: 'reader-page-speed',
                    label: '翻页速度',
                    value: _readerPreferences.pageSpeed,
                    options: {
                      for (final speed in ReaderPageSpeed.values)
                        speed: speed.label,
                    },
                    onChanged: (speed) => _preferences(
                      _readerPreferences.copyWith(pageSpeed: speed),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
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
            GlassChoiceGroup<String>(
              enabled: !_changingScope,
              name: 'reader-style-scope',
              label: '排版范围',
              value: widget.state.independentReaderStyle(widget.novel.id)
                  ? 'book'
                  : 'shared',
              options: const {'shared': '通用', 'book': '本书'},
              optionName: (value) => value,
              labelSize: 14,
              optionSize: 12,
              onChanged: (value) => _changeStyleScope(value == 'book'),
            ),
          ),
          if (widget.languages.length > 1) _adjustment(_languageOptions()),
          _adjustment(
            GlassTextButton(
              key: const ValueKey('reader-font-choice'),
              onPressed: () => pushNovelPage<void>(
                context,
                FontSettingsPage(
                  state: widget.state,
                  readerOnly: true,
                  bookId: widget.novel.id,
                  onReaderTypefaceChanged: widget.onReaderTypefaceChanged,
                ),
                reduceMotion: widget.state.reduceMotion,
              ),
              child: Row(
                children: [
                  const ArchiveIcon(CupertinoIcons.textformat, size: 20),
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
                  const ArchiveIcon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
          _adjustment(
            ReaderValueSlider(
              sliderKey: const ValueKey('reader-font-slider'),
              label: '字体大小',
              stepper: true,
              value: _fontSize,
              min: minimumReaderFontSize,
              max: maximumReaderFontSize,
              divisions: (maximumReaderFontSize - minimumReaderFontSize)
                  .round(),
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
              label: _readerPreferences.mode == ReaderMode.vertical
                  ? '列距'
                  : '行距',
              value: _lineHeight,
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
                  value: _marginValue(_readerPreferences),
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
              value: _readerPreferences.paragraphGap,
              min: 0,
              max: 32,
              divisions: 16,
              format: (v) => '${v.round()} px',
              onPreview: (v) => _preferences(
                _readerPreferences.copyWith(paragraphGap: v),
                persist: false,
              ),
              onInteractionChanged: (v) =>
                  _preview(const ValueKey('reader-paragraph-gap-slider'), v),
              onCommitted: (v) =>
                  _preferences(_readerPreferences.copyWith(paragraphGap: v)),
            ),
            const ValueKey('reader-paragraph-gap-slider'),
          ),
          _adjustment(
            GlassTextButton(
              key: const ValueKey('reader-text-details'),
              onPressed: () => setState(() => _textDetails = !_textDetails),
              child: Row(
                children: [
                  const Expanded(
                    child: AppText('文字细节', style: TextStyle(fontSize: 14)),
                  ),
                  ArchiveIcon(
                    _textDetails
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
          AnimatedOptionSection(
            expanded: _textDetails,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _adjustment(
                  ReaderChoicePicker<ReaderTextWeight>(
                    name: 'reader-text-weight',
                    label: '字重',
                    value: _readerPreferences.textWeight,
                    options: {
                      for (final weight in ReaderTextWeight.values)
                        weight: weight.label,
                    },
                    onChanged: (weight) => _preferences(
                      _readerPreferences.copyWith(textWeight: weight),
                    ),
                  ),
                ),
                _adjustment(
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-letter-spacing'),
                    label: '字间距',
                    value: _readerPreferences.letterSpacing,
                    min: -.5,
                    max: 3,
                    divisions: 35,
                    format: (v) => '${v.toStringAsFixed(1)} px',
                    onPreview: (v) => _preferences(
                      _readerPreferences.copyWith(letterSpacing: v),
                      persist: false,
                    ),
                    onCommitted: (v) => _preferences(
                      _readerPreferences.copyWith(letterSpacing: v),
                    ),
                    onInteractionChanged: (v) =>
                        _preview(const ValueKey('reader-letter-spacing'), v),
                  ),
                  const ValueKey('reader-letter-spacing'),
                ),
              ],
            ),
          ),
          _adjustment(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _switch(
                  context,
                  '首行缩进',
                  _readerPreferences.indent,
                  (v) => _preferences(_readerPreferences.copyWith(indent: v)),
                ),
                _switch(
                  context,
                  _readerPreferences.mode == ReaderMode.vertical
                      ? '上下对齐'
                      : '两端对齐',
                  _readerPreferences.justify,
                  (v) => _preferences(_readerPreferences.copyWith(justify: v)),
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
                          icon: CupertinoIcons.folder,
                          label: '分类书签 ${mark.id}',
                          onPressed: () => organizeBookmark(
                            context,
                            widget.state,
                            widget.novel.id,
                            mark,
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

  Widget _behavior(
    BuildContext context, {
    bool turn = false,
  }) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    builder: (context, _) {
      final prefs = _readerPreferences;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!turn)
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
                    FutureBuilder<bool>(
                      future: _floatingNavigation,
                      builder: (context, value) => value.data != true
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 8),
                                const AppText(
                                  '系统悬浮球需在「系统和更新 → 系统导航方式 → 悬浮导航」中关闭。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                                GlassTextButton(
                                  onPressed: () async {
                                    try {
                                      await _systemControls.invokeMethod<void>(
                                        'navigationSettings',
                                      );
                                    } catch (_) {
                                      if (context.mounted) {
                                        showNovelFeedback(
                                          context,
                                          '请在手机设置中搜索「悬浮导航」',
                                        );
                                      }
                                    }
                                  },
                                  child: const AppText('打开系统设置'),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            if (!turn)
              AnimatedOptionSection(
                expanded: prefs.hideSystemStatus,
                child: _adjustment(
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-status-inset'),
                    label: '时间与电量留边',
                    value: prefs.statusSideInset,
                    min: 0,
                    max: 96,
                    divisions: 48,
                    format: (v) => v == 0 ? '自动' : '+${v.round()}',
                    onPreview: (v) => _preferences(
                      prefs.copyWith(statusSideInset: v),
                      persist: false,
                    ),
                    onCommitted: (v) =>
                        _preferences(prefs.copyWith(statusSideInset: v)),
                    onInteractionChanged: (v) =>
                        _preview(const ValueKey('reader-status-inset'), v),
                  ),
                  const ValueKey('reader-status-inset'),
                ),
              ),
            if (!turn)
              _adjustment(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    Row(
                      children: [
                        const Expanded(child: AppText('控件显隐时正文重排')),
                        AppControls.toggle(
                          context,
                          key: const ValueKey('reader-reflow-on-chrome'),
                          value: prefs.reflowOnChrome,
                          onChanged: (value) => _preferences(
                            prefs.copyWith(reflowOnChrome: value),
                          ),
                        ),
                      ],
                    ),
                    const AppText(
                      '开启时正文为控件留出空间；关闭时控件覆盖正文。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            if (turn)
              _adjustment(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: AppText('章节入场动画')),
                        AppControls.toggle(
                          context,
                          key: const ValueKey('reader-chapter-entrance'),
                          value: prefs.chapterEntrance,
                          onChanged: (value) => _preferences(
                            prefs.copyWith(chapterEntrance: value),
                          ),
                        ),
                      ],
                    ),
                    const AppText(
                      '只控制打开章节时的额外入场；跨章仍沿用翻页效果。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                    _switch(
                      context,
                      '分区点按翻页',
                      prefs.tapPaging,
                      (v) => _preferences(prefs.copyWith(tapPaging: v)),
                    ),
                    AppText(
                      prefs.tapPaging && prefs.tapBothSidesNext
                          ? '左右两侧前进，中间显示控件；滑动翻页不变。'
                          : '常规布局点按中间显示控件；竖排左右翻页方向相反。',
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                    AnimatedOptionSection(
                      expanded: prefs.tapPaging,
                      child: Row(
                        children: [
                          const Expanded(child: AppText('左右点按均为下一页')),
                          AppControls.toggle(
                            context,
                            key: const ValueKey('reader-tap-both-sides-next'),
                            value: prefs.tapBothSidesNext,
                            onChanged: (value) => _preferences(
                              prefs.copyWith(tapBothSidesNext: value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOptionSection(
                      expanded: prefs.tapPaging && !prefs.tapBothSidesNext,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final layout in ReaderTapLayout.values)
                            Semantics(
                              selected: prefs.tapLayout == layout,
                              child: GlassTextButton(
                                key: ValueKey(
                                  'reader-tap-layout-${layout.name}',
                                ),
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
                          !prefs.tapBothSidesNext &&
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
                      child: AppText(
                        prefs.mode.paginated ? '开始自动翻页' : '开始自动滚动',
                      ),
                    ),
                    const AppText(
                      '点按正文、手动滑动或切到后台即可暂停。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            if (!turn)
              _adjustment(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
            if (!turn && LocalPlatform.android)
              AnimatedOptionSection(
                expanded: prefs.brightness != null,
                child: _adjustment(
                  ReaderValueSlider(
                    sliderKey: const ValueKey('reader-brightness'),
                    label: '阅读亮度',
                    value: prefs.brightness ?? .7,
                    min: 0,
                    max: 1,
                    format: (v) => '${(v * 100).round()}%',
                    onPreview: (v) => _preferences(
                      _readerPreferences.copyWith(brightness: v),
                      persist: false,
                    ),
                    onInteractionChanged: (v) =>
                        _preview(const ValueKey('reader-brightness'), v),
                    onCommitted: (v) => _preferences(
                      _readerPreferences.copyWith(brightness: v),
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
    this.stepper = false,
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
  final bool stepper;

  @override
  State<ReaderValueSlider> createState() => _ReaderValueSliderState();
}

class _ReaderValueSliderState extends State<ReaderValueSlider> {
  late double _draft = widget.value;
  bool _dragging = false;
  bool _pointerCancelled = false;
  bool _previewChanged = false;
  double get _unit => (widget.max - widget.min) / (widget.divisions ?? 20);
  int _notch(double value) =>
      ((value - widget.min) /
              (widget.max - widget.min) *
              (widget.hapticSteps ?? widget.divisions ?? 20))
          .round();

  void _change(double value) {
    final next = value.clamp(widget.min, widget.max);
    final previous = _draft;
    final firstDragChange = _dragging && !_previewChanged;
    if (_dragging && next != _draft) _previewChanged = true;
    setState(() => _draft = next);
    // The reader owns both its explicit progress cadence and semantic steps;
    // the glass adapter is muted so one changed value cannot pulse twice.
    if (next != previous &&
        (firstDragChange || !_dragging || _notch(next) != _notch(previous))) {
      AppHaptics.play(
        context,
        next == widget.min || next == widget.max
            ? HapticCue.boundary
            : HapticCue.detent,
      );
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
            if (widget.stepper) ...[
              const SizedBox(width: 8),
              GlassTextButton(
                dense: true,
                onPressed: widget.onCommitted == null || _draft <= widget.min
                    ? null
                    : () => _adjust(-1),
                child: AppText(widget.label.contains('字体') ? 'A−' : '−'),
              ),
              const SizedBox(width: 4),
              GlassTextButton(
                dense: true,
                onPressed: widget.onCommitted == null || _draft >= widget.max
                    ? null
                    : () => _adjust(1),
                child: AppText(widget.label.contains('字体') ? 'A＋' : '＋'),
              ),
            ],
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
                  haptics: false,
                  onChanged: widget.onCommitted == null ? null : _change,
                  onChangeStart: (_) {
                    _pointerCancelled = false;
                    _dragging = true;
                    _previewChanged = false;
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
