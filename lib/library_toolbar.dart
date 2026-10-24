import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'glass_choices.dart';

/// A single quiet line shared by the separate and merged libraries.
class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    super.key,
    required this.category,
    required this.count,
    required this.onCategory,
    required this.onOptions,
    this.categoryKey,
    this.optionsKey,
    this.onManage,
    this.manageKey,
    this.activeFilters = 0,
    this.loading = false,
    this.filterLabel,
  });
  final String category;
  final int count, activeFilters;
  final String? filterLabel;
  final bool loading;
  final VoidCallback? onCategory, onOptions, onManage;
  final Key? categoryKey, optionsKey, manageKey;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: GlassTextButton(
          key: categoryKey,
          compact: true,
          onPressed: onCategory,
          child: Row(
            children: [
              const ArchiveIcon(CupertinoIcons.folder, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              const ArchiveIcon(CupertinoIcons.chevron_down, size: 11),
            ],
          ),
        ),
      ),
      const SizedBox(width: 12),
      if (loading)
        const InlineSkeleton(width: 38, height: 18)
      else
        AppText(
          '${activeFilters == 0 ? '' : '筛选 · '}$count 本',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      const SizedBox(width: 8),
      Semantics(
        label: '显示与筛选',
        value: activeFilters == 0 ? '未筛选' : '$activeFilters 项筛选',
        button: true,
        child: GlassTextButton(
          key: optionsKey,
          dense: true,
          onPressed: onOptions,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: AppText(
              filterLabel ?? '筛选',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
      if (onManage != null)
        GlassIconButton(
          key: manageKey,
          icon: CupertinoIcons.checkmark_circle,
          label: '批量整理本地书',
          onPressed: onManage,
        ),
    ],
  );
}

class LibraryViewOptions extends StatelessWidget {
  const LibraryViewOptions({
    super.key,
    required this.shelf,
    required this.reading,
    required this.sort,
    required this.onView,
    required this.onReading,
    required this.onSort,
    this.source,
    this.onSource,
    this.footer,
    this.viewHint,
  });
  final bool shelf;
  final String reading, sort;
  final String? source;
  final ValueChanged<bool> onView;
  final ValueChanged<String> onReading, onSort;
  final ValueChanged<String>? onSource;
  final Widget? footer;
  final String? viewHint;
  Widget _choices(
    String label,
    Map<String, String> values,
    String current,
    ValueChanged<String> changed,
  ) => GlassChoiceGroup<String>(
    name: 'library-option-$label',
    label: label,
    value: current,
    options: values,
    onChanged: changed,
  );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const ArchiveSection(title: '显示与筛选', code: 'LIBRARY / VIEW'),
        _choices(
          '视图',
          const {'shelf': '立体书架 + 列表', 'list': '仅列表'},
          shelf ? 'shelf' : 'list',
          (v) => onView(v == 'shelf'),
        ),
        if (viewHint != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: AppText(
              viewHint!,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        _choices(
          '阅读状态',
          const {
            'all': '全部',
            'unread': '未读',
            'reading': '阅读中',
            'finished': '已读完',
          },
          reading,
          onReading,
        ),
        if (source != null && onSource != null)
          _choices(
            '书籍来源',
            const {
              'all': '全部',
              'local': '本地导入',
              'cached': '已缓存',
              'online': '在线收藏',
            },
            source!,
            onSource!,
          ),
        _choices(
          '排列顺序',
          const {'recentRead': '最近阅读', 'recentAdded': '最近加入', 'title': '书名'},
          sort,
          onSort,
        ),
        if (footer != null) ...[const SizedBox(height: 14), footer!],
      ],
    ),
  );
}
