import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'app_search_field.dart';
import 'catalog.dart';
import 'offline_cache.dart';
import 'library_state.dart' show ReadingPosition;
import 'reader_tools.dart'
    show
        ReaderChapterProgress,
        ReaderSeekProgress,
        ReaderOpenFind,
        ReaderOpenHandoff;
import 'reader_book_progress.dart';

/// A bounded, lazy chapter picker using the existing glass drawer. The current
/// chapter is the scroll origin, so locating it never lays out earlier rows.
class ReaderCatalogue extends StatefulWidget {
  const ReaderCatalogue({
    super.key,
    required this.novel,
    required this.currentChapter,
    this.cache,
    this.position,
    this.onProgressPreview,
    this.onProgressCommitted,
    this.onPreviewChanged,
    this.canHandoff = false,
    this.bookmarks,
  });
  final Novel novel;
  final int currentChapter;
  final OfflineCacheStore? cache;
  final ReadingPosition? position;
  final ValueChanged<double>? onProgressPreview, onProgressCommitted;
  final ValueChanged<bool>? onPreviewChanged;
  final bool canHandoff;
  final Widget? bookmarks;

  @override
  State<ReaderCatalogue> createState() => _ReaderCatalogueState();
}

class _ReaderCatalogueState extends State<ReaderCatalogue> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _center = GlobalKey();
  late String _tab = widget.position == null ? 'chapters' : 'progress';
  bool _previewing = false;
  bool _wholeBook = false;
  late List<int> _matches = _filter('');
  late final _entries = widget.novel.directory;
  late final _directoryChapters = widget.novel.directoryChapters;
  late final _current = widget.novel.directoryIndexFor(
    widget.currentChapter,
    paragraph: widget.position?.paragraphIndex ?? 0,
    offset: widget.position?.textOffset ?? 0,
  );
  late final _volumes = NovelVolume.of(_directoryChapters);
  late final Set<String> _expanded = {
    for (final volume in _volumes)
      if (_current >= volume.start && _current < volume.end) volume.key,
  };

  List<int> _filter(String query) {
    final chapters = _directoryChapters;
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return List.generate(chapters.length, (index) => index);
    final number = int.tryParse(text);
    if (number != null) {
      return number > 0 && number <= chapters.length ? [number - 1] : [];
    }
    return [
      for (var index = 0; index < chapters.length; index++)
        if (chapters[index].title.toLowerCase().contains(text) ||
            chapters[index].volumeTitle.toLowerCase().contains(text))
          index,
    ];
  }

  void _filterChanged(String query) {
    setState(() => _matches = _filter(query));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _locateCurrent() {
    _tab = 'chapters';
    for (final volume in _volumes) {
      if (_current >= volume.start && _current < volume.end) {
        _expanded.add(volume.key);
      }
    }
    _search.clear();
    _filterChanged('');
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = math.max(
      0.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom - 40,
    );
    final height = math.min(media.size.height * .64, available);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Small landscape/keyboard viewports can scroll the header as well;
          // the chapter list still has its own finite lazy viewport.
          if (constraints.maxHeight < 210) {
            return SingleChildScrollView(
              child: SizedBox(height: 300, child: _contents(context)),
            );
          }
          return _contents(context);
        },
      ),
    );
  }

  Widget _contents(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Visibility(
          visible: !_previewing,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: Row(
            children: [
              const Expanded(
                child: ArchiveSection(title: '目录', code: 'READER / CONTENTS'),
              ),
              GlassIconButton(
                icon: CupertinoIcons.location,
                label: '定位当前章节',
                onPressed: _locateCurrent,
              ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭目录',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        if (widget.position != null) ...[
          const SizedBox(height: 8),
          Visibility(
            visible: !_previewing,
            maintainSize: true,
            maintainState: true,
            maintainAnimation: true,
            child: AppControls.segments<String>(
              context,
              groupValue: _tab,
              children: {
                'progress': const AppText('章节进度'),
                'chapters': const AppText('章节目录'),
                if (widget.bookmarks != null) 'bookmarks': const AppText('书签'),
              },
              onValueChanged: (value) {
                if (value != null) setState(() => _tab = value);
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: _tab == 'bookmarks' && widget.bookmarks != null
              ? widget.bookmarks!
              : _tab == 'progress'
              ? SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppControls.segments<bool>(
                        context,
                        groupValue: _wholeBook,
                        children: const {
                          false: AppText('本章'),
                          true: AppText('整书'),
                        },
                        onValueChanged: (value) {
                          if (value != null) setState(() => _wholeBook = value);
                        },
                      ),
                      if (_wholeBook)
                        ReaderBookProgress(
                          novel: widget.novel,
                          chapter: widget.currentChapter,
                          fraction: widget.position?.fraction ?? 0,
                        )
                      else
                        ReaderChapterProgress(
                          position: widget.position,
                          onPreview: widget.onProgressPreview,
                          onCommitted: widget.onProgressCommitted,
                          onPreviewChanged: (active) {
                            setState(() => _previewing = active);
                            widget.onPreviewChanged?.call(active);
                          },
                          onSeek: (value) =>
                              Navigator.pop(context, ReaderSeekProgress(value)),
                          onFind: () =>
                              Navigator.pop(context, const ReaderOpenFind()),
                        ),
                      if (widget.canHandoff)
                        Visibility(
                          visible: !_previewing,
                          maintainState: true,
                          maintainAnimation: true,
                          maintainSize: true,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                            child: GlassTextButton(
                              key: const ValueKey('reader-handoff-entry'),
                              onPressed: () => Navigator.pop(
                                context,
                                const ReaderOpenHandoff(),
                              ),
                              child: const AppText('在其他设备上续读'),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSearchField(
                      inputKey: const ValueKey('reader-chapter-search'),
                      controller: _search,
                      hint: widget.novel.navigation?.entries.isNotEmpty == true
                          ? '搜索目录名或输入序号'
                          : '搜索章节名或输入章序',
                      onChanged: _filterChanged,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    ),
                    const SizedBox(height: 10),
                    AppText(
                      _search.text.trim().isEmpty
                          ? widget.novel.navigation?.entries.isNotEmpty == true
                                ? '共 ${_entries.length} 项 · ${_entries[_current].title}'
                                : '共 ${_entries.length} 章 · 当前第 ${widget.currentChapter + 1} 章'
                          : '找到 ${_matches.length} ${widget.novel.navigation?.entries.isNotEmpty == true ? '项' : '章'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _chapters(context)),
                  ],
                ),
        ),
      ],
    ),
  );

  Widget _chapters(BuildContext context) {
    if (_matches.isEmpty) {
      return const Center(child: AppText('没有匹配的章节'));
    }
    final matches = _matches.toSet();
    final rows = <({NovelVolume? volume, int? chapter})>[
      for (final volume in _volumes)
        if (Iterable.generate(
          volume.length,
          (i) => volume.start + i,
        ).any(matches.contains)) ...[
          if (volume.title.isNotEmpty) (volume: volume, chapter: null),
          if (volume.title.isEmpty ||
              _expanded.contains(volume.key) ||
              _search.text.trim().isNotEmpty)
            for (var i = volume.start; i < volume.end; i++)
              if (matches.contains(i)) (volume: null, chapter: i),
        ],
    ];
    Widget row(int index) => rows[index].volume != null
        ? _volumeRow(context, rows[index].volume!)
        : _row(context, rows[index].chapter!);
    final current = rows.indexWhere((row) => row.chapter == _current);
    final origin = current < 0 ? 0 : current;
    return CustomScrollView(
      key: const ValueKey('reader-catalogue-scroll'),
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      center: _center,
      anchor: current > 0 ? .22 : 0,
      slivers: [
        SliverList.builder(
          itemCount: origin,
          itemBuilder: (context, index) => row(origin - index - 1),
        ),
        SliverList.builder(
          key: _center,
          itemCount: rows.length - origin,
          itemBuilder: (context, index) => row(origin + index),
        ),
      ],
    );
  }

  Widget _volumeRow(BuildContext context, NovelVolume volume) {
    final expanded =
        _expanded.contains(volume.key) || _search.text.trim().isNotEmpty;
    return Semantics(
      expanded: expanded,
      child: JellyTapSurface(
        key: ValueKey('reader-volume-${volume.key}'),
        onTap: _search.text.trim().isNotEmpty
            ? null
            : () => setState(() {
                if (!_expanded.add(volume.key)) _expanded.remove(volume.key);
              }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  volume.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppText(
                '${volume.length} 章',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(width: 10),
              ArchiveIcon(
                expanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    final entry = _entries[index];
    final chapter = widget.novel.chapters[entry.chapter];
    final current = index == _current;
    return Semantics(
      selected: current,
      child: JellyTapSurface(
        key: ValueKey('reader-chapter-$index'),
        onTap: () {
          FocusScope.of(context).unfocus();
          Navigator.pop(
            context,
            widget.novel.navigation?.entries.isNotEmpty == true
                ? entry.target
                : entry.chapter,
          );
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: EdgeInsets.fromLTRB(
            10 + entry.depth.clamp(0, 6) * 12.0,
            12,
            10,
            12,
          ),
          decoration: BoxDecoration(
            color: current
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .06)
                : null,
            borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: AppText(
                  entry.title,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (current)
                    const AppText('正在阅读', style: TextStyle(fontSize: 10)),
                  if (widget.cache case final OfflineCacheStore cache)
                    AnimatedBuilder(
                      animation: cache.bookChanges(widget.novel.id),
                      builder: (context, _) =>
                          cache
                                  .book(widget.novel.id)
                                  ?.chapterBytes
                                  .containsKey(chapter.id) ==
                              true
                          ? const AppText('已缓存', style: TextStyle(fontSize: 10))
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
