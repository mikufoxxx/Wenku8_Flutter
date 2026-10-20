import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_background.dart';
import 'background_settings_page.dart';
import 'reader_background.dart';
import 'app_search_field.dart';
import 'setting_menu.dart';
import 'cover_images.dart';
import 'font_settings_page.dart';
import 'my_page.dart';
import 'illustration_layout_page.dart';
import 'illustration_placement.dart';
import 'automatic_illustrations.dart';
import 'local_book_series.dart';
import 'local_book_batch_page.dart';
import 'app_interactions.dart';
import 'author_works_page.dart';
import 'archive_carousel.dart';
import 'backup_page.dart';
import 'book_collection_layout.dart';
import 'book_categories.dart';
import 'bookshelf_scope.dart';
import 'book_source_badge.dart';
import 'book_search.dart';
import 'catalog.dart';
import 'glass_dock.dart';
import 'home_navigation.dart';
import 'library_state.dart';
import 'library_toolbar.dart';
import 'library_workspace.dart';
import 'library_reflow.dart';
import 'library_search_repository.dart';
import 'listening/controller.dart';
import 'listening/models.dart' show hasSpeechText;
import 'listening/widgets.dart';
import 'listening/custom_tts_page.dart';
import 'local_platform.dart';
import 'local_books.dart';
import 'local_library_page.dart';
import 'local_book_editor.dart';
import 'local_book_removal.dart';
import 'local_book_importer.dart';
import 'native_effects.dart' show NativeGlassGroup;
import 'network_status.dart';
import 'novel_feed_controller.dart';
import 'offline_repository.dart';
import 'offline_widgets.dart';
import 'low_performance_page.dart';
import 'frame_rate_settings.dart';
import 'reader_catalogue.dart';
import 'reader_chrome.dart';
import 'reader_appearance.dart';
import 'reader_content.dart';
import 'reader_scroll_sliver.dart';
import 'discovery_filters.dart';
import 'reader_follow_scroll.dart';
import 'reader_illustrations.dart';
import 'reader_volume_illustrations.dart';
import 'local_image_layout.dart';
import 'reader_find.dart';
import 'reader_pagination.dart';
import 'reader_paged_view.dart';
import 'reader_vertical_text.dart';
import 'reader_reflow.dart';
import 'reader_turn_motion.dart';
import 'reader_selection.dart';
import 'reader_landing_highlight.dart';
import 'reader_tools.dart';
import 'reader_status.dart';
import 'reader_preferences.dart';
import 'reader_text.dart';
import 'reading_history.dart';
import 'recent_searches.dart';
import 'ui_notifiers.dart';
import 'feature_pages.dart';
import 'wenku_features.dart';
import 'legacy_import_page.dart';
import 'legacy_transport.dart';
import 'review_pages.dart';

export 'app_ui.dart' show sectionHeader;

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.state,
    required this.repository,
    this.network,
  });
  final LibraryState state;
  final NovelRepository repository;
  final NetworkStatus? network;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  late final _navigation = HomeNavigation(widget.state, widget.network);
  late List<int> _visibleTabs;
  final _visitedTabs = <int>{};
  bool _catalogStarted = false;
  static const _dockItems = [
    GlassDockItem(CupertinoIcons.house, '发现'),
    GlassDockItem(CupertinoIcons.book, '书架'),
    GlassDockItem(CupertinoIcons.folder, '本地'),
    GlassDockItem(CupertinoIcons.person_crop_circle, '我的'),
  ];
  late final _catalog = NovelFeedController(
    widget.repository,
    initialItems: 60,
  );
  late final _searchFeed = NovelFeedController(widget.repository, search: true);
  LocalBookStore? get _localBooks => widget.repository is OfflineNovelRepository
      ? (widget.repository as OfflineNovelRepository).local
      : null;
  late final _shelfSearch = NovelFeedController(
    LibrarySearchRepository(
      source: widget.repository,
      state: widget.state,
      local: _localBooks,
      cachedOnly: () => _navigation.readableShelfOnly,
    ),
    search: true,
  );
  late final _localSearch = NovelFeedController(
    LibrarySearchRepository(
      source: widget.repository,
      state: widget.state,
      local: _localBooks,
      localOnly: true,
    ),
    search: true,
  );
  int _searchScope = 0;
  NovelFeedController get _activeSearch => switch (_searchScope) {
    1 => _shelfSearch,
    2 => _localSearch,
    _ => _searchFeed,
  };
  final _localLibrary = LocalLibraryController();
  List<Widget> _pageWidgets = const [];
  List<WidgetBuilder> _headers = const [];
  int _tab = 0;
  double _tabDirection = 1;
  int? _outgoingTab;
  bool _searchOpen = false;
  bool _searchMounted = false;
  bool _searchCovered = false;
  bool _searchFocusPending = false;
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(
    debugLabel: 'inline-search',
    canRequestFocus: false,
  );
  bool _searchStarted = false;
  bool? _routeCurrent;
  String _lastRecordedSearch = '';
  late final AnimationController _searchExpansion =
      AnimationController(
        vsync: this,
        duration: NovelMotion.enter,
        reverseDuration: NovelMotion.exit,
      )..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.dismissed && !_searchOpen) {
          setState(() => _searchMounted = false);
        } else if (status == AnimationStatus.completed && _searchOpen) {
          setState(() => _searchCovered = true);
          _focusOpenedSearch();
        }
      });
  late final AnimationController _pageTransition =
      AnimationController(vsync: this, duration: NovelMotion.enter, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _outgoingTab = null);
          }
        });

  @override
  void initState() {
    super.initState();
    _visibleTabs = _navigation.tabs;
    _tab = _navigation.destination(_tab);
    _visitedTabs.add(_tab);
    _navigation.addListener(_navigationChanged);
    _searchText.addListener(_searchEdited);
    _searchFeed.addListener(_searchSucceeded);
    if (widget.repository case final OfflineNovelRepository offline) {
      unawaited(offline.loadCache().catchError((Object _) {}));
    }
    final discover = DiscoverPage(
      books: const [],
      feed: _catalog,
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
      onSearch: _openSearch,
    );
    final shelf = ShelfPage(
      books: const [],
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
      onSearch: _openSearch,
      navigation: _navigation,
    );
    final settings = MyPage(
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
    );
    final local = widget.repository is OfflineNovelRepository
        ? (widget.repository as OfflineNovelRepository).local
        : null;
    final localPage = local == null
        ? null
        : LocalLibraryPage(
            books: local,
            state: widget.state,
            controller: _localLibrary,
            showHeader: false,
            onSearch: _openSearch,
            onOpen: (page, book) =>
                openDetail(page, book, widget.state, widget.repository),
            onOpenWithCover: (page, book, tag) => openDetail(
              page,
              book,
              widget.state,
              widget.repository,
              coverHeroTag: tag,
            ),
          );
    _headers = [
      discover.buildHeader,
      shelf.buildHeader,
      localPage?.buildHeader ??
          (_) => const ArchiveMasthead(title: '本地', code: '03 / LOCAL ARCHIVE'),
      settings.buildHeader,
    ];
    _pageWidgets =
        [
              discover,
              shelf,
              localPage ?? const Center(child: AppText('当前演示数据源未启用本地书库')),
              settings,
            ]
            .map((page) => RepaintBoundary(child: Atmosphere(child: page)))
            .toList(growable: false);
    _ensureCatalog();
  }

  void _ensureCatalog() {
    if (_tab != 0 || !_visibleTabs.contains(0)) return;
    if (!_catalogStarted) {
      _catalogStarted = true;
      _catalog.loadInitial();
    } else if (_catalog.items.isEmpty && _catalog.error != null) {
      _catalog.retry();
    }
  }

  void _navigationChanged() {
    if (!mounted) return;
    final tabs = _navigation.tabs;
    final next = _navigation.destination(_tab);
    if (_searchOpen && !tabs.contains(_searchScope)) _closeSearch();
    setState(() {
      _visibleTabs = tabs;
    });
    if (next != _tab) _selectTab(next, feedback: false);
    if (_searchOpen && _searchScope == 1) {
      _shelfSearch.refresh();
    }
    _ensureCatalog();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An obscured route can pause its expansion ticker until it returns.
    // Returning must not resume an old request to open the keyboard.
    final current = ModalRoute.isCurrentOf(context);
    if (current == false) {
      _searchFocusPending = false;
    } else if (current == true &&
        _routeCurrent == false &&
        _searchOpen &&
        _searchScope != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _searchOpen &&
            _searchScope != 0 &&
            ModalRoute.isCurrentOf(context) == true) {
          _activeSearch.refresh();
        }
      });
    }
    _routeCurrent = current;
  }

  @override
  void dispose() {
    _navigation.removeListener(_navigationChanged);
    _navigation.dispose();
    _pageTransition.dispose();
    _searchExpansion.dispose();
    _searchText.dispose();
    _searchFocus.dispose();
    _catalog.dispose();
    _searchFeed.dispose();
    _shelfSearch.dispose();
    _localSearch.dispose();
    _localLibrary.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context);

  void _openSearch() {
    _searchFocus.canRequestFocus = true;
    _searchScope = _tab;
    final feed = _activeSearch;
    _searchText.value = TextEditingValue(
      text: feed.query,
      selection: TextSelection.collapsed(offset: feed.query.length),
    );
    _searchFocusPending = true;
    if (_searchScope != 0) {
      feed.refresh();
    } else if (!_searchStarted ||
        (_searchFeed.page == 0 && !_searchFeed.loading)) {
      _searchStarted = true;
      _searchFeed.loadInitial();
    }
    setState(() {
      _searchOpen = true;
      _searchMounted = true;
    });
    if (_reduceMotion) {
      _searchExpansion.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusOpenedSearch();
      });
    } else {
      _searchExpansion.forward();
    }
  }

  void _focusOpenedSearch() {
    if (!_searchFocusPending ||
        !_searchOpen ||
        _searchFocus.context == null ||
        ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    _searchFocusPending = false;
    _searchFocus.requestFocus();
  }

  void _dismissSearchKeyboard() {
    _searchFocusPending = false;
    _searchFocus.unfocus();
  }

  void _closeSearch() {
    _dismissSearchKeyboard();
    _searchFocus.canRequestFocus = false;
    _activeSearch.cancelScheduledSearch();
    setState(() {
      _searchOpen = false;
      _searchCovered = false;
    });
    if (_reduceMotion) {
      _searchExpansion.value = 0;
    } else {
      _searchExpansion.reverse();
    }
  }

  void _searchEdited() {
    if (!_searchOpen) return;
    if (!_searchText.value.composing.isCollapsed) {
      _activeSearch.cancelScheduledSearch();
      return;
    }
    _activeSearch.scheduleSearch(_searchText.text);
  }

  void _searchSucceeded() {
    if (_searchScope != 0 ||
        _searchFeed.loading ||
        _searchFeed.error != null ||
        _searchFeed.page < 1) {
      return;
    }
    final query = _searchFeed.query.trim();
    if (query == _lastRecordedSearch) return;
    _lastRecordedSearch = query;
    unawaited(
      widget.state.recordSearch(query).catchError((Object _) {
        if (_lastRecordedSearch == query) _lastRecordedSearch = '';
        if (mounted) showNovelFeedback(context, '最近搜索保存失败');
      }),
    );
  }

  void _recallSearch(String query) {
    _searchText.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _searchFeed.searchFor(query);
    _dismissSearchKeyboard();
  }

  void _selectTab(int index, {bool feedback = true}) {
    if (index == _tab || !_visibleTabs.contains(index)) return;
    if (index == 2) _localLibrary.refresh?.call();
    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion =
        widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (feedback) HapticFeedback.selectionClick();
    setState(() {
      if (index != _tab) {
        _tabDirection = index > _tab ? 1 : -1;
        _outgoingTab = reduceMotion ? null : _tab;
        if (reduceMotion) {
          _pageTransition.value = 1;
        } else {
          _pageTransition.forward(from: 0);
        }
      }
      _tab = index;
      _visitedTabs.add(index);
    });
    _ensureCatalog();
  }

  Widget _tabPlane(int index) {
    if (!_visitedTabs.contains(index)) {
      return SizedBox.shrink(key: ValueKey('home-tab-unvisited-$index'));
    }
    final active = index == _tab;
    final outgoing = index == _outgoingTab;
    final animation = (active || outgoing) && !_reduceMotion
        ? _pageTransition
        : const AlwaysStoppedAnimation<double>(1);
    return RetainedPane(
      key: ValueKey('home-tab-$index'),
      active: !_searchCovered && (active || outgoing),
      child: ExcludeFocus(
        excluding: !active || _searchMounted,
        child: TickerMode(
          enabled: active && !_searchCovered,
          child: HeroMode(
            enabled: active && !_searchMounted,
            child: IgnorePointer(
              ignoring: !active || _searchMounted,
              child: ExcludeSemantics(
                excluding: !active || _searchMounted,
                child: ArchivePlaneTransition(
                  key: ValueKey('home-archive-plane-$index'),
                  animation: animation,
                  kind: outgoing
                      ? ArchivePlaneKind.outgoing
                      : ArchivePlaneKind.incoming,
                  direction: _tabDirection,
                  child: ArchiveMotionScope(
                    animation: animation,
                    enabled: active && !_reduceMotion,
                    child: _pageWidgets[index],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LibraryWorkspace(
    reduceMotion: widget.state.reduceMotion,
    child: PopScope<void>(
      canPop: !_searchMounted,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchMounted) _closeSearch();
      },
      child: Scaffold(
        body: Atmosphere(
          // Each tab/search paints its own archive diagram; the shell only
          // supplies the fallback canvas during a transition.
          archiveBackdrop: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (var i = 0; i < _pageWidgets.length; i++)
                            if (i != _tab && i != _outgoingTab) _tabPlane(i),
                          if (_outgoingTab case final outgoing?)
                            _tabPlane(outgoing),
                          _tabPlane(_tab),
                        ],
                      ),
                    ),
                    if (_searchMounted)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_searchOpen,
                          child: ArchivePlaneTransition(
                            key: const ValueKey('search-archive-plane'),
                            animation: _searchExpansion,
                            child: Atmosphere(
                              child: InlineSearchResults(
                                feed: _activeSearch,
                                state: widget.state,
                                repository: widget.repository,
                                onOpenBook: _dismissSearchKeyboard,
                                showSources:
                                    _searchScope == 1 &&
                                    widget.state.combinedShelf,
                                fromCache:
                                    _searchScope == 1 &&
                                    _navigation.readableShelfOnly,
                                onRecall: _searchScope == 0
                                    ? _recallSearch
                                    : null,
                                emptyQueryTitle: switch (_searchScope) {
                                  1 => '书架中的书籍',
                                  2 => '本地书籍',
                                  _ => '你可能会喜欢',
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      key: const ValueKey('home-pinned-header'),
                      top: 0,
                      left: 0,
                      right: 0,
                      child: FrostedHeader(
                        child: _searchMounted
                            ? _expandedSearchHeader(context)
                            : ArchiveMotionScope(
                                animation: _pageTransition,
                                enabled: !_reduceMotion,
                                child: Row(
                                  children: [
                                    Expanded(child: _headers[_tab](context)),
                                    if (ListeningScope.maybeOf(context)
                                        case final listening?)
                                      SelectedValueBuilder<
                                        ListeningSnapshot,
                                        Novel?
                                      >(
                                        listenable: listening.snapshot,
                                        select: (session) => session.active
                                            ? session.novel
                                            : null,
                                        builder: (context, novel, _) =>
                                            novel == null
                                            ? const SizedBox.shrink()
                                            : Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4,
                                                ),
                                                child: GlassIconButton(
                                                  key: const ValueKey(
                                                    'home-listening-entry',
                                                  ),
                                                  icon:
                                                      CupertinoIcons.headphones,
                                                  label:
                                                      '正在听书 · ${novel.title}',
                                                  onPressed: () {
                                                    // This button does not rebuild at clip boundaries;
                                                    // opening the panel still uses the live cursor.
                                                    final session = listening
                                                        .snapshot
                                                        .value;
                                                    if (session.novel == null ||
                                                        !session.active) {
                                                      return;
                                                    }
                                                    showListeningPanel(
                                                      context,
                                                      controller: listening,
                                                      novel: session.novel!,
                                                      chapter: session.chapter,
                                                      paragraph:
                                                          session
                                                              .current
                                                              ?.paragraph ??
                                                          0,
                                                      reduceMotion: widget
                                                          .state
                                                          .reduceMotion,
                                                    );
                                                  },
                                                ),
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(),
              ),
              AnimatedBuilder(
                animation: _searchExpansion,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      22 + MediaQuery.paddingOf(context).left,
                      0,
                      22 + MediaQuery.paddingOf(context).right,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: LibraryReflowPart(
                      child: GlassDock(
                        key: const ValueKey('liquid-dock'),
                        selectedIndex: _visibleTabs.indexOf(_tab),
                        reduceMotion: widget.state.reduceMotion,
                        onSelected: (slot) => _selectTab(_visibleTabs[slot]),
                        items: [
                          for (final page in _visibleTabs) _dockItems[page],
                        ],
                      ),
                    ),
                  ),
                ),
                builder: (context, child) => IgnorePointer(
                  ignoring: _searchMounted,
                  child: ExcludeSemantics(
                    excluding: _searchMounted,
                    child: Opacity(
                      opacity: 1 - _searchExpansion.value,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _expandedSearchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _searchExpansion,
      child: _searchField(context),
      builder: (context, child) {
        final t = _searchExpansion.value;
        final expansion = NovelMotion.ease.transform(t);
        final wobble = _reduceMotion ? 0.0 : NovelMotion.jelly(t);
        final width = 46 + (constraints.maxWidth - 46) * expansion;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ExcludeSemantics(
              child: Opacity(
                opacity: 1 - expansion,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ArchiveMasthead(
                    title: switch (_searchScope) {
                      1 => '书架',
                      2 => '本地',
                      _ => '轻小说文库',
                    },
                    code: switch (_searchScope) {
                      1 => '02 / PERSONAL ARCHIVE',
                      2 => '03 / LOCAL ARCHIVE',
                      _ => 'WENKU8 / READING ARCHIVE',
                    },
                    brand: _searchScope == 0,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Transform(
                key: const ValueKey('search-jelly-transform'),
                alignment: Alignment.centerRight,
                transform: Matrix4.diagonal3Values(
                  1 + .026 * wobble,
                  1 - .042 * wobble,
                  1,
                ),
                child: IgnorePointer(
                  ignoring: !_searchOpen || t < .4,
                  child: LiquidGlass(
                    key: const ValueKey('expanded-search-bar'),
                    radius: 24 - expansion,
                    elevated: false,
                    activation: wobble.abs() * .35,
                    touchPosition: .94,
                    child: SizedBox(
                      width: width,
                      height: 46,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24 - expansion),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                          minHeight: 46,
                          maxHeight: 46,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _searchField(BuildContext context) => Row(
    children: [
      const SizedBox(width: 44, child: Icon(CupertinoIcons.search, size: 19)),
      Expanded(
        child: AppSearchField(
          inputKey: const ValueKey('expanded-search-input'),
          embedded: true,
          showLeading: false,
          hint: _activeSearch.searchField.hint,
          controller: _searchText,
          focusNode: _searchFocus,
          onSubmitted: (query) {
            _activeSearch.searchFor(query);
            _dismissSearchKeyboard();
          },
        ),
      ),
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => SizedBox(
            width: 42,
            height: 46,
            child: IconButton(
              key: const ValueKey('search-field-filter'),
              tooltip: '搜索范围：${_activeSearch.searchField.label}',
              icon: Icon(
                CupertinoIcons.line_horizontal_3_decrease,
                size: 19,
                color: _activeSearch.searchField == BookSearchField.all
                    ? null
                    : Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => _chooseSearchField(anchor),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 46,
        height: 46,
        child: IconButton(
          key: const ValueKey('inline-search-close'),
          tooltip: '收起搜索',
          onPressed: _closeSearch,
          icon: const Icon(CupertinoIcons.xmark, size: 17),
        ),
      ),
    ],
  );

  Future<void> _chooseSearchField(BuildContext context) async {
    _dismissSearchKeyboard();
    final field = await showGlassMenu<BookSearchField>(
      context: context,
      reduceMotion: _reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, field) in BookSearchField.values.indexed)
            GlassMenuItem(
              order: index,
              label: field.label,
              selected: _activeSearch.searchField == field,
              onPressed: () => Navigator.pop(menu, field),
            ),
        ],
      ),
    );
    if (field == null || !mounted) return;
    final pending = _activeSearch.selectSearchField(field);
    setState(() {});
    await pending;
  }
}

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({
    super.key,
    required this.books,
    required this.state,
    required this.repository,
    required this.onSearch,
    this.showHeader = true,
    this.feed,
    this.categoryTitle,
    this.onChooseCategory,
  });
  final List<Novel> books;
  final LibraryState state;
  final NovelRepository repository;
  final VoidCallback onSearch;
  final bool showHeader;
  final NovelFeedController? feed;
  final String? categoryTitle;
  final void Function(BuildContext context)? onChooseCategory;

  Widget buildHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: const ArchiveMasthead(
          title: '轻小说文库',
          code: 'WENKU8 / READING ARCHIVE',
          brand: true,
        ),
      ),
      if (WenkuFeaturesScope.maybeOf(context) case final features?)
        GlassIconButton(
          icon: CupertinoIcons.square_grid_2x2,
          label: '出版文库',
          onPressed: () => pushNovelPage<void>(
            context,
            PublicationLibraryPage(
              catalog: features.publications,
              account: features.account,
              repository: repository,
              state: state,
            ),
            reduceMotion: state.reduceMotion,
          ),
        ),
      GlassIconButton(
        icon: CupertinoIcons.search,
        label: '搜索',
        onPressed: onSearch,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => feed == null
      ? _buildContent(context, books)
      : ActiveListenableBuilder(
          listenable: feed!,
          builder: (context) => LoadedContentSequence(
            generation: feed!.resultRevision,
            firstIndex: feed!.resultStartIndex == 0
                ? 0
                : feed!.resultStartIndex + 2,
            child: _buildContent(context, feed!.items),
          ),
        );

  Widget _buildContent(BuildContext context, List<Novel> books) {
    final featuredCount = books.length.clamp(0, 10);
    Widget body;
    if (books.isEmpty && feed?.loading == true) {
      body = LibrarySkeleton(header: _categoryHeader(context));
    } else if (books.isEmpty && feed?.error != null) {
      body = ContentNotice(
        icon: CupertinoIcons.wifi_exclamationmark,
        title: '书籍加载失败',
        message: '检查网络后再试，已保存的书架与阅读记录仍保留。',
        onRetry: feed!.retry,
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical &&
              feed?.loading == false &&
              feed?.hasMore == true &&
              feed?.error == null &&
              notification.metrics.extentAfter <
                  math.max(800, notification.metrics.viewportDimension * 1.5)) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => feed?.loadMore(),
            );
          }
          return false;
        },
        child: KeyedSubtree(
          key: ValueKey((feed?.sort, feed?.tags.join('|'))),
          child: CustomScrollView(
            key: const PageStorageKey('discover'),
            clipBehavior: LibraryReflowScope.clipOf(context),
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: BookCollectionLayout.cacheExtentFor(
              MediaQuery.sizeOf(context).width - 48,
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _categoryHeader(context),
                      const SizedBox(height: 14),
                      if (books.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 90),
                          child: Center(child: AppText('暂无书籍')),
                        )
                      else ...[
                        ArchiveFileCarousel(
                          key: ValueKey(
                            'archive-files-${feed?.sort.name ?? 'recent'}-${books.first.id}',
                          ),
                          books: books
                              .take(featuredCount)
                              .toList(growable: false),
                          reduceMotion: state.reduceMotion,
                          animateEntrance: true,
                          onOpen: (book, tag) => openDetail(
                            context,
                            book,
                            state,
                            repository,
                            coverHeroTag: tag,
                          ),
                        ),
                        if (books.length > featuredCount ||
                            feed?.loading == true) ...[
                          const SizedBox(height: 32),
                          LoadedContentItem(
                            index: 2,
                            placeholder: const LoadingSkeleton(
                              layout: SkeletonLayout.actions,
                            ),
                            child: sectionHeader(context, '更多书籍', ''),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: BookCollectionSliver(
                  itemCount: books.length - featuredCount,
                  itemBuilder: (context, index) {
                    final book = books[index + featuredCount];
                    return LoadedContentItem(
                      key: ValueKey(book.id),
                      index: index + featuredCount + 2,
                      placeholder: const BookRowSkeleton(),
                      child: NovelRow(
                        novel: book,
                        coverHeroTag: CoverHeroTag(context, book.id),
                        onTap: () => openDetail(
                          context,
                          book,
                          state,
                          repository,
                          coverHeroTag: CoverHeroTag(context, book.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 120,
                ),
                sliver: SliverToBoxAdapter(
                  child: feed == null
                      ? const SizedBox.shrink()
                      : FeedFooter(feed: feed!),
                ),
              ),
            ],
          ),
        ),
      );
      if (feed != null) {
        body = FeedRefresh(feed: feed!, child: body);
      }
    }
    return GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: body,
    );
  }

  Widget _categoryHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: sectionHeader(
          context,
          categoryTitle ??
              (feed?.tags.isNotEmpty == true
                  ? feed!.tags.join(' · ')
                  : feed?.sort.label) ??
              '最近更新',
          '',
        ),
      ),
      if (feed != null)
        GlassMenuAnchor(
          child: Builder(
            builder: (buttonContext) => GlassIconButton(
              icon: CupertinoIcons.line_horizontal_3_decrease,
              label: '分类与排序',
              onPressed: () => onChooseCategory != null
                  ? onChooseCategory!(buttonContext)
                  : _chooseSort(buttonContext),
            ),
          ),
        ),
    ],
  );

  Future<void> _chooseSort(BuildContext context) async {
    final selected = await showJellySheet<DiscoverySelection>(
      context: context,
      reduceMotion: state.reduceMotion,
      heightFactor: .75,
      builder: (_) => DiscoveryFilters(
        sort: feed!.sort,
        books: feed!.items,
        selectedTags: feed!.tags.toSet(),
        availableTags: feed!.tagSuggestions,
      ),
    );
    if (!context.mounted || selected == null) return;
    if (selected.sort case final sort?) await feed!.selectSort(sort);
    if (selected.tags case final tags?) await feed!.selectTags(tags);
  }
}

/// Pull-to-refresh keeps content/scroll position and announces a bounded static
/// skeleton strip. There is no native spinner hidden behind the glass header.
class FeedRefresh extends StatelessWidget {
  const FeedRefresh({super.key, required this.feed, required this.child});
  final NovelFeedController feed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: RefreshIndicator.noSpinner(
          onRefresh: feed.refresh,
          child: child,
        ),
      ),
      if (feed.refreshing)
        Positioned(
          top: MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight,
          left: 24,
          right: 24,
          height: 64,
          child: IgnorePointer(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const LoadingSkeleton(
                key: ValueKey('feed-refresh-skeleton'),
                layout: SkeletonLayout.actions,
                label: '正在刷新书籍',
              ),
            ),
          ),
        ),
    ],
  );
}

class FeedFooter extends StatelessWidget {
  const FeedFooter({
    super.key,
    required this.feed,
    this.horizontalPadding = 24,
  });
  final NovelFeedController feed;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 20, horizontal: horizontalPadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (feed.loading)
          const BookCollectionSkeleton(rows: 2, label: '正在加载更多书籍')
        else if (feed.error != null) ...[
          AppText(
            feed.refreshFailed ? '刷新失败，已保留原列表' : '加载下一页失败',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          GlassTextButton(onPressed: feed.retry, child: const AppText('重试')),
        ] else if (feed.hasMore)
          GlassTextButton(
            onPressed: feed.loadMore,
            child: const AppText('加载更多'),
          )
        else if (feed.items.isNotEmpty)
          AppText(
            '已经到底了',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
      ],
    ),
  );
}

void openDetail(
  BuildContext context,
  Novel novel,
  LibraryState state,
  NovelRepository repository, {
  Object? coverHeroTag,
  bool fromCache = false,
  bool forceDetails = false,
}) {
  if (state.directReading && !forceDetails) {
    unawaited(
      pushNovelPage<void>(
        context,
        ReaderLoaderPage(
          novel: novel,
          state: state,
          repository: repository,
          fromCache: fromCache,
        ),
        reduceMotion: state.reduceMotion,
        slot: ('reader-entry', novel.id),
      ),
    );
    return;
  }
  if (LibraryWorkspace.open(
    context,
    novel.id,
    (_) => fromCache
        ? DetailPage(
            novel: novel,
            state: state,
            repository: repository,
            fromCache: true,
          )
        : DetailLoaderPage(novel: novel, state: state, repository: repository),
  )) {
    return;
  }
  unawaited(
    pushNovelPage<void>(
      context,
      fromCache
          ? DetailPage(
              novel: novel,
              state: state,
              repository: repository,
              fromCache: true,
              coverHeroTag: coverHeroTag,
            )
          : DetailLoaderPage(
              novel: novel,
              state: state,
              repository: repository,
              coverHeroTag: coverHeroTag,
            ),
      reduceMotion: state.reduceMotion,
      paperFlight: coverHeroTag != null,
      slot: 'detail',
      explorationKey: ('book', novel.id),
    ),
  );
}

/// One destination owns directory loading and reading, so Back never exposes
/// a transient loading route or a details page that the user chose to skip.
class ReaderLoaderPage extends StatefulWidget {
  const ReaderLoaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.fromCache = false,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final bool fromCache;
  @override
  State<ReaderLoaderPage> createState() => _ReaderLoaderPageState();
}

class _ReaderLoaderPageState extends State<ReaderLoaderPage> {
  late Future<Novel> _book = _load();
  Future<Novel> _load() async {
    Novel? book;
    if (widget.repository case final OfflineNovelRepository offline) {
      if (widget.fromCache || offline.offline) {
        if (!isLocalBook(widget.novel.id)) await offline.loadCache();
        book = await offline.cachedBook(widget.novel.id);
      }
    }
    book ??= (await widget.repository.detail(
      widget.novel,
    )).withChapters(await widget.repository.chapters(widget.novel.id));
    if (book.tags.isEmpty && widget.novel.tags.isNotEmpty) {
      book = book.withGenre(widget.novel.genre);
    }
    if (book.chapters.isEmpty) throw const FormatException('本书暂无可阅读的章节');
    await widget.state.rememberNovel(book);
    return book;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Novel>(
    future: _book,
    builder: (context, snapshot) {
      if (snapshot.data case final book?) {
        var chapter = widget.state.chapterForNovel(book);
        if (widget.repository case final OfflineNovelRepository offline) {
          if (offline.offline &&
              !isLocalBook(book.id) &&
              offline.cache
                      .book(book.id)
                      ?.chapterBytes
                      .containsKey(book.chapters[chapter].id) !=
                  true) {
            final cached = book.chapters.indexWhere(
              (c) =>
                  offline.cache.book(book.id)?.chapterBytes.containsKey(c.id) ==
                  true,
            );
            if (cached >= 0) chapter = cached;
          }
        }
        return ReaderPage(
          novel: book,
          state: widget.state,
          repository: widget.repository,
          initialChapter: chapter,
          directEntry: true,
        );
      }
      final preferences = widget.state.readerPreferences;
      final chromeVisible = widget.state.readerChromeVisible;
      return ReaderAppearance(
        state: widget.state,
        appTheme: Theme.of(context),
        child: Scaffold(
          body: Atmosphere(
            archiveBackdrop: false,
            child: GlassHeaderLayout(
              showHeader: chromeVisible || snapshot.hasError,
              header: ArchiveHeaderBar(
                leading: GlassIconButton(
                  icon: CupertinoIcons.back,
                  label: '返回',
                  onPressed: () => Navigator.pop(context),
                ),
                title: ArchiveRouteTitle(
                  title: widget.novel.title,
                  code: 'READ / OPEN',
                ),
              ),
              body: snapshot.hasError
                  ? ContentNotice(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      title: '暂时无法打开本书',
                      message: snapshot.error is FormatException
                          ? (snapshot.error as FormatException).message
                          : '请检查网络或本机缓存后重试',
                      onRetry: () => setState(() => _book = _load()),
                    )
                  : SafeArea(
                      top:
                          !(preferences.hideSystemStatus &&
                              preferences.mode == ReaderMode.scroll),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          preferences.leftMargin,
                          preferences.marginTop +
                              (chromeVisible
                                  ? FrostedHeader.toolbarHeight + 16
                                  : 16),
                          preferences.rightMargin,
                          preferences.marginBottom + 24,
                        ),
                        child: ReaderSkeleton(
                          vertical:
                              widget.state.readerPreferences.mode ==
                              ReaderMode.vertical,
                          expand: widget.state.readerPreferences.mode.paginated,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  );
}

void openReadingHistory(
  BuildContext context,
  LibraryState state,
  NovelRepository repository,
) => unawaited(
  pushNovelPage<void>(
    context,
    ReadingHistoryPage(
      state: state,
      repository: repository,
      onOpen: (pageContext, id, book) => openDetail(
        pageContext,
        book ??
            Novel(
              id: id,
              title: '书籍 $id',
              author: '',
              genre: '',
              summary: '',
              colors: const [Color(0xFF202020), Color(0xFF333333)],
            ),
        state,
        repository,
      ),
    ),
    reduceMotion: state.reduceMotion,
  ),
);

class NovelRow extends StatelessWidget {
  const NovelRow({
    super.key,
    required this.novel,
    required this.onTap,
    this.trailing,
    this.coverHeroTag,
    this.sourceLabel,
  });
  final Novel novel;
  final VoidCallback onTap;
  final Widget? trailing;
  final Object? coverHeroTag;
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) => JellyTapSurface(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Semantics(
                label: novel.title,
                image: true,
                child: NovelCover(
                  novel,
                  width: 56,
                  height: 76,
                  heroTag: coverHeroTag,
                ),
              ),
              if (sourceLabel != null)
                Positioned(
                  top: 3,
                  right: 3,
                  child: BookSourceBadge(sourceLabel!),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArchiveCode(ArchiveDesign.fileCode(novel.id)),
                const SizedBox(height: 4),
                AppText(
                  novel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 7),
                AppText(
                  novel.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const Icon(CupertinoIcons.chevron_right, size: 15),
        ],
      ),
    ),
  );
}

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.books,
    required this.state,
    required this.repository,
    this.showHeader = true,
    this.onSearch,
    this.navigation,
  });
  final List<Novel> books;
  final LibraryState state;
  final NovelRepository repository;
  final bool showHeader;
  final VoidCallback? onSearch;
  final HomeNavigation? navigation;

  Widget buildHeader(BuildContext context, {VoidCallback? search}) =>
      AnimatedBuilder(
        animation: state.navigationChanges,
        builder: (context, _) => Row(
          children: [
            Expanded(
              child: const ArchiveMasthead(
                title: '书架',
                code: '02 / PERSONAL ARCHIVE',
              ),
            ),
            GlassIconButton(
              icon: CupertinoIcons.clock,
              label: '阅读历史',
              onPressed: () => openReadingHistory(context, state, repository),
            ),
            if (state.combinedShelf && repository is OfflineNovelRepository)
              if ((repository as OfflineNovelRepository).local
                  case final local?)
                LocalBookImportButton(
                  books: local,
                  library: state,
                  onManage: () => pushNovelPage<void>(
                    context,
                    LocalLibraryPage(
                      books: local,
                      state: state,
                      onOpen: (page, book) =>
                          openDetail(page, book, state, repository),
                      onOpenWithCover: (page, book, tag) => openDetail(
                        page,
                        book,
                        state,
                        repository,
                        coverHeroTag: tag,
                      ),
                    ),
                    reduceMotion: state.reduceMotion,
                  ),
                ),
            GlassIconButton(
              key: const ValueKey('shelf-search-entry'),
              icon: CupertinoIcons.search,
              label: '搜索书架',
              onPressed: onSearch ?? search,
            ),
          ],
        ),
      );

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

enum _ShelfSort { recentRead, recentAdded, title }

class _ShelfPageState extends State<ShelfPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _modeTransition;
  late bool _lastCacheOnly;
  final _cacheAvailability = ValueNotifier(0);
  Set<int> _availableIds = const {};
  bool _cacheLoaded = false, _cacheFailed = false;
  OfflineNovelRepository? get _offline =>
      widget.repository is OfflineNovelRepository
      ? widget.repository as OfflineNovelRepository
      : null;
  bool get _cacheOnly =>
      widget.navigation?.readableShelfOnly ??
      (state.localReaderMode ||
          (state.adaptWhenOffline && _offline?.offline == true));
  bool _lastCombined = false;
  final Map<int, Future<Novel?>> _requests = {};
  String? _previewKey;
  Future<List<Novel>>? _previewRequest;
  final _query = TextEditingController();
  bool _standaloneSearch = false;
  _ShelfSort get _sort =>
      _ShelfSort.values.firstWhere((sort) => sort.name == state.shelfSort);
  LibraryState get state => widget.state;
  late final _changes = Listenable.merge([
    state,
    state.historyChanges,
    state.shelfViewChanges,
    if (widget.navigation != null) widget.navigation!,
    _cacheAvailability,
    state.organization,
    if (_offline?.local != null) _offline!.local!,
  ]);

  @override
  void initState() {
    super.initState();
    _modeTransition = AnimationController(
      vsync: this,
      duration: NovelMotion.enter,
      value: 1,
    );
    _lastCacheOnly = _cacheOnly;
    _lastCombined = state.combinedShelf;
    _offline?.addListener(_offlineCacheChanged);
    widget.navigation?.addListener(_modeChanged);
    state.navigationChanges.addListener(_modeChanged);
    if (state.combinedShelf && _offline != null) {
      unawaited(_offline!.loadCache().catchError((Object _) {}));
    }
  }

  void _modeChanged() {
    if (_lastCacheOnly == _cacheOnly && _lastCombined == state.combinedShelf) {
      return;
    }
    _lastCacheOnly = _cacheOnly;
    _lastCombined = state.combinedShelf;
    if (state.combinedShelf && _offline?.cache.loaded == false) {
      unawaited(_offline!.loadCache().catchError((Object _) {}));
    }
    if (state.effectiveReduceMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _modeTransition.value = 1;
    } else {
      _modeTransition.forward(from: 0);
    }
  }

  Widget _modeMotion(int index, Widget child) => AnimatedBuilder(
    animation: _modeTransition,
    child: child,
    builder: (context, child) {
      final delay = (index * .07).clamp(0.0, .24);
      final progress = Curves.easeOutCubic.transform(
        ((_modeTransition.value - delay) / (1 - delay)).clamp(0.0, 1.0),
      );
      return Transform.translate(
        offset: Offset(-8, 10) * (1 - progress),
        child: child,
      );
    },
  );

  void _offlineCacheChanged() {
    if (!_cacheOnly && !state.combinedShelf) return;
    final source = _offline!;
    final ids = {
      for (final book in source.cache.books)
        if (book.cachedCount > 0) book.novel.id,
    };
    final loaded = source.cache.loaded;
    final failed = source.cacheError != null;
    if (setEquals(ids, _availableIds) &&
        loaded == _cacheLoaded &&
        failed == _cacheFailed) {
      return;
    }
    _availableIds = ids;
    _cacheLoaded = loaded;
    _cacheFailed = failed;
    _cacheAvailability.value++;
  }

  @override
  void dispose() {
    widget.navigation?.removeListener(_modeChanged);
    state.navigationChanges.removeListener(_modeChanged);
    _modeTransition.dispose();
    _offline?.removeListener(_offlineCacheChanged);
    _cacheAvailability.dispose();
    _query.dispose();
    super.dispose();
  }

  bool _matches(int id) {
    if (_cacheOnly && _offline?.availableOffline(id) != true) return false;
    if (!bookshelfMatchesCategory(id, state)) return false;
    final book = _known(id);
    final term = _query.text.trim().toLowerCase();
    if (term.isNotEmpty &&
        !'$id ${book?.title ?? ''} ${book?.author ?? ''}'
            .toLowerCase()
            .contains(term)) {
      return false;
    }
    final read = state.hasRead(id);
    final finished = book != null && state.finishedReading(book);
    return switch (state.shelfFilter) {
      'unread' => !read,
      'reading' => read && !finished,
      'finished' => finished,
      _ => true,
    };
  }

  Novel? _known(int id) {
    final local = _offline?.local?.book(id);
    if (local != null) return local;
    if (_cacheOnly || state.combinedShelf) {
      final cached = _offline?.cache.book(id)?.novel;
      if (cached != null) return cached;
    }
    final cached = state.cachedNovel(id);
    if (cached != null) return cached;
    for (final book in widget.books) {
      if (book.id == id) return book;
    }
    return null;
  }

  Future<Novel?> _resolve(int id) async {
    final book = await widget.repository.find(id);
    if (book != null) await state.rememberNovel(book);
    return book;
  }

  Future<List<Novel>> _resolvePreview(List<int> ids) async {
    final resolved = <int, Novel>{};
    var cursor = 0;
    Future<void> next() async {
      while (cursor < ids.length) {
        final id = ids[cursor++];
        try {
          final book =
              _known(id) ?? await _requests.putIfAbsent(id, () => _resolve(id));
          if (book != null) resolved[id] = book;
        } catch (_) {
          // Failed books keep the existing retry/remove actions in the list.
        }
      }
    }

    await Future.wait(List.generate(ids.length.clamp(0, 4), (_) => next()));
    return [
      for (final id in ids)
        if (resolved[id] != null) resolved[id]!,
    ];
  }

  Widget _preview(List<int> ids) {
    Widget carousel(List<Novel> books) => ArchiveFileCarousel(
      key: ValueKey((
        'bookshelf-preview',
        state.shelfSort,
        state.shelfFilter,
        state.organization.shelfSelected,
      )),
      books: books,
      reduceMotion: state.reduceMotion,
      animateEntrance: true,
      sourceLabel: state.combinedShelf
          ? (book) => bookshelfSource(book.id, _offline)
          : null,
      onOpen: (book, tag) => openDetail(
        context,
        book,
        state,
        widget.repository,
        coverHeroTag: tag,
      ),
    );
    final known = [for (final id in ids) ?_known(id)];
    final ready = known.length == ids.length;
    final key = ids.join(',');
    if (!ready && _previewKey != key) {
      _previewKey = key;
      _previewRequest = _resolvePreview(ids);
    }
    return FutureBuilder<List<Novel>>(
      // Keep the same parent for resolved and asynchronously resolved books.
      // Reparenting the carousel on a later rebuild loses its Hero identity.
      key: const ValueKey('shelf-preview-state'),
      future: ready ? null : _previewRequest,
      initialData: ready ? known : null,
      builder: (context, snapshot) {
        if (!ready && snapshot.connectionState != ConnectionState.done) {
          return const ArchiveShelfSkeleton();
        }
        final books = ready ? known : snapshot.data ?? const <Novel>[];
        if (books.isNotEmpty) return carousel(books);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              const AppText('立体书架暂未载入，下方列表仍可整理书籍。'),
              const SizedBox(height: 12),
              GlassTextButton(
                onPressed: () => setState(() {
                  for (final id in ids) {
                    if (_known(id) == null) _requests.remove(id);
                  }
                  _previewKey = null;
                }),
                child: const AppText('重新载入'),
              ),
            ],
          ),
        );
      },
    );
  }

  int _compare(int a, int b) {
    final result = switch (_sort) {
      _ShelfSort.recentRead =>
        state.lastReadAt(b).compareTo(state.lastReadAt(a)),
      _ShelfSort.recentAdded => _addedAt(b).compareTo(_addedAt(a)),
      _ShelfSort.title => (_known(a)?.title ?? '$a').compareTo(
        _known(b)?.title ?? '$b',
      ),
    };
    if (result != 0) return result;
    final added = _addedAt(b).compareTo(_addedAt(a));
    return added != 0 ? added : a.compareTo(b);
  }

  int _addedAt(int id) => isLocalBook(id)
      ? _offline?.local?.importedAt(id) ?? 0
      : state.addedAt(id);

  @override
  Widget build(BuildContext context) => ActiveListenableBuilder(
    listenable: _changes,
    builder: (context) {
      final all = bookshelfIds(
        state,
        _offline,
        readableOnly: _cacheOnly,
        filterCategory: false,
      );
      final saved = all.where(_matches).toList()..sort(_compare);
      final cacheLoading =
          (_cacheOnly || state.combinedShelf) &&
          _offline?.cache.loaded == false &&
          _offline?.cacheError == null;
      final showPreview = state.shelfLayout == 'shelf' && saved.isNotEmpty;
      final previewRows = showPreview ? 2 : 0;
      return GlassHeaderLayout(
        showHeader: widget.showHeader,
        header: widget.onSearch != null || state.combinedShelf
            ? widget.buildHeader(
                context,
                search: () =>
                    setState(() => _standaloneSearch = !_standaloneSearch),
              )
            : Row(
                children: [
                  const Expanded(
                    child: ArchiveMasthead(
                      title: '书架',
                      code: '02 / PERSONAL ARCHIVE',
                    ),
                  ),
                  GlassIconButton(
                    icon: CupertinoIcons.search,
                    label: '搜索书架',
                    onPressed: () =>
                        setState(() => _standaloneSearch = !_standaloneSearch),
                  ),
                ],
              ),
        body: cacheLoading
            ? LibrarySkeleton(featured: state.shelfLayout == 'shelf')
            : _cacheOnly &&
                  _offline?.cache.loaded == false &&
                  _offline?.cacheError != null
            ? ContentNotice(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: '离线书库暂未载入',
                message: '缓存目录读取失败，请重试',
                onRetry: () => _offline!.loadCache().catchError((Object _) {}),
              )
            : BookCollectionView.builder(
                key: const PageStorageKey('shelf'),
                leadingCount: saved.isEmpty ? 2 : 1 + previewRows,
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  MediaQuery.paddingOf(context).bottom + 120,
                ),
                itemCount: saved.isEmpty ? 2 : saved.length + 1 + previewRows,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_standaloneSearch)
                            AppSearchField(
                              inputKey: const ValueKey('shelf-search'),
                              controller: _query,
                              hint: '在书架中查找书名、作者或 ID',
                              onChanged: (_) => setState(() {}),
                            ),
                          if (_standaloneSearch) const SizedBox(height: 10),
                          LibraryToolbar(
                            categoryKey: const ValueKey('shelf-category'),
                            optionsKey: const ValueKey('shelf-view'),
                            manageKey: const ValueKey('shelf-manage-local'),
                            onManage:
                                state.combinedShelf &&
                                    _offline?.local != null &&
                                    _offline!.local!.books.isNotEmpty
                                ? () => openLocalBookBatch(
                                    context,
                                    books: _offline!.local!,
                                    library: state,
                                  )
                                : null,
                            category: state.organization.nameOf(
                              state.organization.shelfSelected,
                            ),
                            count: saved.length,
                            activeFilters:
                                (state.shelfFilter == 'all' ? 0 : 1) +
                                (state.combinedShelf &&
                                        state.shelfSourceFilter != 'all'
                                    ? 1
                                    : 0),
                            onCategory: () => showBookCategories(
                              context,
                              state.organization,
                              shelf: true,
                              reduceMotion: state.reduceMotion,
                            ),
                            onOptions: _libraryOptions,
                          ),
                        ],
                      ),
                    );
                  }
                  if (saved.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 90),
                      child: Column(
                        children: [
                          Icon(
                            CupertinoIcons.book,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            size: 34,
                          ),
                          const SizedBox(height: 18),
                          AppText(
                            all.isNotEmpty ||
                                    state.combinedShelf &&
                                        state.shelfSourceFilter != 'all'
                                ? '没有符合条件的书'
                                : _cacheOnly
                                ? '没有可离线阅读的书'
                                : state.shelf.isEmpty
                                ? '书架还空着'
                                : '没有符合条件的书',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AppText(
                            _cacheOnly
                                ? state.combinedShelf
                                      ? '缓存正文或导入本地书籍后即可在这里阅读'
                                      : '已缓存正文的收藏会显示在这里，本地导入请到「本地」阅读'
                                : state.combinedShelf && all.isEmpty
                                ? '收藏、缓存或点击右上角 ＋ 导入书籍'
                                : state.shelf.isEmpty
                                ? '在发现页收藏喜欢的书'
                                : '试试其他关键词或切回全部',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (showPreview && index == 1) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _preview(saved.take(10).toList()),
                    );
                  }
                  if (showPreview && index == 2) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: ArchiveSection(
                        title: '全部书籍',
                        code: 'PERSONAL / INDEX',
                      ),
                    );
                  }
                  final rowIndex = index - 1 - previewRows;
                  final id = saved[rowIndex];
                  final book = _known(id);
                  return FutureBuilder<Novel?>(
                    key: ValueKey('shelf-resolve-$id'),
                    initialData: book,
                    future: book == null
                        ? _requests.putIfAbsent(id, () => _resolve(id))
                        : _requests[id],
                    builder: (context, snapshot) {
                      final resolved = book ?? snapshot.data;
                      final pending =
                          snapshot.connectionState != ConnectionState.done;
                      return _modeMotion(
                        rowIndex,
                        LoadedContentSequence(
                          generation: resolved?.id,
                          child: resolved != null
                              ? LoadedContentItem(
                                  index: rowIndex,
                                  placeholder: const BookRowSkeleton(),
                                  child: _row(context, resolved),
                                )
                              : pending
                              ? BookRowSkeleton(label: '正在载入书籍 $id')
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.book, size: 26),
                                      const SizedBox(width: 15),
                                      Expanded(child: AppText('书籍 $id 暂未载入')),
                                      GlassTextButton(
                                        onPressed: () => setState(() {
                                          _requests[id] = _resolve(id);
                                        }),
                                        child: const AppText('重试'),
                                      ),
                                      GlassMenuAnchor(
                                        child: Builder(
                                          builder: (buttonContext) =>
                                              GlassIconButton(
                                                icon: CupertinoIcons.ellipsis,
                                                label: '书籍 $id 书架操作',
                                                onPressed: () => _bookMenu(
                                                  buttonContext,
                                                  id,
                                                ),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    },
                  );
                },
              ),
      );
    },
  );

  Widget _row(BuildContext context, Novel book) => NovelRow(
    key: ValueKey('shelf-book-${book.id}'),
    novel: book,
    sourceLabel: state.combinedShelf
        ? bookshelfSource(book.id, _offline)
        : null,
    coverHeroTag: CoverHeroTag(this, book.id),
    onTap: () => openDetail(
      context,
      book,
      state,
      widget.repository,
      coverHeroTag: CoverHeroTag(this, book.id),
      fromCache: _cacheOnly,
    ),
    trailing: SizedBox(
      width: 74,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuAnchor(
            child: Builder(
              builder: (buttonContext) => GlassIconButton(
                icon: CupertinoIcons.ellipsis,
                label: '${book.title}书架操作',
                onPressed: () => _bookMenu(buttonContext, book.id, book: book),
              ),
            ),
          ),
          AppText(
            !state.hasRead(book.id)
                ? '未读'
                : state.finishedReading(book)
                ? '已读完'
                : (book.chapters.isNotEmpty || book.chapterCount > 0)
                ? '${state.chapterForNovel(book) + 1}/${book.chapters.isNotEmpty ? book.chapters.length : book.chapterCount}'
                : '第 ${state.chapterFor(book.id) + 1} 章',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _libraryOptions() => showJellySheet<void>(
    context: context,
    reduceMotion: state.reduceMotion,
    heightFactor: .78,
    builder: (_) => AnimatedBuilder(
      animation: state.shelfViewChanges,
      builder: (context, _) {
        void save({
          String? layout,
          String? filter,
          String? source,
          String? sort,
        }) {
          unawaited(
            state
                .setShelfView(
                  layout: layout,
                  filter: filter,
                  source: source,
                  sort: sort,
                )
                .catchError((Object _) {
                  if (mounted) showNovelFeedback(this.context, '书架偏好保存失败，请重试');
                }),
          );
        }

        return LibraryViewOptions(
          shelf: state.shelfLayout == 'shelf',
          reading: state.shelfFilter,
          sort: state.shelfSort,
          source: state.combinedShelf ? state.shelfSourceFilter : null,
          onView: (v) => save(layout: v ? 'shelf' : 'list'),
          onReading: (v) => save(filter: v),
          onSource: (v) => save(source: v),
          onSort: (v) => save(sort: v),
        );
      },
    ),
  );

  Future<void> _bookMenu(BuildContext context, int id, {Novel? book}) async {
    if (isLocalBook(id) && book != null && _offline?.local != null) {
      await pushNovelPage<LocalBookEditResult>(
        context,
        LocalBookEditor(book: book, books: _offline!.local!, library: state),
        reduceMotion: state.reduceMotion,
      );
      return;
    }
    final action = await showGlassMenu<String>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menuContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuItem(
            label: '移至分类',
            onPressed: () => Navigator.pop(menuContext, 'category'),
          ),
          GlassMenuItem(
            order: 1,
            label: !state.contains(id)
                ? '加入收藏书架'
                : state.combinedShelf && _offline?.availableOffline(id) == true
                ? '取消收藏（保留缓存）'
                : '移出书架',
            onPressed: () => Navigator.pop(
              menuContext,
              state.contains(id) ? 'remove' : 'add',
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'add') {
      try {
        await state.setShelfMembership(id, true, novel: book);
      } catch (_) {
        if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
      }
      return;
    }
    if (action == 'category') {
      final group = await chooseBookCategory(
        this.context,
        state.organization,
        bookId: id,
        reduceMotion: state.reduceMotion,
      );
      if (group != null) {
        try {
          await state.organization.assign(id, group);
        } catch (_) {
          if (mounted) showNovelFeedback(this.context, '分类保存失败，请重试');
        }
      }
      return;
    }
    if (action != 'remove' || !state.contains(id)) return;
    final addedAt = state.addedAt(id);
    try {
      await state.setShelfMembership(id, false);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
      return;
    }
    final revision = state.shelfRevision(id);
    if (!mounted) return;
    showNovelFeedback(
      this.context,
      state.combinedShelf && _offline?.availableOffline(id) == true
          ? '已取消收藏，缓存仍在书架中'
          : '已移出书架',
      actionLabel: '撤销',
      action: () async {
        if (!state.contains(id) && state.shelfRevision(id) == revision) {
          await state.setShelfMembership(
            id,
            true,
            novel: book,
            restoredAddedAt: addedAt,
          );
        }
      },
    );
  }
}

Future<void> openLocalLibrary(
  BuildContext context,
  LocalBookStore books,
  LibraryState state,
  NovelRepository repository,
) => pushNovelPage<void>(
  context,
  LocalLibraryPage(
    books: books,
    state: state,
    onOpen: (page, novel) => openDetail(page, novel, state, repository),
    onOpenWithCover: (page, novel, tag) =>
        openDetail(page, novel, state, repository, coverHeroTag: tag),
  ),
  reduceMotion: state.reduceMotion,
);

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    this.repository,
    this.showHeader = true,
  });
  final LibraryState state;
  final NovelRepository? repository;
  final bool showHeader;

  Widget buildHeader(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: const ArchiveMasthead(title: '设置', code: '04 / SYSTEM PROFILE'),
  );

  @override
  Widget build(BuildContext context) => ActiveListenableBuilder(
    listenable: state.settingsChanges,
    builder: (context) => GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: ListView(
        key: const PageStorageKey('settings'),
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          MediaQuery.paddingOf(context).bottom + 120,
        ),
        children: [
          _sectionEntry(
            context,
            id: 'usage',
            title: '使用方式',
            subtitle: '点书续读、合并书架与离线适配',
            code: 'SYSTEM / USAGE',
            icon: CupertinoIcons.square_grid_2x2,
            options: _usageOptions,
          ),
          const SizedBox(height: 14),
          _sectionEntry(
            context,
            id: 'reading',
            title: '阅读与外观',
            subtitle: '外观模式、字体、字号与听书',
            code: 'SYSTEM / READING',
            icon: CupertinoIcons.textformat,
            options: _readingOptions,
          ),
          const SizedBox(height: 14),
          _sectionEntry(
            context,
            id: 'effects',
            title: '性能与动效',
            subtitle: '帧率偏好、玻璃材质与动态效果',
            code: 'SYSTEM / EFFECTS',
            icon: CupertinoIcons.speedometer,
            options: _effectsOptions,
          ),
          const SizedBox(height: 14),
          _sectionEntry(
            context,
            id: 'data',
            title: '数据与存储',
            subtitle: '阅读历史、缓存管理与备份恢复',
            code: 'SYSTEM / STORAGE',
            icon: CupertinoIcons.folder,
            options: _dataOptions,
          ),
        ],
      ),
    ),
  );

  Widget _sectionEntry(
    BuildContext context, {
    required String id,
    required String title,
    required String subtitle,
    required String code,
    required IconData icon,
    required List<Widget> Function(BuildContext) options,
  }) => FeatureEntry(
    key: ValueKey('settings-$id-entry'),
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: () => pushNovelPage<void>(
      context,
      ArchiveFeaturePage(
        key: ValueKey('settings-$id-page'),
        title: title,
        code: code,
        child: ActiveListenableBuilder(
          listenable: state.settingsChanges,
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                key: PageStorageKey('settings-$id'),
                padding: featurePadding(context).add(
                  EdgeInsets.only(
                    left: MediaQuery.paddingOf(context).left,
                    right: MediaQuery.paddingOf(context).right,
                  ),
                ),
                children: options(context),
              ),
            ),
          ),
        ),
      ),
      reduceMotion: state.reduceMotion,
      slot: ('settings', id),
    ),
  );

  List<Widget> _usageOptions(BuildContext context) => [
    ContentPanel(
      child: Column(
        children: [
          _toggleSetting(
            context,
            keyName: 'settings-direct-reading',
            icon: CupertinoIcons.book_fill,
            title: '点书直接阅读',
            description: '从上次位置继续；书籍详情可在阅读器右上角打开',
            value: state.directReading,
            onChanged: state.setDirectReading,
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-combined-shelf',
            icon: CupertinoIcons.square_stack,
            title: '合并书架',
            description: '缓存与本地书统一显示在书架，隐藏底部本地入口',
            value: state.combinedShelf,
            onChanged: (value) => state.setNavigationMode(combinedShelf: value),
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-adapt-offline',
            icon: CupertinoIcons.wifi_slash,
            title: '离线适配',
            description: state.combinedShelf
                ? '断网后隐藏发现，书架保留缓存和本地书籍'
                : '断网后隐藏发现，书架只显示已缓存的收藏',
            value: state.adaptWhenOffline,
            onChanged: (value) =>
                state.setNavigationMode(adaptWhenOffline: value),
          ),
          const Divider(height: 22),
          _toggleSetting(
            context,
            keyName: 'settings-local-reader-mode',
            icon: CupertinoIcons.book,
            title: '阅读器模式',
            description: state.combinedShelf ? '只显示离线可读的合并书架和我的' : '只显示本地和我的',
            value: state.localReaderMode,
            onChanged: (value) =>
                state.setNavigationMode(localReaderMode: value),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _readingOptions(BuildContext context) => [
    ContentPanel(
      child: Column(
        children: [
          _appearanceSetting(context),
          const Divider(height: 22),
          FeatureEntry(
            title: '主页背景颜色',
            icon: CupertinoIcons.paintbrush,
            subtitle:
                state.homeBackgroundFor(Theme.of(context).brightness) == null
                ? '当前模式跟随默认外观'
                : backgroundHex(
                    state.homeBackgroundFor(Theme.of(context).brightness)!,
                  ),
            onTap: () => pushNovelPage<void>(
              context,
              HomeBackgroundPage(state: state),
              reduceMotion: state.reduceMotion,
            ),
          ),
          const Divider(height: 22),
          FeatureEntry(
            title: '阅读背景图片',
            icon: CupertinoIcons.photo,
            subtitle: '导入图片、显示方式与遮罩',
            onTap: () => pushNovelPage<void>(
              context,
              ReaderBackgroundPage(state: state),
              reduceMotion: state.reduceMotion,
            ),
          ),
          const Divider(height: 22),
          LanguageSettingMenu(
            key: const ValueKey('settings-language'),
            state: state,
          ),
          const Divider(height: 22),
          JellyTapSurface(
            key: const ValueKey('settings-fonts'),
            onTap: () => pushNovelPage<void>(
              context,
              FontSettingsPage(state: state),
              reduceMotion: state.reduceMotion,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.textformat, size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                    child: const AppText(
                      '字体',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.chevron_forward, size: 14),
                ],
              ),
            ),
          ),
          const Divider(height: 22),
          ReaderValueSlider(
            sliderKey: const ValueKey('settings-font-slider'),
            label: '阅读字号',
            value: state.fontSize,
            min: 15,
            max: 27,
            divisions: 12,
            format: (value) => '${value.round()} pt',
            onCommitted: (value) =>
                _savePreference(context, () => state.setFontSize(value)),
          ),
          if (LocalPlatform.android)
            Row(
              children: [
                Icon(
                  CupertinoIcons.sun_max,
                  size: 21,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: AppText(
                    '阅读时保持亮屏',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: state.keepScreenOn,
                  onChanged: (value) => _savePreference(
                    context,
                    () => state.setKeepScreenOn(value),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
    if (LocalPlatform.android) ...[
      if (ListeningScope.maybeOf(context) case final listening?)
        if (listening.customSpeech case final settings?) ...[
          const SizedBox(height: 14),
          FeatureEntry(
            title: '自定义语音接口',
            subtitle: 'Microsoft SSML 兼容服务',
            icon: CupertinoIcons.waveform,
            onTap: () => pushNovelPage<void>(
              context,
              CustomSpeechPage(settings: settings, controller: listening),
              reduceMotion: state.reduceMotion,
            ),
          ),
        ],
    ],
  ];

  List<Widget> _effectsOptions(BuildContext context) => [
    sectionHeader(context, '玻璃外观', '实时预览'),
    const SizedBox(height: 14),
    ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _glassSettingLabel(context, '模糊度', '${state.glassBlur.round()}'),
          AppControls.slider(
            context,
            key: const ValueKey('glass-blur-slider'),
            value: state.glassBlur,
            min: 0,
            max: 24,
            divisions: 24,
            onChanged: (value) => state.setGlassBlur(value, persist: false),
            onChangeEnd: state.setGlassBlur,
          ),
          const Divider(height: 22),
          _glassSettingLabel(
            context,
            '不透明度',
            '${(state.glassOpacity * 100).round()}%',
          ),
          AppControls.slider(
            context,
            key: const ValueKey('glass-opacity-slider'),
            value: state.glassOpacity,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: (value) => state.setGlassOpacity(value, persist: false),
            onChangeEnd: state.setGlassOpacity,
          ),
          GlassTextButton(
            onPressed: () async {
              await state.setGlassBlur(8);
              await state.setGlassOpacity(.87);
            },
            child: const AppText('恢复默认'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    ContentPanel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.circle_grid_3x3,
                  color: Theme.of(context).colorScheme.primary,
                  size: 21,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: AppText(
                    '减少动态效果',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                AppControls.toggle(
                  context,
                  value: state.reduceMotion,
                  onChanged: (value) => _savePreference(
                    context,
                    () => state.setReduceMotion(value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    const FrameRateOptions(),
    const SizedBox(height: 24),
    ContentPanel(
      key: const ValueKey('settings-performance'),
      onTap: () => pushNovelPage<void>(
        context,
        LowPerformancePage(state: state),
        reduceMotion: state.reduceMotion,
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.speedometer, size: 21),
          SizedBox(width: 12),
          Expanded(
            child: AppText(
              '低性能设备模式',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
  ];

  List<Widget> _dataOptions(BuildContext context) => [
    if (repository case final NovelRepository source) ...[
      sectionHeader(context, '阅读记录', ''),
      const SizedBox(height: 14),
      ContentPanel(
        onTap: () => openReadingHistory(context, state, source),
        child: const Row(
          children: [
            Icon(CupertinoIcons.clock, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: AppText(
                '阅读历史',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 14),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
    if (repository case final OfflineNovelRepository offline) ...[
      if (offline.local != null) ...[
        FeatureEntry(
          key: const ValueKey('settings-removed-local-books'),
          title: '已移出的本地书',
          subtitle: '恢复保留在本机的书籍，或删除其文件',
          icon: CupertinoIcons.book,
          onTap: () => pushNovelPage<void>(
            context,
            RemovedLocalBooksPage(books: offline.local!, library: state),
            reduceMotion: state.reduceMotion,
          ),
        ),
        const SizedBox(height: 24),
      ],
      sectionHeader(context, '离线阅读', ''),
      const SizedBox(height: 14),
      ContentPanel(
        onTap: () => pushNovelPage<void>(
          context,
          OfflineCachePage(
            repository: offline,
            reduceMotion: state.reduceMotion,
            onOpen: (pageContext, novel) =>
                openDetail(pageContext, novel, state, offline, fromCache: true),
          ),
          reduceMotion: state.reduceMotion,
        ),
        child: const Row(
          children: [
            Icon(CupertinoIcons.cloud_download, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: AppText(
                '缓存管理',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 14),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
    sectionHeader(context, '备份与清理', ''),
    const SizedBox(height: 14),
    ContentPanel(
      key: const ValueKey('settings-backup'),
      onTap: () => pushNovelPage<void>(
        context,
        LibraryBackupPage(state: state),
        reduceMotion: state.reduceMotion,
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.folder, size: 21),
          SizedBox(width: 12),
          Expanded(
            child: AppText(
              '备份与恢复',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
    if (LocalPlatform.android) ...[
      const SizedBox(height: 14),
      FeatureEntry(
        key: const ValueKey('settings-legacy-import'),
        title: '导入旧版文库记录',
        icon: CupertinoIcons.folder_badge_plus,
        subtitle: '预览后合并，保留较新的阅读进度',
        onTap: () => pushNovelPage<void>(
          context,
          LegacyImportPage(state: state),
          reduceMotion: state.reduceMotion,
        ),
      ),
      const SizedBox(height: 14),
      FeatureEntry(
        title: '清理插图缓存',
        icon: CupertinoIcons.photo,
        subtitle: '不影响书架、正文缓存和阅读记录',
        onTap: () async {
          if (!await confirmNovelAction(
            context,
            title: '清理已下载的插图？',
            message: '插图下次查看时重新下载，正文和阅读记录仍保留。',
            confirmLabel: '清理插图',
            reduceMotion: state.reduceMotion,
          )) {
            return;
          }
          try {
            await LegacyTransport.clearIllustrations();
            ReaderIllustrationCache.shared.clearMemory();
            if (context.mounted) showNovelFeedback(context, '插图缓存已清理');
          } catch (_) {
            if (context.mounted) showNovelFeedback(context, '缓存清理失败，请重试');
          }
        },
      ),
    ],
  ];

  Widget _appearanceSetting(BuildContext context) =>
      GlassSettingMenu<ThemeMode>(
        key: const ValueKey('settings-appearance'),
        icon: CupertinoIcons.moon_stars,
        label: '外观模式',
        value: state.theme,
        options: const {
          ThemeMode.system: '跟随系统',
          ThemeMode.light: '浅色',
          ThemeMode.dark: '深色',
        },
        reduceMotion: state.reduceMotion,
        onChanged: (value) =>
            _savePreference(context, () => state.setTheme(value)),
      );

  Widget _glassSettingLabel(BuildContext context, String title, String value) =>
      Row(
        children: [
          Expanded(
            child: AppText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          AppText(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  Widget _toggleSetting(
    BuildContext context, {
    required String keyName,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: AppText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          AppControls.toggle(
            context,
            key: ValueKey(keyName),
            value: value,
            onChanged: (value) =>
                _savePreference(context, () => onChanged(value)),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 33, top: 4),
        child: AppText(
          description,
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  Future<void> _savePreference(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    try {
      await save();
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '设置保存失败，请重试');
    }
  }
}

class InlineSearchResults extends StatelessWidget {
  const InlineSearchResults({
    super.key,
    required this.state,
    required this.repository,
    required this.feed,
    required this.onOpenBook,
    this.onRecall,
    this.emptyQueryTitle = '你可能会喜欢',
    this.showSources = false,
    this.fromCache = false,
  });
  final LibraryState state;
  final NovelRepository repository;
  final NovelFeedController feed;
  final VoidCallback onOpenBook;
  final ValueChanged<String>? onRecall;
  final String emptyQueryTitle;
  final bool showSources, fromCache;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => LoadedContentSequence(
      generation: feed.resultRevision,
      firstIndex: feed.resultStartIndex == 0 ? 0 : feed.resultStartIndex + 1,
      child: _buildResults(context),
    ),
  );

  Widget _buildResults(BuildContext context) {
    final books = feed.items;
    if (books.isEmpty &&
        feed.query.isEmpty &&
        onRecall != null &&
        state.recentSearches.isNotEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          24,
        ),
        children: [
          RecentSearches(state: state, onRecall: onRecall!),
          if (feed.loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: BookCollectionSkeleton(rows: 2),
            )
          else if (feed.error != null)
            Column(
              children: [
                const AppText('推荐载入失败，仍可搜索书名或作者'),
                GlassTextButton(
                  onPressed: feed.retry,
                  child: const AppText('重试'),
                ),
              ],
            )
          else
            const AppText('搜索书名或作者，开始寻找故事。'),
        ],
      );
    }
    if (books.isEmpty && feed.loading) {
      return const SearchSkeleton();
    }
    if (books.isEmpty && feed.error != null) {
      return ContentNotice(
        icon: CupertinoIcons.wifi_exclamationmark,
        title: '搜索失败，请稍后重试',
        onRetry: feed.retry,
      );
    }
    if (books.isEmpty) {
      return const ContentNotice(
        icon: CupertinoIcons.search,
        title: '没有找到相关故事',
        message: '试试更短的书名或作者名',
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            !feed.loading &&
            feed.hasMore &&
            feed.error == null &&
            notification.metrics.extentAfter < 400) {
          WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadMore());
        }
        return false;
      },
      child: FeedRefresh(
        feed: feed,
        child: BookCollectionView.builder(
          key: PageStorageKey('inline-search-results-${feed.query}'),
          leadingCount: 1,
          trailingCount: 1,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            22,
            MediaQuery.paddingOf(context).top +
                FrostedHeader.toolbarHeight +
                20,
            22,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          itemCount: books.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return LoadedContentItem(
                index: 0,
                placeholder: const LoadingSkeleton(
                  layout: SkeletonLayout.actions,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (feed.query.isEmpty && onRecall != null)
                        RecentSearches(state: state, onRecall: onRecall!),
                      AppText(
                        feed.query.isEmpty
                            ? emptyQueryTitle
                            : '找到 ${feed.totalItems ?? books.length} 个结果',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (index == books.length + 1) {
              return FeedFooter(feed: feed, horizontalPadding: 0);
            }
            final book = books[index - 1];
            return LoadedContentItem(
              key: ValueKey(book.id),
              index: index,
              placeholder: const BookRowSkeleton(),
              child: NovelRow(
                novel: book,
                sourceLabel: showSources
                    ? bookshelfSource(
                        book.id,
                        repository is OfflineNovelRepository
                            ? repository as OfflineNovelRepository
                            : null,
                      )
                    : null,
                coverHeroTag: CoverHeroTag(context, book.id),
                onTap: () {
                  onOpenBook();
                  openDetail(
                    context,
                    book,
                    state,
                    repository,
                    coverHeroTag: CoverHeroTag(context, book.id),
                    fromCache: fromCache,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class DetailLoaderPage extends StatefulWidget {
  const DetailLoaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.coverHeroTag,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final Object? coverHeroTag;

  @override
  State<DetailLoaderPage> createState() => _DetailLoaderPageState();
}

class _DetailLoaderPageState extends State<DetailLoaderPage> {
  late Future<Novel> _loaded = _load();
  Novel? _cached;

  @override
  void initState() {
    super.initState();
    if (widget.repository case final OfflineNovelRepository offline) {
      final saved = offline.cache.book(widget.novel.id)?.novel;
      if (saved != null && saved.chapters.isNotEmpty) _cached = saved;
    }
    unawaited(_seedFromCache());
  }

  Future<void> _seedFromCache() async {
    if (widget.repository case final OfflineNovelRepository offline) {
      try {
        final cached = await offline.cachedBook(widget.novel.id);
        if (mounted && cached != null && cached.chapters.isNotEmpty) {
          setState(() => _cached = cached);
        }
      } catch (_) {
        // Online loading remains available when a local snapshot is damaged.
      }
    }
  }

  Future<Novel> _load() async {
    final detail = await widget.repository.detail(widget.novel);
    final chapters = await widget.repository.chapters(widget.novel.id);
    final loaded = detail.withChapters(chapters);
    await widget.state.rememberNovel(loaded);
    return loaded;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Novel>(
    future: _loaded,
    // Keep the destination cover's element and layout alive from the first
    // route frame through loading, errors and completion of its Hero flight.
    builder: (context, snapshot) => DetailPage(
      novel: snapshot.data ?? _cached ?? widget.novel,
      transitionNovel: widget.novel,
      coverHeroTag: widget.coverHeroTag,
      state: widget.state,
      repository: widget.repository,
      isLoading:
          !snapshot.hasData &&
          _cached == null &&
          snapshot.connectionState != ConnectionState.done,
      loadError: _cached == null ? snapshot.error : null,
      fromCache:
          (_cached != null && !snapshot.hasData) ||
          (widget.repository is OfflineNovelRepository &&
              (widget.repository as OfflineNovelRepository).isDirectoryOffline(
                widget.novel.id,
              )),
      onRetry: () => setState(() {
        _loaded = _load();
      }),
    ),
  );
}

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.coverHeroTag,
    this.transitionNovel,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
    this.fromCache = false,
    this.onRead,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final Object? coverHeroTag;
  final Novel? transitionNovel;
  final bool isLoading;
  final Object? loadError;
  final VoidCallback? onRetry;
  final bool fromCache;
  final ValueChanged<int>? onRead;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
  );
  late final AnimationController _contentIntro = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
  );
  Animation<double>? _routeAnimation;
  bool _introStarted = false;
  bool _contentStarted = false;
  bool _cacheSkeletonShown = false;
  bool _readerOpening = false;
  bool _shelfChanging = false;
  int? _resumeChapter;
  final Set<String> _expandedVolumes = {};
  final Set<String> _directoryVolumeKeys = {};
  int? _directoryBook;

  List<({NovelVolume? volume, int? chapter})> _directory() {
    // Provisional cached chapters can predate volume metadata. Wait for the
    // displayed directory before choosing its initially expanded volume.
    if (isLoading || loadError != null) return const [];
    final volumes = NovelVolume.of(novel.chapters);
    if (_directoryBook != novel.id) {
      _expandedVolumes.clear();
      _directoryVolumeKeys.clear();
    }
    final current = _resumeChapter ?? 0;
    for (final volume in volumes) {
      if (current >= volume.start &&
          current < volume.end &&
          !_directoryVolumeKeys.contains(volume.key)) {
        _expandedVolumes.add(volume.key);
      }
    }
    _directoryVolumeKeys
      ..clear()
      ..addAll(volumes.map((volume) => volume.key));
    _expandedVolumes.retainAll(_directoryVolumeKeys);
    if (volumes.isNotEmpty) _directoryBook = novel.id;
    return [
      for (final volume in volumes) ...[
        if (volume.title.isNotEmpty) (volume: volume, chapter: null),
        if (volume.title.isEmpty || _expandedVolumes.contains(volume.key))
          for (var i = volume.start; i < volume.end; i++)
            (volume: null, chapter: i),
      ],
    ];
  }

  Novel get novel =>
      isLocalBook(widget.novel.id) && repository is OfflineNovelRepository
      ? (repository as OfflineNovelRepository).local?.book(widget.novel.id) ??
            widget.novel
      : widget.novel;
  LibraryState get state => widget.state;
  NovelRepository get repository => widget.repository;
  Object? get coverHeroTag => widget.coverHeroTag;
  Novel? get transitionNovel => widget.transitionNovel;
  bool get _titleUpdated =>
      transitionNovel != null && transitionNovel!.title != novel.title;
  bool get _authorUpdated =>
      transitionNovel != null && transitionNovel!.author != novel.author;
  bool get isLoading => widget.isLoading;
  Object? get loadError => widget.loadError;
  VoidCallback? get onRetry => widget.onRetry;
  bool get _reduceMotion =>
      state.reduceMotion || MediaQuery.disableAnimationsOf(context);

  void _viewCover() {
    openNovelCoverImage(context, novel, reduceMotion: state.reduceMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeChanged);
    }
    if (_reduceMotion) {
      _intro.stop();
      _contentIntro.stop();
      _intro.value = 1;
      _contentIntro.value = 1;
      _introStarted = true;
      _contentStarted = !isLoading;
    } else if (animation == null ||
        animation.status == AnimationStatus.completed) {
      // A newly installed route's proxy can briefly report completed before
      // Navigator attaches the push animation at the end of its first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startIntro();
      });
    }
  }

  void _routeChanged(AnimationStatus status) {
    if (mounted && status == AnimationStatus.completed) _startIntro();
  }

  void _startIntro() {
    if (_routeAnimation != null &&
        _routeAnimation!.status != AnimationStatus.completed) {
      return;
    }
    if (!_introStarted) {
      _introStarted = true;
      if (isLoading) setState(() => _cacheSkeletonShown = true);
      _intro.forward();
    }
    if (!isLoading && !_contentStarted) {
      _contentStarted = true;
      _contentIntro.forward();
    }
  }

  @override
  void didUpdateWidget(DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isLoading && !oldWidget.isLoading) {
      _contentStarted = false;
      _contentIntro.value = 0;
    } else if (!isLoading && oldWidget.isLoading) {
      if (_reduceMotion) {
        _contentIntro.value = 1;
        _contentStarted = true;
      } else if (_introStarted) {
        _startIntro();
      }
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeChanged);
    _intro.dispose();
    _contentIntro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve a stable chapter ID once for the lazily built directory, not once
    // per visible row or once per animation/scroll frame.
    _resumeChapter = state.hasRead(novel.id) && novel.chapters.isNotEmpty
        ? state.chapterForNovel(novel)
        : null;
    final directory = _directory();
    return Scaffold(
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: _header(context),
          body: Stack(
            children: [
              Positioned.fill(
                child: CustomScrollView(
                  key: PageStorageKey('detail-scroll-${novel.id}'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        MediaQuery.paddingOf(context).top +
                            FrostedHeader.toolbarHeight +
                            12,
                        24,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: RepaintBoundary(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    button: novel.coverUrl != null,
                                    label: '查看小说封面',
                                    child: GestureDetector(
                                      key: const ValueKey('detail-view-cover'),
                                      onTap: novel.coverUrl == null
                                          ? null
                                          : _viewCover,
                                      child: NovelCover(
                                        transitionNovel ?? novel,
                                        width: 118,
                                        height: 166,
                                        heroTag: coverHeroTag,
                                        isDetailCover: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 22),
                                  Expanded(
                                    child: Padding(
                                      // Keep the title at its existing landing
                                      // position; the inverse ID plaque belongs
                                      // below the fixed header's blur feather.
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          RevealFromTop(
                                            key: const ValueKey(
                                              'detail-title-reveal',
                                            ),
                                            axis: ArchiveRevealAxis.horizontal,
                                            animation: _titleUpdated
                                                ? _contentIntro
                                                : _intro,
                                            end: .46,
                                            placeholder: _titleUpdated
                                                ? const LoadingSkeleton(
                                                    layout:
                                                        SkeletonLayout.inline,
                                                  )
                                                : null,
                                            child: AppText(
                                              novel.title,
                                              maxLines: 4,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 23,
                                                height: 1.3,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          RevealFromTop(
                                            key: const ValueKey(
                                              'detail-author-reveal',
                                            ),
                                            axis: ArchiveRevealAxis.horizontal,
                                            animation: _authorUpdated
                                                ? _contentIntro
                                                : _intro,
                                            start: .09,
                                            end: .56,
                                            placeholder:
                                                _authorUpdated && !isLoading
                                                ? const LoadingSkeleton(
                                                    layout:
                                                        SkeletonLayout.inline,
                                                  )
                                                : null,
                                            child:
                                                isLoading &&
                                                    novel.author.trim().isEmpty
                                                ? const InlineSkeleton(
                                                    key: ValueKey(
                                                      'detail-author-skeleton',
                                                    ),
                                                    height: 20,
                                                    label: '正在加载作者信息',
                                                  )
                                                : Semantics(
                                                    button: true,
                                                    label:
                                                        '查看${novel.author}的作品',
                                                    child: JellyTapSurface(
                                                      key: const ValueKey(
                                                        'detail-author-works',
                                                      ),
                                                      onTap:
                                                          novel.author
                                                              .trim()
                                                              .isEmpty
                                                          ? null
                                                          : () => pushNovelPage<void>(
                                                              context,
                                                              AuthorWorksPage(
                                                                author: novel
                                                                    .author,
                                                                repository:
                                                                    repository,
                                                                state: state,
                                                                localOnly:
                                                                    isLocalBook(
                                                                      novel.id,
                                                                    ),
                                                              ),
                                                              reduceMotion:
                                                                  _reduceMotion,
                                                              explorationKey: (
                                                                'author',
                                                                novel.author
                                                                    .trim(),
                                                                isLocalBook(
                                                                  novel.id,
                                                                ),
                                                              ),
                                                            ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 5,
                                                            ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Flexible(
                                                              child: AppText(
                                                                novel.author,
                                                                style: TextStyle(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onSurfaceVariant,
                                                                  fontSize: 14,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 5,
                                                            ),
                                                            Icon(
                                                              CupertinoIcons
                                                                  .chevron_right,
                                                              size: 11,
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                          const SizedBox(height: 20),
                                          RevealFromTop(
                                            key: const ValueKey(
                                              'detail-meta-reveal',
                                            ),
                                            axis: ArchiveRevealAxis.horizontal,
                                            animation: isLoading
                                                ? _intro
                                                : _contentIntro,
                                            start: .18,
                                            end: .64,
                                            placeholder: !isLoading
                                                ? const LoadingSkeleton(
                                                    layout:
                                                        SkeletonLayout.actions,
                                                  )
                                                : null,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (isLoading)
                                                  const InlineSkeleton(
                                                    key: ValueKey(
                                                      'detail-meta-skeleton',
                                                    ),
                                                    label: '正在加载章节信息',
                                                  )
                                                else
                                                  AppText(
                                                    loadError != null
                                                        ? '目录暂未载入'
                                                        : '${novel.isComplete ? '已完结' : '连载中'}  ·  ${novel.chapters.length} 章',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                ArchiveCode(
                                                  ArchiveDesign.fileCode(
                                                    novel.id,
                                                  ),
                                                  inverse: true,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (repository
                                              case final OfflineNovelRepository
                                                  offline) ...[
                                            const SizedBox(height: 8),
                                            if (isLoading &&
                                                _cacheSkeletonShown)
                                              const InlineSkeleton(
                                                key: ValueKey(
                                                  'detail-cache-skeleton',
                                                ),
                                                label: '正在加载缓存信息',
                                              )
                                            else if (isLoading)
                                              const SizedBox(height: 18)
                                            else if (loadError == null &&
                                                !isLocalBook(novel.id))
                                              RevealFromTop(
                                                key: const ValueKey(
                                                  'detail-cache-reveal',
                                                ),
                                                axis: ArchiveRevealAxis
                                                    .horizontal,
                                                animation: _cacheSkeletonShown
                                                    ? _contentIntro
                                                    : _intro,
                                                start: .24,
                                                end: .72,
                                                placeholder: _cacheSkeletonShown
                                                    ? const LoadingSkeleton(
                                                        layout: SkeletonLayout
                                                            .inline,
                                                      )
                                                    : null,
                                                child: OfflineBookStatus(
                                                  repository: offline,
                                                  novel: novel,
                                                  localDirectory:
                                                      widget.fromCache,
                                                ),
                                              )
                                            else
                                              const SizedBox(height: 18),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 35),
                              if (isLoading) ...[
                                const DetailSkeleton(),
                              ] else if (loadError != null) ...[
                                const Center(child: AppText('书籍详情加载失败')),
                                Center(
                                  child: GlassTextButton(
                                    onPressed: onRetry,
                                    child: const AppText('重试'),
                                  ),
                                ),
                              ] else ...[
                                RevealFromTop(
                                  key: const ValueKey('detail-summary-reveal'),
                                  animation: _contentIntro,
                                  start: .27,
                                  end: .76,
                                  placeholder: const LoadingSkeleton(
                                    layout: SkeletonLayout.detail,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (novel.tags.isNotEmpty) ...[
                                        Wrap(
                                          key: const ValueKey(
                                            'detail-book-tags',
                                          ),
                                          spacing: 7,
                                          runSpacing: 7,
                                          children: [
                                            for (final tag in novel.tags)
                                              GestureDetector(
                                                key: ValueKey(
                                                  'detail-tag-$tag',
                                                ),
                                                onTap: () =>
                                                    pushNovelPage<void>(
                                                      context,
                                                      TagWorksPage(
                                                        tag: tag,
                                                        repository:
                                                            widget.repository,
                                                        state: widget.state,
                                                      ),
                                                      reduceMotion: widget
                                                          .state
                                                          .reduceMotion,
                                                      explorationKey: (
                                                        'tag',
                                                        tag,
                                                      ),
                                                    ),
                                                child: Semantics(
                                                  button: true,
                                                  label: '查看标签 $tag 的书籍',
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: .055,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            7,
                                                          ),
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                      child: AppText(
                                                        tag,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                      ],
                                      sectionHeader(context, '简介', ''),
                                      const SizedBox(height: 13),
                                      AppText(
                                        novel.summary,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.75,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                if (!isLocalBook(novel.id) &&
                                    WenkuFeaturesScope.maybeOf(context) !=
                                        null) ...[
                                  RevealFromTop(
                                    animation: _contentIntro,
                                    start: .34,
                                    placeholder: const LoadingSkeleton(
                                      layout: SkeletonLayout.actions,
                                    ),
                                    child: BookCommunityActions(
                                      novel: novel,
                                      state: state,
                                      repository: repository,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                RevealFromTop(
                                  key: const ValueKey(
                                    'detail-directory-reveal',
                                  ),
                                  animation: _contentIntro,
                                  start: .43,
                                  placeholder: const LoadingSkeleton(
                                    layout: SkeletonLayout.actions,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      sectionHeader(context, '目录', ''),
                                      const SizedBox(height: 7),
                                      if (novel.chapters.isEmpty)
                                        const AppText('暂无章节'),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isLoading && loadError == null)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        // Keep the directory out of a single tall Column: only
                        // visible/cache-nearby rows build, lay out and paint.
                        sliver: SliverList.builder(
                          itemCount: directory.length,
                          itemBuilder: (context, index) => RevealFromTop(
                            key: ValueKey('detail-chapter-$index'),
                            animation: _contentIntro,
                            start: .48 + index.clamp(0, 8) * .025,
                            placeholder: const LoadingSkeleton(
                              layout: SkeletonLayout.inline,
                            ),
                            end: .78 + index.clamp(0, 8) * .025,
                            child: directory[index].volume != null
                                ? _volumeRow(context, directory[index].volume!)
                                : _chapterRow(
                                    context,
                                    directory[index].chapter!,
                                  ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).bottom + 96,
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    0,
                    22,
                    MediaQuery.paddingOf(context).bottom + 12,
                  ),
                  child: RevealFromTop(
                    key: const ValueKey('detail-footer-reveal'),
                    animation: _intro,
                    start: .52,
                    child: ArchiveMotionScope(
                      animation: _contentIntro,
                      enabled: !_reduceMotion && loadError == null,
                      child: AnimatedBuilder(
                        animation: state,
                        builder: (context, _) => GlassPillButton(
                          key: const ValueKey('detail-read-button'),
                          icon: CupertinoIcons.book,
                          loading: isLoading,
                          label: _readLabel,
                          onPressed: isLoading
                              ? null
                              : loadError != null
                              ? onRetry
                              : novel.chapters.isEmpty
                              ? null
                              : () => _openReader(
                                  context,
                                  state.chapterForNovel(novel),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _readLabel {
    if (isLoading) return '正在加载目录';
    if (loadError != null) return '重试加载目录';
    if (novel.chapters.isEmpty) return '暂无可读章节';
    final action = state.hasRead(novel.id) ? '继续阅读' : '开始阅读';
    return '$action · 第${state.chapterForNovel(novel) + 1}章';
  }

  Widget _volumeRow(BuildContext context, NovelVolume volume) {
    final expanded = _expandedVolumes.contains(volume.key);
    return Semantics(
      expanded: expanded,
      child: JellyTapSurface(
        key: ValueKey('detail-volume-${volume.key}'),
        onTap: () => setState(() {
          if (!_expandedVolumes.add(volume.key)) {
            _expandedVolumes.remove(volume.key);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  volume.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppText(
                '${volume.length} 章',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                expanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chapterRow(BuildContext context, int index) => JellyTapSurface(
    onTap: () => _openReader(context, index),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: AppText(
              (index + 1).toString().padLeft(2, '0'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: AppText(
              novel.chapters[index].title,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          if (index == _resumeChapter) ...[
            const SizedBox(width: 8),
            AppText(
              '上次阅读',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Icon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
  );

  Widget _header(BuildContext context) => ArchiveHeaderBar(
    leading: GlassIconButton(
      icon: CupertinoIcons.back,
      label: '返回',
      onPressed: () {
        if (!LibraryWorkspace.close(context)) Navigator.pop(context);
      },
    ),
    title: ArchiveRouteTitle(
      title: '图书详情',
      code: ArchiveDesign.fileCode(novel.id),
    ),
    actions: [
      if (!isLocalBook(novel.id) && repository is OfflineNovelRepository)
        if (isLoading || loadError != null || novel.chapters.isEmpty)
          const GlassIconButton(
            icon: CupertinoIcons.cloud_download,
            label: '离线缓存',
            onPressed: null,
          )
        else
          OfflineBookMenu(
            repository: repository as OfflineNovelRepository,
            novel: novel,
            startChapter: state.chapterForNovel(novel),
            reduceMotion: state.reduceMotion,
          ),
      if (isLocalBook(novel.id))
        GlassIconButton(
          key: const ValueKey('local-book-config'),
          icon: CupertinoIcons.gear_alt,
          label: '配置本地书籍',
          onPressed: () async {
            final local = repository is OfflineNovelRepository
                ? (repository as OfflineNovelRepository).local
                : null;
            if (local == null) return;
            final result = await pushNovelPage<LocalBookEditResult>(
              context,
              LocalBookEditor(book: novel, books: local, library: state),
              reduceMotion: _reduceMotion,
            );
            if (!mounted) return;
            if (result == LocalBookEditResult.hidden ||
                result == LocalBookEditResult.deleted ||
                result == LocalBookEditResult.regrouped) {
              if (!LibraryWorkspace.close(this.context)) {
                Navigator.pop(this.context);
              }
            } else if (result == LocalBookEditResult.saved) {
              setState(() {});
            }
          },
        )
      else
        AnimatedBuilder(
          animation: state,
          builder: (context, child) => GlassIconButton(
            icon: state.contains(novel.id)
                ? CupertinoIcons.bookmark_fill
                : CupertinoIcons.bookmark,
            label: state.contains(novel.id) ? '移出书架' : '加入书架',
            onPressed: () async {
              if (_shelfChanging) return;
              _shelfChanging = true;
              try {
                await state.toggleShelf(novel.id, novel: novel);
              } catch (_) {
                if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
              } finally {
                _shelfChanging = false;
              }
            },
          ),
        ),
    ],
  );

  Future<void> _openReader(BuildContext context, int chapter) async {
    if (widget.onRead case final read?) {
      read(chapter);
      return;
    }
    if (_readerOpening || !mounted || !context.mounted) return;
    _readerOpening = true;
    try {
      await pushNovelPage<void>(
        context,
        ReaderPage(
          novel: novel,
          state: state,
          repository: repository,
          initialChapter: chapter,
        ),
        reduceMotion: state.reduceMotion,
      );
    } finally {
      _readerOpening = false;
      // Reader exit persists its final anchor without broadcasting scroll
      // changes. Refresh the label and directory marker once, without replay.
      if (mounted) setState(() {});
    }
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    required this.initialChapter,
    this.directEntry = false,
    this.initialBookmark,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final int initialChapter;
  final bool directEntry;
  final ReaderBookmark? initialBookmark;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  VoidCallback? _releaseFeedbackHeader, _dismissChromeHint;
  late int _chapter = widget.novel.chapters.isEmpty
      ? 0
      : widget.initialChapter.clamp(0, widget.novel.chapters.length - 1);
  late Future<({ReaderContent? content, Object? error})> _content;
  ReaderContent? _currentContent;
  bool _illustrationsRefreshing = false;
  final _findMatch = ValueNotifier<ReaderMatch?>(null);
  final _bookmarkLanding = ValueNotifier<int?>(null);
  Timer? _bookmarkLandingTimer;
  bool _bookmarkLandingPending = false;
  Timer? _highlightTimer;
  // Stable chapter IDs/paragraph anchors own restoration; do not also walk
  // PageStorage and persist the viewport on every interrupted fling.
  final _scroll = ScrollController(keepScrollOffset: false);
  late final _followScroll = ReaderFollowScroll(_scroll);
  final _paragraphRegistry = ReaderParagraphRegistry();
  final _paragraphWidgets = <int, Widget>{};
  Object? _paragraphWidgetSpec;
  final _scrollAnchor = ReaderScrollAnchor();
  final _paged = ReaderPagedController();
  final _verticalGlyphs = ReaderGlyphCache();
  final _selection = ReaderSelectionController();
  late ReaderMode _readerMode;
  bool get _paginated => _readerMode.paginated;
  ReadingPosition? _restorePending;
  bool _restoreQueued = false;
  bool _restoring = false;
  bool _ready = false;
  int _paragraphCount = 0;
  bool _saveQueued = false;
  Timer? _idleSave;
  bool _catalogueOpen = false;
  bool _toolsOpen = false;
  bool _findOpen = false;
  bool _detailsOpen = false, _sourceChanged = false;
  Novel get _sourceBook =>
      widget.repository is OfflineNovelRepository &&
          isLocalBook(widget.novel.id)
      ? (widget.repository as OfflineNovelRepository).local?.book(
              widget.novel.id,
            ) ??
            widget.novel
      : widget.novel;
  DateTime? _exitRequestedAt;
  bool _allowExit = false;
  final _preparedContent = <int, ReaderContent>{};
  final _automaticContent = <int, (ReaderContent, ReaderContent)>{};
  final _contentLoads = <int, Future<ReaderContent>>{};
  bool _boundaryQueued = false, _scrollGesture = false;
  double _edgeDrag = 0;
  int _scrollDirection = 0;
  ListeningController? _listening;
  (int, int, int, int)? _listeningTarget;
  String? _listeningError;
  int _followTicket = 0;
  bool _followLocallyPaused = false;
  bool _followAutomatic = false;
  final _followPrompt = ValueNotifier(false);
  bool _enablingFollow = false;
  int _restoreTicket = 0;
  double _layoutWidth = 0;
  String _layoutTypeface = 'system';
  bool _typographyPreviewing = false;
  double _layoutTextScale = 1;
  double _readingInset = 0;
  int _contentGeneration = 0;
  late final AnimationController _chapterReveal;
  bool _chapterRevealPending = false;
  int _chapterRevealFirst = 0;
  late final AnimationController _chrome;
  bool _chromeTarget = false;
  bool _chromeReserved = false;
  bool _chromeHintQueued = false;
  String? _readerRegion;
  late final Ticker _autoScroll;
  Duration? _autoLast;
  bool _autoRunning = false;
  bool _autoPaused = false;
  double _autoPageSeconds = 0;
  String _layoutKey = '';
  late ReaderPaper _paper;
  late bool _hideSystemStatus;
  Widget _readerSurface(Widget child) => ReaderAppearance(
    state: widget.state,
    appTheme: Theme.of(context),
    child: child,
  );

  void _paperChanged() {
    final paper = widget.state.readerPreferences.paper;
    // Typography previews rebuild the article, not the glass controls. Only a
    // different paper palette needs to update the chrome's contrast.
    final mode = widget.state.readerPreferences.mode;
    final hideSystemStatus = widget.state.readerPreferences.hideSystemStatus;
    if (mode != _readerMode || hideSystemStatus != _hideSystemStatus) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      _selection.clear();
      _stopAutoScroll();
    }
    if (paper != _paper ||
        mode != _readerMode ||
        hideSystemStatus != _hideSystemStatus) {
      setState(() {
        _paper = paper;
        _readerMode = mode;
        _hideSystemStatus = hideSystemStatus;
      });
    }
  }

  void _autoTick(Duration elapsed) {
    final previous = _autoLast;
    _autoLast = elapsed;
    if (previous == null ||
        !_ready ||
        _restoring ||
        !_listeningScrollSceneActive) {
      return;
    }
    if (_paginated) {
      if (!_paged.ready) return;
      _autoPageSeconds += ((elapsed - previous).inMicroseconds / 1000000).clamp(
        0.0,
        .05,
      );
      if (_autoPageSeconds >=
          600 / widget.state.readerPreferences.autoScrollSpeed) {
        _autoPageSeconds = 0;
        if (!_paged.pageBy(1)) {
          if (_chapter + 1 < widget.novel.chapters.length) {
            _go(_chapter + 1);
          } else {
            _stopAutoScroll(showControls: true);
          }
        }
      }
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - .5) {
      if (_chapter + 1 < widget.novel.chapters.length) {
        _go(_chapter + 1);
      } else {
        _stopAutoScroll(showControls: true);
      }
      return;
    }
    final dt = ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, .05);
    _scroll.jumpTo(
      (position.pixels + dt * widget.state.readerPreferences.autoScrollSpeed)
          .clamp(0.0, position.maxScrollExtent),
    );
  }

  void _startAutoScroll() {
    if (!_ready) return;
    _suspendListeningFollow();
    unawaited(_listening?.pause().catchError((Object _) {}));
    _autoRunning = true;
    if (_autoPaused) setState(() => _autoPaused = false);
    _autoPageSeconds = 0;
    _autoLast = null;
    _showChrome(false);
    if (!_autoScroll.isActive) _autoScroll.start();
  }

  void _stopAutoScroll({bool showControls = false}) {
    if (!_autoRunning) return;
    _autoRunning = false;
    _autoLast = null;
    _autoScroll.stop();
    if (mounted && _autoPaused != showControls) {
      setState(() => _autoPaused = showControls);
    }
    _saveWhenIdle();
    if (showControls && mounted) _showChrome(true);
  }

  void _contentTap(TapUpDetails details) {
    _cancelExitRequest();
    if (_selection.value) {
      _selection.clear();
      return;
    }
    if (_autoRunning) {
      _stopAutoScroll(showControls: true);
      return;
    }
    if (widget.state.readerPreferences.tapPaging) {
      final prefs = widget.state.readerPreferences;
      final x = details.localPosition.dx / MediaQuery.sizeOf(context).width;
      final y = details.localPosition.dy / MediaQuery.sizeOf(context).height;
      final direction = switch (prefs.tapLayout) {
        ReaderTapLayout.standard =>
          x < .28
              ? -1
              : x > .72
              ? 1
              : 0,
        ReaderTapLayout.rightHand => x > .4 ? (y < .3 ? -1 : 1) : 0,
        ReaderTapLayout.leftHand => x < .6 ? (y < .3 ? -1 : 1) : 0,
      };
      if (direction != 0) {
        _pageBy(
          prefs.mode == ReaderMode.vertical &&
                  prefs.tapLayout == ReaderTapLayout.standard
              ? -direction
              : direction,
        );
        return;
      }
    }
    _toggleChrome();
  }

  @override
  void initState() {
    super.initState();
    _paper = widget.state.readerPreferences.paper;
    _hideSystemStatus = widget.state.readerPreferences.hideSystemStatus;
    _readerMode = widget.state.readerPreferences.mode;
    _chromeTarget = widget.state.readerChromeVisible;
    _chromeReserved = _chromeTarget;
    widget.state.readerSettingsChanges.addListener(_paperChanged);
    widget.state.illustrationChanges.addListener(_illustrationLayoutChanged);
    _autoScroll = createTicker(_autoTick);
    _chapterReveal = AnimationController(
      vsync: this,
      duration: NovelMotion.enter,
      value: 1,
    );
    _chrome = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: NovelMotion.exit,
      value: _chromeTarget ? 1 : 0,
    );
    WidgetsBinding.instance.addObserver(this);
    final saved =
        widget.initialBookmark?.position ??
        widget.state.positionFor(widget.novel.id);
    _bookmarkLandingPending = widget.initialBookmark != null;
    if (saved != null &&
        widget.novel.chapters.isNotEmpty &&
        (saved.chapterId > 0
            ? saved.chapterId == widget.novel.chapters[_chapter].id
            : saved.chapter == _chapter)) {
      _restorePending = saved;
    }
    _content = _loadContent();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.readerSettingsChanges.removeListener(_paperChanged);
      oldWidget.state.illustrationChanges.removeListener(
        _illustrationLayoutChanged,
      );
      widget.state.readerSettingsChanges.addListener(_paperChanged);
      widget.state.illustrationChanges.addListener(_illustrationLayoutChanged);
      _paper = widget.state.readerPreferences.paper;
      _hideSystemStatus = widget.state.readerPreferences.hideSystemStatus;
    }
  }

  @override
  void deactivate() {
    // The Scrollable child detaches its controller before this State's dispose.
    // Capture while it is still attached, also when idle-save is pending.
    _idleSave?.cancel();
    _followTicket++;
    _followScroll.cancel();
    _savePosition(notify: false, finalSave: true);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.state.illustrationChanges.removeListener(_illustrationLayoutChanged);
    _dismissChromeHint?.call();
    _releaseFeedbackHeader?.call();
    widget.state.readerSettingsChanges.removeListener(_paperChanged);
    _idleSave?.cancel();
    _savePosition(notify: false, finalSave: true);
    _highlightTimer?.cancel();
    _findMatch.dispose();
    _bookmarkLandingTimer?.cancel();
    _bookmarkLanding.dispose();
    _selection.dispose();
    _verticalGlyphs.dispose();
    _listening?.snapshot.removeListener(_listeningChanged);
    _followPrompt.dispose();
    _followTicket++;
    _followScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _chapterReveal.dispose();
    _chrome.dispose();
    _autoScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _releaseFeedbackHeader ??= bindNovelFeedbackHeader(context, _chrome);
    _scheduleChromeHint();
    final region = chineseLocale(
      Localizations.maybeLocaleOf(context),
    ).countryCode;
    if (_readerRegion != null && _readerRegion != region) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      _content = _loadContent();
    }
    _readerRegion = region;
    final listening = ListeningScope.maybeOf(context);
    if (listening != _listening) {
      _listening?.snapshot.removeListener(_listeningChanged);
      _listening = listening;
      listening?.snapshot.addListener(_listeningChanged);
      _listeningTarget = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    } else if (listening != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    }
    if (!_ready || _restoring || _layoutWidth <= 0) return;
    final media = MediaQuery.of(context);
    final scale =
        media.textScaler.scale(widget.state.fontSize) / widget.state.fontSize;
    if ((media.size.width - _layoutWidth).abs() >= 1 ||
        (scale - _layoutTextScale).abs() >= .01 ||
        _layoutTypeface != widget.state.readerFontId) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
    }
  }

  Future<void> _listen() async {
    if (_listening != null) await _settings(initialTab: 'listening');
  }

  void _suspendListeningFollow({bool userDrag = false}) {
    final listening = _listening;
    _followTicket++;
    _followScroll.cancel(userDrag: userDrag);
    if (listening != null &&
        listening.snapshot.value.active &&
        listening.snapshot.value.novel?.id == widget.novel.id &&
        listening.snapshot.value.follow) {
      _followLocallyPaused = true;
      _followPrompt.value = listening.snapshot.value.current != null;
      unawaited(listening.setFollow(false).catchError((Object _) {}));
    }
  }

  void _listeningChanged() {
    final state = _listening?.snapshot.value;
    final current = state?.current;
    if (state?.error == null) _listeningError = null;
    if (mounted &&
        state?.novel?.id == widget.novel.id &&
        state?.error != null &&
        state!.error != _listeningError) {
      final error = _listeningError = state.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ModalRoute.of(context)?.isCurrent != false &&
            _listening?.snapshot.value.error == error) {
          showNovelFeedback(
            context,
            error!,
            actionLabel: '听书',
            action: _listen,
          );
        }
      });
    }
    if (state == null || !state.active || !state.follow) {
      _followLocallyPaused = false;
    }
    _followPrompt.value =
        state != null &&
        state.active &&
        state.novel?.id == widget.novel.id &&
        current != null &&
        (!state.follow || _followLocallyPaused);
    if (state == null ||
        !state.active ||
        state.novel?.id != widget.novel.id ||
        !_listeningScrollSceneActive) {
      _listeningTarget = null;
      _followTicket++;
      _followScroll.cancel();
      return;
    }
    if (!state.follow || _followLocallyPaused || current == null) {
      _listeningTarget = null;
      if (_followAutomatic) {
        _followTicket++;
        _followScroll.cancel();
        _followAutomatic = false;
      }
      return;
    }
    final target = (
      widget.novel.id,
      state.chapter,
      current.paragraph,
      current.start,
    );
    if (_listeningTarget == target) return;
    _listeningTarget = target;
    if (state.chapter != _chapter) _go(state.chapter, listeningFollow: true);
    _revealListeningFragment(
      state.chapter,
      current.paragraph,
      current.start,
      current.end,
      automatic: true,
    );
  }

  bool get _listeningScrollSceneActive =>
      mounted &&
      !_toolsOpen &&
      !_catalogueOpen &&
      !_findOpen &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ModalRoute.of(context)?.isCurrent != false;

  Future<void> _enableListeningFollow() async {
    final listening = _listening;
    final state = listening?.snapshot.value;
    if (_enablingFollow ||
        listening == null ||
        state?.active != true ||
        state?.novel?.id != widget.novel.id ||
        state?.current == null) {
      return;
    }
    _enablingFollow = true;
    _stopAutoScroll();
    _selection.clear();
    try {
      await listening.setFollow(true);
      if (!mounted) return;
      _followLocallyPaused = false;
      _listeningTarget = null;
      _listeningChanged();
    } catch (_) {
      if (mounted) showNovelFeedback(context, '跟随设置保存失败，请重试');
    } finally {
      _enablingFollow = false;
    }
  }

  void _revealListeningFragment(
    int chapter,
    int paragraph,
    int start,
    int end, {
    required bool automatic,
  }) {
    final ticket = ++_followTicket;
    _followAutomatic = automatic;
    _followScroll.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool allowed() =>
          _listeningScrollSceneActive &&
          ticket == _followTicket &&
          _chapter == chapter &&
          _listening?.snapshot.value.active == true &&
          _listening?.snapshot.value.novel?.id == widget.novel.id &&
          (!automatic ||
              (_listening?.snapshot.value.follow == true &&
                  !_followLocallyPaused));
      if (!allowed()) return;
      try {
        if (_paginated) {
          if (allowed() && _paged.ready) {
            _paged.reveal(ReaderTextAnchor(paragraph, start));
          }
          return;
        }
        await _followScroll.reveal(
          allowed: allowed,
          reduceMotion:
              widget.state.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
          target: () =>
              !_ready ||
                  _restoring ||
                  _restorePending != null ||
                  !_scroll.hasClients
              ? null
              : _paragraphRegistry.speechTarget(
                  paragraph,
                  start,
                  end,
                  _readingInset,
                  viewportBottom:
                      _scroll.position.viewportDimension -
                      MediaQuery.paddingOf(context).bottom -
                      116,
                  trailingSpace: 12,
                ),
        );
      } finally {
        if (ticket == _followTicket) _followAutomatic = false;
      }
    });
    // Adding a post-frame callback alone does not request a frame. In a static
    // chapter or after resuming, explicitly wake the one requested landing.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _doubleTapListeningParagraph(int paragraph) async {
    final listening = _listening;
    if (listening == null) return;
    final state = listening.snapshot.value;
    final other =
        state.active &&
        state.novel?.id == widget.novel.id &&
        (state.chapter != _chapter || state.current?.paragraph != paragraph);
    final action = listening.paragraphDoubleTap(
      novelId: widget.novel.id,
      chapter: _chapter,
      paragraph: paragraph,
    );
    // An explicit double-tap is a one-off soft landing even after a manual
    // scroll suspended following. It never flips the user's follow preference.
    if (other &&
        (!state.follow || _followLocallyPaused) &&
        _currentContent != null) {
      final text = _currentContent!.paragraphs[paragraph];
      _revealListeningFragment(
        _chapter,
        paragraph,
        0,
        text.length.clamp(0, 240),
        automatic: false,
      );
    }
    await action;
  }

  void _go(
    int index, {
    ReadingPosition? position,
    bool highlightBookmark = false,
    bool listeningFollow = false,
  }) {
    if (index < 0 || index >= widget.novel.chapters.length) {
      return;
    }
    _selection.clear();
    if (!listeningFollow) _suspendListeningFollow();
    _clearBookmarkLanding();
    _bookmarkLandingPending = highlightBookmark;
    if (highlightBookmark) {
      _highlightTimer?.cancel();
      _findMatch.value = null;
    }
    if (index == _chapter) {
      if (position == null) return;
      _prepareRestore(position);
      setState(() {});
      return;
    }
    _idleSave?.cancel();
    _savePosition(notify: false);
    _scrollGesture = false;
    _edgeDrag = 0;
    _cancelExitRequest();
    _highlightTimer?.cancel();
    _findMatch.value = null;
    _currentContent = null;
    _illustrationsRefreshing = false;
    _ready = false;
    _restorePending = position;
    _restoreQueued = false;
    _restoring = false;
    _restoreTicket++;
    setState(() {
      _chapter = index;
      _content = _loadContent();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _catalogue() async {
    _cancelExitRequest();
    _selection.clear();
    if (_catalogueOpen ||
        _toolsOpen ||
        _findOpen ||
        widget.novel.chapters.isEmpty) {
      return;
    }
    _stopAutoScroll();
    _catalogueOpen = true;
    _followTicket++;
    _followScroll.cancel();
    final preview = ValueNotifier(false);
    int? progressFrame;
    double? pendingProgress;
    bool progressStarted = false;
    void previewProgress(double value) {
      if (!progressStarted) {
        progressStarted = true;
        _suspendListeningFollow();
        _clearBookmarkLanding();
      }
      pendingProgress = value;
      progressFrame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
        progressFrame = null;
        if (!mounted || pendingProgress == null) return;
        final target = pendingProgress!.clamp(0.0, 1.0);
        pendingProgress = null;
        if (_paginated) {
          _paged.seek(target);
        } else if (_scroll.hasClients) {
          _scroll.jumpTo(target * _scroll.position.maxScrollExtent);
        }
      });
    }

    try {
      final action = await showJellySheet<Object>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        previewing: preview,
        surfaceWrapper: _readerSurface,
        builder: (context) => ReaderCatalogue(
          novel: widget.novel,
          currentChapter: _chapter,
          position: _currentPosition(),
          onPreviewChanged: (active) {
            _typographyPreviewing = active;
            preview.value = active;
          },
          onProgressPreview: previewProgress,
          onProgressCommitted: (value) {
            if (progressFrame case final frame?) {
              SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
            }
            progressFrame = null;
            pendingProgress = null;
            progressStarted = false;
            unawaited(_seekProgress(value));
          },
          cache: widget.repository is OfflineNovelRepository
              ? (widget.repository as OfflineNovelRepository).cache
              : null,
        ),
      );
      if (!mounted) return;
      if (action is int && action != _chapter) {
        _go(action);
      } else if (action is ReaderToolAction) {
        _catalogueOpen = false;
        await _handleReaderAction(action);
      }
    } finally {
      if (progressFrame case final frame?) {
        SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
      }
      _typographyPreviewing = false;
      preview.dispose();
      _catalogueOpen = false;
      _listeningTarget = null;
      _savePosition(notify: false);
      if (mounted) _listeningChanged();
    }
  }

  Future<({ReaderContent? content, Object? error})> _loadContent({
    bool refresh = false,
  }) async {
    final index = _chapter;
    final generation = ++_contentGeneration;
    _illustrationsRefreshing = false;
    _chapterRevealPending = false;
    _chapterReveal.value = 1;
    // Picker results can arrive between frames. Carry expected request failure
    // as data, rather than an exceptional future awaiting the next UI listener.
    try {
      final source = !refresh && _preparedContent[index] != null
          ? _preparedContent[index]!
          : await _prepareContent(index, refresh: refresh);
      final placed = placeIllustrations(
        await _automaticIllustrations(source, index),
        widget.state.illustrationsFor(
          widget.novel.id,
          chapterId: widget.novel.chapters[index].id,
        ),
      );
      final content = await placed.localizedAsync(
        Locale('zh', _readerRegion ?? 'CN'),
      );
      if (mounted && index == _chapter && generation == _contentGeneration) {
        _currentContent = content;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _contentGeneration) {
            _listeningTarget = null;
            _listeningChanged();
            _deferContentWarmup(generation, content);
          }
        });
        final reduce =
            widget.state.reduceMotion ||
            MediaQuery.disableAnimationsOf(context);
        if (reduce) {
          _chapterReveal.value = 1;
        } else {
          _chapterRevealPending = true;
          _chapterReveal.value = 0;
        }
      }
      return (content: content, error: null);
    } catch (error) {
      if (mounted && generation == _contentGeneration) _showChrome(true);
      return (content: null, error: error);
    }
  }

  Future<ReaderContent> _prepareContent(int index, {bool refresh = false}) {
    if (!refresh) {
      if (_preparedContent[index] case final content?) {
        return Future.value(content);
      }
      if (_contentLoads[index] case final request?) return request;
    }
    late final Future<ReaderContent> request;
    request = () async {
      try {
        final content = await ReaderContent.parse(
          await _requestContent(index, refresh: refresh),
        );
        if (mounted &&
            (index - _chapter).abs() <= 1 &&
            identical(_contentLoads[index], request)) {
          _preparedContent[index] = content;
        }
        return content;
      } finally {
        if (identical(_contentLoads[index], request)) {
          _contentLoads.remove(index);
        }
      }
    }();
    _contentLoads[index] = request;
    return request;
  }

  void _prefetchAdjacent() {
    _automaticContent.removeWhere((index, _) => (index - _chapter).abs() > 1);
    _preparedContent.removeWhere((index, _) => (index - _chapter).abs() > 1);
    for (final index in [_chapter + 1, _chapter - 1]) {
      if (index < 0 || index >= widget.novel.chapters.length) continue;
      if (widget.repository case final OfflineNovelRepository offline) {
        if (offline.offline &&
            !isLocalBook(widget.novel.id) &&
            offline.cache
                    .book(widget.novel.id)
                    ?.chapterBytes
                    .containsKey(widget.novel.chapters[index].id) !=
                true) {
          continue;
        }
      }
      unawaited(
        _prepareContent(index).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  void _deferContentWarmup(int generation, ReaderContent content) {
    // Borrow frames already driven by the route/reveal. A blocked idle task
    // would continuously reschedule event-loop callbacks during animation;
    // this check never starts a ticker or requests another frame of its own.
    void afterFrame(Duration _) {
      if (!mounted || generation != _contentGeneration) return;
      final route = ModalRoute.of(context);
      final entering =
          route?.animation?.status == AnimationStatus.forward ||
          route?.animation?.status == AnimationStatus.reverse;
      final preparing =
          !_ready ||
          _restoring ||
          (_paginated
              ? !_paged.ready
              : _chapterRevealPending || _chapterReveal.isAnimating);
      if (entering || preparing) {
        WidgetsBinding.instance.addPostFrameCallback(afterFrame);
        return;
      }
      _prefetchAdjacent();
      if (content.paragraphs.any((p) => p.trim() == '[插图]') &&
          widget.repository is OfflineNovelRepository) {
        unawaited(_refreshIllustrations(automatic: true));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(afterFrame);
  }

  Future<ReaderContent> _automaticIllustrations(
    ReaderContent source,
    int chapter,
  ) async {
    if (isLocalBook(widget.novel.id)) return source;
    if (_automaticContent[chapter] case (
      final original,
      final effective,
    ) when identical(original, source)) {
      return effective;
    }
    final local = widget.repository is OfflineNovelRepository
        ? (widget.repository as OfflineNovelRepository).local
        : null;
    if (local == null || local.originals.isEmpty) return source;
    final title = seriesTitleKey(widget.novel.title),
        section = widget.novel.chapters[chapter];
    final volume = inferLocalSeries(
      '${widget.novel.title} ${section.volumeTitle}',
    )?.number;
    final candidates = <(Novel, NovelChapter)>[];
    for (final book in local.originals) {
      final hint = local.seriesHint(book.id);
      if ((hint?.key ?? seriesTitleKey(book.title)) != title ||
          (volume != null && hint?.number != null && hint!.number != volume)) {
        continue;
      }
      if (book.author != '本地书籍' &&
          seriesTitleKey(book.author) != seriesTitleKey(widget.novel.author)) {
        continue;
      }
      for (final entry in book.chapters) {
        if (seriesTitleKey(entry.title) == seriesTitleKey(section.title)) {
          candidates.add((book, entry));
        }
      }
    }
    ReaderContent result = source;
    var matched = 0;
    // Ambiguous short chapter labels must not trigger a library-wide parse.
    if (candidates.length <= 4) {
      for (final (book, entry) in candidates) {
        try {
          final reference = await ReaderContent.parse(
            await local.chapterContent(book.id, entry),
          );
          final placed = autoIllustrationsFromReference(source, reference);
          if (!identical(placed, source)) {
            result = placed;
            matched++;
          }
        } catch (_) {
          /* A missing reference never blocks the original prose. */
        }
      }
    }
    if (matched != 1) result = source;
    _automaticContent[chapter] = (source, result);
    return result;
  }

  void _continueChapter(int direction) {
    if (!_ready ||
        _restoring ||
        _boundaryQueued ||
        _toolsOpen ||
        _catalogueOpen ||
        _findOpen) {
      return;
    }
    final target = _chapter + direction;
    if (target < 0 || target >= widget.novel.chapters.length) return;
    final generation = _contentGeneration;
    _boundaryQueued = true;
    _scrollGesture = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boundaryQueued = false;
      if (!mounted || generation != _contentGeneration) return;
      _go(
        target,
        position: direction < 0
            ? ReadingPosition(
                chapter: target,
                chapterId: widget.novel.chapters[target].id,
                offset: 0,
                fraction: 1,
                fontSize: widget.state.fontSize,
                width: 0,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              )
            : null,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showChrome(bool visible) {
    if (visible) {
      _dismissChromeHint?.call();
      _dismissChromeHint = null;
    }
    if (_chromeTarget != visible) {
      unawaited(
        widget.state.setReaderChromeVisible(visible).catchError((Object _) {
          if (mounted) showNovelFeedback(context, '控件显示偏好未保存，请重试');
        }),
      );
    }
    _chromeTarget = visible;
    _readingInset = _scrollReadingInset(widget.state.readerPreferences);
    // Start the incremental text move with the glass transition, not after
    // waiting for the hide animation to finish and then shaping the chapter.
    if (_chromeReserved != visible) {
      _chromeReserved = visible;
      // Scrolling has a constant status-bar inset. Only paged text changes
      // its reserved area; leave the scrolling article and paragraphs intact.
      if (_paginated) setState(() {});
    }
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _chrome.value = visible ? 1 : 0;
    } else if (visible) {
      _chrome.forward();
    } else {
      _chrome.reverse();
    }
  }

  void _scheduleChromeHint() {
    if (!_ready ||
        _chromeTarget ||
        _chromeHintQueued ||
        widget.state.readerChromeHintSeen) {
      return;
    }
    _chromeHintQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final animation = route?.animation;
      void show() {
        if (!mounted || !_ready || _chromeTarget || route?.isCurrent == false) {
          return;
        }
        _dismissChromeHint = showNovelFeedback(context, '点击屏幕显示控件');
        unawaited(
          widget.state.markReaderChromeHintSeen().catchError((Object _) {}),
        );
      }

      if (animation == null || animation.status == AnimationStatus.completed) {
        show();
      } else {
        void after(AnimationStatus status) {
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            animation.removeStatusListener(after);
            if (status == AnimationStatus.completed) show();
          }
        }

        animation.addStatusListener(after);
      }
    });
  }

  void _revealChapter() {
    if (!_chapterRevealPending || !_ready || !_scroll.hasClients) return;
    _chapterRevealPending = false;
    // Reveal the restored viewport, not offscreen paragraphs at chapter start.
    // The anchor render objects remain outside the visual transform so saving,
    // typography changes and lazy restoration keep the same coordinates.
    final first =
        _paragraphRegistry.capture(_scroll.offset + _readingInset)?.index ?? 0;
    if (_chapterRevealFirst != first) {
      setState(() => _chapterRevealFirst = first);
    }
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _chapterReveal.value = 1;
    } else {
      _chapterReveal.forward(from: 0);
    }
  }

  void _toggleChrome() {
    if (_ready && !_toolsOpen && !_catalogueOpen && !_findOpen) {
      _showChrome(!_chromeTarget);
    }
  }

  void _pageBy(int direction) {
    _cancelExitRequest();
    if (!_ready || _toolsOpen || _catalogueOpen || _findOpen) {
      return;
    }
    if (_selection.value) {
      _selection.clear();
      return;
    }
    _stopAutoScroll();
    _suspendListeningFollow();
    if (_paginated) {
      if (!_paged.ready || _paged.pageBy(direction)) return;
      _continueChapter(direction);
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (direction > 0 &&
        position.extentAfter <= .5 &&
        _chapter + 1 < widget.novel.chapters.length) {
      _continueChapter(1);
      return;
    }
    if (direction < 0 && position.pixels <= .5 && _chapter > 0) {
      _continueChapter(-1);
      return;
    }
    final target =
        (position.pixels +
                direction *
                    (position.viewportDimension - _readingInset - 100).clamp(
                      80.0,
                      double.infinity,
                    ))
            .clamp(0.0, position.maxScrollExtent);
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: NovelMotion.contact,
        curve: NovelMotion.ease,
      );
    }
  }

  Future<String> _requestContent(int index, {bool refresh = false}) async {
    if (widget.novel.chapters.isEmpty) throw const FormatException('目录为空');
    if (widget.repository case final OfflineNovelRepository offline) {
      await offline.rememberDirectory(widget.novel);
      if (refresh) {
        return offline.refreshChapterContent(
          widget.novel.id,
          widget.novel.chapters[index],
        );
      }
    }
    return widget.repository.chapterContent(
      widget.novel.id,
      widget.novel.chapters[index],
    );
  }

  Future<void> _refreshIllustrations({bool automatic = false}) async {
    if (_illustrationsRefreshing) return;
    final chapter = _chapter;
    final generation = _contentGeneration;
    setState(() => _illustrationsRefreshing = true);
    try {
      final body = automatic
          ? await (widget.repository as OfflineNovelRepository)
                .repairChapterIllustrations(
                  widget.novel.id,
                  widget.novel.chapters[chapter],
                )
          : await _requestContent(chapter, refresh: true);
      if (body == null) return;
      final source = await ReaderContent.parse(body);
      if (!mounted || chapter != _chapter || generation != _contentGeneration) {
        return;
      }
      _preparedContent[chapter] = source;
      final placed = placeIllustrations(
        await _automaticIllustrations(source, chapter),
        widget.state.illustrationsFor(
          widget.novel.id,
          chapterId: widget.novel.chapters[chapter].id,
        ),
      );
      final content = await placed.localizedAsync(
        Locale('zh', _readerRegion ?? 'CN'),
      );
      if (!mounted || chapter != _chapter || generation != _contentGeneration) {
        return;
      }
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      setState(() {
        _currentContent = content;
        _content = Future.value((content: content, error: null));
      });
    } catch (_) {
      if (!automatic && mounted && chapter == _chapter) {
        showNovelFeedback(context, '插图暂未更新成功，正文已保留，可稍后重试');
      }
    } finally {
      if (mounted && generation == _contentGeneration) {
        setState(() => _illustrationsRefreshing = false);
      }
    }
  }

  Widget _paragraphContent(
    List<String> paragraphs,
    int index,
    TextStyle style, {
    bool fullPage = false,
    bool sizedImage = false,
  }) {
    final url = readerIllustrationUrl(paragraphs[index]);
    if (url != null) {
      final image = ReaderIllustration(
        url: url,
        fitPage: fullPage,
        localLayout: LocalImageLayout.fromParagraph(paragraphs[index]),
        fontSize: MediaQuery.textScalerOf(context).scale(style.fontSize ?? 19),
        sizedFrame: sizedImage,
        onOpen: () => pushNovelPage<void>(
          context,
          ReaderIllustrationGallery(
            urls: _currentContent!.illustrations,
            initialUrl: url,
          ),
          reduceMotion: widget.state.reduceMotion,
        ),
      );
      final placement = _currentContent?.placementIds[index];
      return placement == null
          ? image
          : GestureDetector(
              onLongPress: () => _removePlacedIllustration(placement),
              child: image,
            );
    }
    if (paragraphs[index].trim() == '[插图]') {
      return ReaderIllustrationFrame(
        fitPage: fullPage,
        child: _illustrationsRefreshing
            ? const LoadingSkeleton(
                layout: SkeletonLayout.cover,
                label: '正在补全插图',
              )
            : ContentPanel(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.photo),
                      const SizedBox(height: 10),
                      const AppText('暂未取得本章插图地址'),
                      GlassTextButton(
                        onPressed: _refreshIllustrations,
                        child: const AppText('重试本章插图'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }
    return ReaderSelectionFragment(
      controller: _selection,
      text: paragraphs[index],
      selectableOffset: widget.state.readerPreferences.indent
          ? readerIndentLength
          : 0,
      anchorForOffset: (offset) =>
          (paragraph: index, offset: offset.clamp(0, paragraphs[index].length)),
      child: ReaderHighlightText(
        text: paragraphs[index],
        index: index,
        match: _findMatch,
        style: style,
        indent: widget.state.readerPreferences.indent,
        textAlign: widget.state.readerPreferences.justify
            ? TextAlign.justify
            : TextAlign.start,
      ),
    );
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_ready || _restoring) return;
    final view = View.of(context);
    final width = view.physicalSize.width / view.devicePixelRatio;
    if ((width - _layoutWidth).abs() < 1) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
  }

  @override
  void didChangeTextScaleFactor() {
    if (!mounted) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopAutoScroll();
      _idleSave?.cancel();
      _savePosition(notify: false);
    }
    _followTicket++;
    _followScroll.cancel();
    _listeningTarget = null;
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    }
  }

  void _saveWhenIdle() {
    _idleSave?.cancel();
    if (_restoring) return;
    final generation = _contentGeneration;
    _idleSave = Timer(const Duration(milliseconds: 160), () {
      _idleSave = null;
      if (mounted &&
          generation == _contentGeneration &&
          (_paginated
              ? _paged.ready
              : _scroll.hasClients &&
                    !_scroll.position.isScrollingNotifier.value)) {
        _savePosition(notify: false);
      }
    });
  }

  void _savePosition({bool notify = true, bool finalSave = false}) {
    // Explicit save/restore/exit supersedes any delayed copy of that position.
    _idleSave?.cancel();
    _idleSave = null;
    if (_detailsOpen ||
        _sourceChanged ||
        !_ready ||
        _restoring ||
        (_paginated ? !_paged.ready : !_scroll.hasClients) ||
        (_typographyPreviewing && !finalSave)) {
      return;
    }
    // Lazy slivers can emit a scroll-end while correcting their estimated
    // extent during layout. Persist after that frame, not from inside layout.
    final duringLayout =
        WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    if (duringLayout && !finalSave) {
      if (!_saveQueued) {
        _saveQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _saveQueued = false;
          if (mounted) _savePosition(notify: notify);
        });
      }
      return;
    }
    final position = _currentPosition(includeParagraph: !duringLayout);
    unawaited(
      widget.state
          .savePosition(
            novel: _sourceBook,
            chapter: _chapter,
            offset:
                position?.offset ??
                (_paginated ? _paged.fraction : _scroll.offset),
            maximum: _paginated ? 1 : _scroll.position.maxScrollExtent,
            width: _layoutWidth,
            notify: notify,
            paragraphIndex: position?.paragraphIndex,
            paragraphFraction: position?.paragraphFraction ?? 0,
            textOffset: position?.textOffset,
            textScale: _textScale,
            typeface: position?.typeface ?? _layoutTypeface,
          )
          .catchError((Object _) {}),
    );
  }

  double get _textScale => _layoutTextScale;

  ReadingPosition? _currentPosition({
    bool includeParagraph = true,
    bool bookmark = false,
  }) {
    if (!_ready ||
        _restoring ||
        (_paginated ? !_paged.ready : !_scroll.hasClients) ||
        widget.novel.chapters.isEmpty) {
      return null;
    }
    if (_paginated) {
      final visible = _paged.anchor;
      final owner = _currentContent?.inlineOwners[visible?.paragraph];
      final anchor = owner == null
          ? visible
          : ReaderTextAnchor(owner, _currentContent!.paragraphs[owner].length);
      return ReadingPosition(
        chapter: _chapter,
        chapterId: widget.novel.chapters[_chapter].id,
        offset: _paged.fraction,
        fraction: _paged.fraction,
        fontSize: widget.state.fontSize,
        lineHeight: widget.state.lineHeight,
        width: _layoutWidth,
        textScale: _textScale,
        typeface: _layoutTypeface,
        layout: _layoutKey,
        paragraphIndex: anchor?.paragraph,
        textOffset: anchor?.offset,
        paragraphFraction: anchor == null
            ? 0
            : anchor.offset /
                  _currentContent!.paragraphs[anchor.paragraph].length.clamp(
                    1,
                    100000000,
                  ),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    final maximum = _scroll.position.maxScrollExtent;
    final offset = _scroll.offset.clamp(
      0.0,
      maximum.clamp(0.0, double.infinity),
    );
    var paragraph =
        includeParagraph && (bookmark || offset > .5 && offset < maximum - .5)
        ? _paragraphRegistry.capture(
            offset + _readingInset,
            clampToLast: bookmark,
          )
        : null;
    if (!includeParagraph) {
      // A route can be disposed inside layout, where reading RenderBox sizes
      // is invalid. Retain an already measured anchor only for the exact same
      // chapter, offset and geometry; otherwise keep the raw-offset fallback.
      final previous = widget.state.positionFor(widget.novel.id);
      if (previous != null &&
          previous.paragraphIndex != null &&
          previous.chapter == _chapter &&
          previous.chapterId == widget.novel.chapters[_chapter].id &&
          (previous.offset - offset).abs() < .5 &&
          previous.fontSize == widget.state.fontSize &&
          previous.lineHeight == widget.state.lineHeight &&
          previous.typeface == _layoutTypeface &&
          previous.layout == _layoutKey &&
          (previous.width - _layoutWidth).abs() < .5 &&
          (previous.textScale - _textScale).abs() < .01) {
        paragraph = (
          index: previous.paragraphIndex!,
          fraction: previous.paragraphFraction,
        );
      }
    }
    return ReadingPosition(
      chapter: _chapter,
      chapterId: widget.novel.chapters[_chapter].id,
      offset: offset,
      fraction: maximum > 0 ? (offset / maximum).clamp(0, 1) : 0,
      fontSize: widget.state.fontSize,
      lineHeight: widget.state.lineHeight,
      width: _layoutWidth,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      paragraphIndex: paragraph?.index,
      paragraphFraction: paragraph?.fraction ?? 0,
      textOffset: paragraph == null
          ? null
          : includeParagraph
          ? _paragraphRegistry.captureTextOffset(
              paragraph.index,
              offset + _readingInset,
            )
          : widget.state.positionFor(widget.novel.id)?.textOffset,
      textScale: _textScale,
      typeface: _layoutTypeface,
      layout: _layoutKey,
    );
  }

  void _prepareRestore(ReadingPosition position) {
    _restorePending = position;
    _restoreQueued = false;
    _restoring = true;
    _restoreTicket++;
  }

  void _clearBookmarkLanding() {
    _bookmarkLandingTimer?.cancel();
    _bookmarkLandingPending = false;
    _bookmarkLanding.value = null;
  }

  void _pagedReady() {
    if (!mounted || !_paginated || !_paged.ready) return;
    final saved = _restorePending;
    _restorePending = null;
    _restoring = false;
    _restoreQueued = false;
    _landBookmark(saved);
    _listeningTarget = null;
    _listeningChanged();
    _saveWhenIdle();
  }

  double _scrollReadingInset(ReaderPreferences preferences) =>
      ((preferences.hideSystemStatus && !_chromeTarget
                  ? 12.0
                  : FrostedHeader.toolbarHeight + 12) -
              preferences.marginTop)
          .clamp(0.0, double.infinity);

  double _systemStatusExtent(BuildContext context) =>
      _hideSystemStatus ? ReaderStatusFooter.heightFor(context) + 4 : 0;

  double _chromeStatusInset(BuildContext context) => _hideSystemStatus
      ? (_systemStatusExtent(context) - MediaQuery.viewPaddingOf(context).top)
            .clamp(0.0, double.infinity)
      : 0;

  Widget _pagedLeaf(ReaderLeaf page, TextStyle style) {
    if (page.fragments.length == 1 &&
        page.fragments.first.image &&
        readerIllustrationUrl(
              page.fragments.first.text,
            )?.startsWith('wenku-local:') !=
            true) {
      return ReaderTurnPart(
        bounds: page.fragments.first.rect,
        child: _paragraphContent(
          _currentContent!.paragraphs,
          page.fragments.first.paragraph,
          style,
          fullPage: true,
        ),
      );
    }
    if (_readerMode == ReaderMode.vertical) {
      final key = GlobalKey(debugLabel: 'reader-vertical-page');
      Offset? doubleTap;
      Widget verticalPage(
        BuildContext context,
        ({bool active, int? paragraph}) listening,
        Widget? child,
      ) => AnimatedBuilder(
        animation: Listenable.merge([_findMatch, _bookmarkLanding]),
        builder: (context, _) {
          final match = _findMatch.value;
          final body = ReaderSelectionFragment(
            controller: _selection,
            text: page.text,
            paragraphEnds: [
              for (var i = 0; i < page.glyphs.length; i++)
                if (i + 1 == page.glyphs.length ||
                    page.glyphs[i].paragraph != page.glyphs[i + 1].paragraph)
                  page.glyphs[i].end,
            ],
            anchorForOffset: (offset) {
              for (final glyph in page.glyphs) {
                if (glyph.end > offset) {
                  return (
                    paragraph: glyph.paragraph,
                    offset:
                        glyph.sourceStart +
                        (offset - glyph.start).clamp(
                          0,
                          glyph.sourceEnd - glyph.sourceStart,
                        ),
                  );
                }
              }
              return null;
            },
            child: ReaderVerticalText(
              key: key,
              page: page,
              glyphCache: _verticalGlyphs,
              style: style.copyWith(
                fontSize: MediaQuery.textScalerOf(
                  context,
                ).scale(style.fontSize ?? 19),
              ),
              highlightParagraph: _bookmarkLanding.value,
              listeningParagraph: listening.paragraph,
              match: match == null
                  ? null
                  : (
                      paragraph: match.paragraph,
                      start: match.start,
                      end: match.end,
                    ),
            ),
          );
          return !listening.active
              ? body
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTapDown: (details) =>
                      doubleTap = details.localPosition,
                  onDoubleTap: () {
                    if (_selection.value || doubleTap == null) return;
                    final render = key.currentContext?.findRenderObject();
                    final glyph = render is RenderReaderVerticalText
                        ? render.glyphAt(doubleTap!)
                        : null;
                    if (glyph != null) {
                      unawaited(
                        _doubleTapListeningParagraph(
                          glyph.paragraph,
                        ).catchError((Object _) {}),
                      );
                    }
                  },
                  child: body,
                );
        },
      );
      final controller = _listening;
      final body = controller == null
          ? verticalPage(context, (active: false, paragraph: null), null)
          : SelectedValueBuilder<
              ListeningSnapshot,
              ({bool active, int? paragraph})
            >(
              listenable: controller.snapshot,
              select: (state) {
                final active =
                    state.active && state.novel?.id == widget.novel.id;
                return (
                  active: active,
                  paragraph: active && state.chapter == _chapter
                      ? state.current?.paragraph
                      : null,
                );
              },
              builder: verticalPage,
            );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: body),
          for (final (index, fragment) in page.fragments.indexed)
            if (fragment.image)
              Positioned.fromRect(
                rect: fragment.rect,
                child: ReaderFragmentMotion(
                  fragment: fragment,
                  index: index,
                  count: page.fragments.length,
                  child: _paragraphContent(
                    _currentContent!.paragraphs,
                    fragment.paragraph,
                    style,
                    sizedImage: true,
                  ),
                ),
              ),
        ],
      );
    }
    return Builder(
      builder: (context) {
        final previous = ReaderReflowScope.maybeOf(context)?.previous.fragments;
        final identities = {
          for (final fragment in page.fragments)
            (fragment.paragraph, fragment.start),
        };
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (index, fragment) in page.fragments.indexed)
              Positioned.fromRect(
                rect: fragment.rect,
                child: ReaderFragmentMotion(
                  fragment: fragment,
                  index: index,
                  count: page.fragments.length,
                  previousBuilder: (old) => _horizontalFragment(old, style),
                  child: _horizontalFragment(fragment, style),
                ),
              ),
            if (previous != null)
              for (final (index, fragment) in previous.indexed)
                if (!identities.contains((fragment.paragraph, fragment.start)))
                  Positioned.fromRect(
                    rect: fragment.rect,
                    child: ReaderLeavingFragment(
                      fragment: fragment,
                      index: index,
                      count: previous.length,
                      child: _horizontalFragment(fragment, style),
                    ),
                  ),
          ],
        );
      },
    );
  }

  Widget _horizontalFragment(ReaderPageFragment fragment, TextStyle style) =>
      ValueListenableBuilder<int?>(
        valueListenable: _bookmarkLanding,
        child: Builder(
          builder: (context) {
            if (fragment.image) {
              return _paragraphContent(
                _currentContent!.paragraphs,
                fragment.paragraph,
                style,
                sizedImage: true,
              );
            }
            final text = ReaderSelectionFragment(
              controller: _selection,
              text: fragment.text,
              selectableOffset: fragment.indent ? readerIndentLength : 0,
              anchorForOffset: (offset) => (
                paragraph: fragment.paragraph,
                offset: fragment.start + offset.clamp(0, fragment.text.length),
              ),
              child: ReaderHighlightText(
                text: fragment.text,
                index: fragment.paragraph,
                sourceStart: fragment.start,
                match: _findMatch,
                style: style,
                indent: fragment.indent,
                textAlign: widget.state.readerPreferences.justify
                    ? TextAlign.justify
                    : TextAlign.start,
              ),
            );
            return _listening == null
                ? text
                : ListeningParagraphHighlight(
                    controller: _listening!,
                    novelId: widget.novel.id,
                    chapter: _chapter,
                    paragraph: fragment.paragraph,
                    onDoubleTap: () =>
                        _doubleTapListeningParagraph(fragment.paragraph),
                    child: text,
                  );
          },
        ),
        builder: (context, selected, child) => selected == fragment.paragraph
            ? ReaderLandingHighlight(
                reduceMotion: widget.state.reduceMotion,
                child: child!,
              )
            : child!,
      );

  void _landBookmark(ReadingPosition? saved, {int? paragraphIndex}) {
    if (!_bookmarkLandingPending ||
        (_paginated ? !_paged.ready : !_scroll.hasClients)) {
      return;
    }
    _bookmarkLandingPending = false;
    final savedIndex = paragraphIndex ?? saved?.paragraphIndex;
    final index =
        savedIndex != null && savedIndex >= 0 && savedIndex < _paragraphCount
        ? savedIndex
        : (_paginated
                  ? _paged.anchor?.paragraph
                  : _paragraphRegistry
                        .capture(_scroll.offset + _readingInset)
                        ?.index) ??
              0;
    if (index >= _paragraphCount) return;
    _bookmarkLanding.value = index;
    _bookmarkLandingTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) _bookmarkLanding.value = null;
    });
  }

  void _applyTypography({
    double? fontSize,
    double? lineHeight,
    bool persist = true,
  }) {
    final font = fontSize ?? widget.state.fontSize;
    final spacing = lineHeight ?? widget.state.lineHeight;
    if (font == widget.state.fontSize && spacing == widget.state.lineHeight) {
      if (persist) {
        unawaited(
          widget.state
              .setTypography(fontSize: fontSize, lineHeight: lineHeight)
              .catchError((Object _) {
                if (mounted) showNovelFeedback(context, '排版设置保存失败，请重试');
              }),
        );
      }
      return;
    }
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
    unawaited(
      widget.state
          .setTypography(
            fontSize: fontSize,
            lineHeight: lineHeight,
            persist: persist,
          )
          .catchError((Object _) {
            if (mounted) showNovelFeedback(context, '排版设置保存失败，请重试');
          }),
    );
  }

  void _applyReaderPreferences(ReaderPreferences value, bool persist) {
    final changesLayout =
        value.layoutKey != widget.state.readerPreferences.layoutKey;
    if (changesLayout) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
    }
    unawaited(
      widget.state.setReaderPreferences(value, persist: persist).catchError((
        Object _,
      ) {
        if (mounted) {
          _restoring = false;
          showNovelFeedback(context, '阅读偏好保存失败，请重试');
        }
      }),
    );
  }

  Future<ReaderBookmark?> _addBookmark() async {
    final position = _currentPosition(bookmark: true);
    if (position == null) return null;
    _savePosition(notify: false);
    final index = position.paragraphIndex;
    final text = index == null ? '' : _currentContent?.paragraphs[index] ?? '';
    return widget.state.addBookmark(
      novel: widget.novel,
      position: position,
      quote:
          readerIllustrationUrl(text) == null &&
              text != '[插图]' &&
              text.length <= 12000
          ? text
          : '',
    );
  }

  ReadingPosition? _quotePosition(ReaderQuoteSelection selected) {
    final position = _currentPosition(bookmark: true), anchor = selected.anchor;
    if (position == null || anchor == null) return null;
    return ReadingPosition.fromJson({
      ...position.toJson(),
      'paragraphIndex': anchor.paragraph,
      'textOffset': anchor.offset,
      'paragraphFraction': 0,
    });
  }

  Future<void> _saveQuote(ReaderQuoteSelection selected) async {
    final position = _quotePosition(selected);
    if (position == null) {
      showNovelFeedback(context, '暂时无法定位选中的文字，请重新选择');
      return;
    }
    _selection.clear();
    try {
      final mark = await widget.state.addBookmark(
        novel: widget.novel,
        position: position,
        quote: selected.text,
      );
      if (mounted) {
        showNovelFeedback(context, mark == null ? '书签未能保存，请重试' : '已加入书签');
      }
    } catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '书签保存失败，请重试',
        );
      }
    }
  }

  Future<void> _volumeIllustrations() async {
    _cancelExitRequest();
    _selection.clear();
    _stopAutoScroll();
    _suspendListeningFollow();
    await pushNovelPage<void>(
      context,
      ReaderVolumeIllustrationsPage(
        novel: widget.novel,
        chapter: _chapter,
        repository: widget.repository,
        known: {..._preparedContent, _chapter: ?_currentContent},
        reduceMotion: widget.state.reduceMotion,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
  }

  void _illustrationLayoutChanged() {
    final source = _preparedContent[_chapter];
    if (!mounted || source == null) return;
    final position = _currentPosition(bookmark: true);
    if (position != null) _prepareRestore(position);
    final content = placeIllustrations(
      _automaticContent[_chapter]?.$2 ?? source,
      widget.state.illustrationsFor(
        widget.novel.id,
        chapterId: widget.novel.chapters[_chapter].id,
      ),
    ).localized(Locale('zh', _readerRegion ?? 'CN'));
    setState(() {
      _currentContent = content;
      _content = Future.value((content: content, error: null));
    });
  }

  Future<void> _openIllustrationLayout([ReaderQuoteSelection? selected]) async {
    final source = _preparedContent[_chapter];
    final anchor = selected?.anchor;
    if (selected != null &&
        (source == null ||
            anchor == null ||
            anchor.paragraph >= source.paragraphs.length)) {
      return;
    }
    _selection.clear();
    _stopAutoScroll();
    _suspendListeningFollow();
    final inserted = await pushNovelPage<bool>(
      context,
      IllustrationLayoutPage(
        novel: widget.novel,
        chapter: _chapter,
        state: widget.state,
        repository: widget.repository,
        source: source,
        paragraph: anchor?.paragraph,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (mounted && inserted == true) {
      showNovelFeedback(context, '已嵌入段落之后，长按插图可移除');
    }
  }

  Future<void> _removePlacedIllustration(String id) async {
    if (!await confirmNovelAction(
      context,
      title: '移除此处插图？',
      message: '仅移除正文中的排版位置，卷末原图和正文保留。',
      confirmLabel: '移除插图位置',
      reduceMotion: widget.state.reduceMotion,
    )) {
      return;
    }
    try {
      await widget.state.removeIllustration(widget.novel.id, id);
    } catch (_) {
      if (mounted) showNovelFeedback(context, '插图位置移除失败，请重试');
    }
  }

  Future<void> _seekProgress(double fraction) async {
    if (!_ready || (_paginated ? !_paged.ready : !_scroll.hasClients)) return;
    _clearBookmarkLanding();
    if (_paginated) {
      _paged.seek(fraction);
      return;
    }
    final value = fraction.clamp(0.0, 1.0);
    final generation = _contentGeneration;
    final ticket = ++_restoreTicket;
    _restoring = true;
    // A lazy sliver refines its estimate after a large jump. Follow that new
    // extent for a bounded number of frames, including an exact chapter end.
    for (var step = 0; step < 4; step++) {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients) {
        return;
      }
      final maximum = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(value * maximum);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients) {
        return;
      }
      if ((_scroll.position.maxScrollExtent - maximum).abs() < .5) break;
    }
    _restoring = false;
    _savePosition(notify: false);
  }

  void _restoreAfterLayout() {
    if (_paginated) return;
    if (_restoreQueued) return;
    _restoreQueued = true;
    final generation = _contentGeneration;
    final ticket = ++_restoreTicket;
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients ||
          !_ready) {
        return;
      }
      final saved = _restorePending;
      _restorePending = null;
      int? landingParagraph;
      if (saved != null) {
        final centreBookmark = _bookmarkLandingPending;
        final viewportBottom = centreBookmark
            ? (_scroll.position.viewportDimension -
                      MediaQuery.paddingOf(context).bottom -
                      96)
                  .clamp(_readingInset + 1, double.infinity)
            : null;
        final sameLayout =
            (saved.fontSize - widget.state.fontSize).abs() < .01 &&
            (saved.lineHeight - widget.state.lineHeight).abs() < .01 &&
            (saved.width - _layoutWidth).abs() < 1 &&
            (saved.textScale - _textScale).abs() < .01 &&
            saved.typeface == widget.state.readerFontId;
        final identicalLayout =
            sameLayout &&
            saved.layout == widget.state.readerPreferences.layoutKey;
        var anchor =
            saved.paragraphIndex != null &&
                saved.paragraphIndex! >= 0 &&
                saved.paragraphIndex! < _paragraphCount
            ? (index: saved.paragraphIndex!, fraction: saved.paragraphFraction)
            : null;
        for (var step = 0; step < 10; step++) {
          if (!mounted ||
              generation != _contentGeneration ||
              ticket != _restoreTicket ||
              !_scroll.hasClients) {
            return;
          }
          final maximum = _scroll.position.maxScrollExtent;
          final paragraph = anchor == null
              ? null
              : _paragraphRegistry.target(
                  anchor,
                  _readingInset,
                  viewportBottom: viewportBottom,
                  trailingSpace: centreBookmark ? 12 : 0,
                );
          final textOffset = saved.textOffset;
          final fromPaged =
              saved.layout.endsWith(':paged') ||
              saved.layout.endsWith(':vertical');
          final precise =
              fromPaged &&
                  !centreBookmark &&
                  anchor != null &&
                  textOffset != null
              ? _paragraphRegistry.matchOffset(
                  anchor.index,
                  textOffset,
                  textOffset + 1,
                  _readingInset,
                )
              : null;
          final target = identicalLayout && step == 0 && !centreBookmark
              ? saved.offset
              : precise ??
                    paragraph?.offset ??
                    (identicalLayout && saved.fraction < .999
                        ? saved.offset
                        : saved.fraction * maximum);
          if (step == 0 &&
              identicalLayout &&
              !centreBookmark &&
              anchor != null &&
              paragraph?.exact != true) {
            final row =
                _currentContent?.readingOrder?.indexOf(anchor.index) ??
                anchor.index;
            if (row >= 0) {
              _scrollAnchor.restore(
                row: row,
                fraction: anchor.fraction,
                inset: _readingInset,
              );
            }
          }
          _scroll.jumpTo(
            target.clamp(
              0.0,
              centreBookmark && paragraph?.exact == true
                  ? maximum.clamp(0.0, double.infinity)
                  : double.infinity,
            ),
          );
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              generation != _contentGeneration ||
              ticket != _restoreTicket ||
              !_scroll.hasClients) {
            return;
          }
          // Older bookmarks stored only pixels. Resolve that position once,
          // then use the same paragraph-centred refinement as newer bookmarks.
          if (centreBookmark && anchor == null) {
            anchor = _paragraphRegistry.capture(
              _scroll.offset + _readingInset,
              clampToLast: true,
            );
          }
          final refined = anchor == null
              ? null
              : _paragraphRegistry.target(
                  anchor,
                  _readingInset,
                  viewportBottom: viewportBottom,
                  trailingSpace: centreBookmark ? 12 : 0,
                );
          final preciseRefined =
              fromPaged &&
                  !centreBookmark &&
                  anchor != null &&
                  textOffset != null
              ? _paragraphRegistry.matchOffset(
                  anchor.index,
                  textOffset,
                  textOffset + 1,
                  _readingInset,
                )
              : null;
          if (refined?.exact == true &&
              (_scroll.offset -
                          (preciseRefined ?? refined!.offset).clamp(
                            0.0,
                            centreBookmark
                                ? _scroll.position.maxScrollExtent.clamp(
                                    0.0,
                                    double.infinity,
                                  )
                                : double.infinity,
                          ))
                      .abs() <
                  .5) {
            break;
          }
          if (anchor == null &&
              (_scroll.position.maxScrollExtent - maximum).abs() < .5) {
            break;
          }
        }
        landingParagraph = anchor?.index;
      }
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket) {
        return;
      }
      _restoring = false;
      _revealChapter();
      _landBookmark(saved, paragraphIndex: landingParagraph);
      _savePosition();
    });
  }

  Future<void> _requestExit() async {
    if (_allowExit) return;
    if (_toolsOpen || _catalogueOpen || _findOpen) {
      _cancelExitRequest();
      return;
    }
    if (_selection.value) {
      _selection.clear();
      _cancelExitRequest();
      return;
    }
    final now = DateTime.now();
    if (_exitRequestedAt == null ||
        now.difference(_exitRequestedAt!) > const Duration(seconds: 2)) {
      _exitRequestedAt = now;
      showNovelFeedback(context, '再滑动一次退出阅读', headerVisibility: _chrome);
      return;
    }
    dismissNovelFeedback(context);
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  void _cancelExitRequest() {
    if (_exitRequestedAt == null) return;
    _exitRequestedAt = null;
    dismissNovelFeedback(context);
  }

  Future<void> _bookDetails() async {
    if (_detailsOpen || _toolsOpen || _catalogueOpen || _findOpen) {
      return;
    }
    _cancelExitRequest();
    _stopAutoScroll();
    _savePosition(notify: false, finalSave: true);
    _detailsOpen = true;
    int? chapter;
    try {
      chapter = await pushNovelPage<int>(
        context,
        DetailPage(
          novel: _sourceBook,
          state: widget.state,
          repository: widget.repository,
          fromCache:
              widget.repository is OfflineNovelRepository &&
              (widget.repository as OfflineNovelRepository).offline,
          onRead: (index) => Navigator.of(context).pop(index),
        ),
        reduceMotion: widget.state.reduceMotion,
        slot: ('reader-details', widget.novel.id),
      );
    } finally {
      _detailsOpen = false;
    }
    if (!mounted) return;
    if (isLocalBook(widget.novel.id) &&
        widget.repository is OfflineNovelRepository) {
      final current = (widget.repository as OfflineNovelRepository).local?.book(
        widget.novel.id,
      );
      if (current == null ||
          current.chapters.length != widget.novel.chapters.length ||
          current.chapters.indexed.any((entry) {
            final original = widget.novel.chapters[entry.$1];
            return entry.$2.id != original.id ||
                entry.$2.title != original.title ||
                entry.$2.volumeId != original.volumeId ||
                entry.$2.volumeTitle != original.volumeTitle;
          })) {
        // An editor can delete/regroup/reorder the underlying originals. Its
        // remapped records must not be overwritten by this obsolete directory.
        _sourceChanged = true;
        Navigator.pop(context);
        return;
      }
      setState(() {});
    }
    if (mounted && chapter != null && chapter != _chapter) {
      _go(chapter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.novel.chapters.isEmpty
        ? const NovelChapter('目录为空', '')
        : widget.novel.chapters[_chapter];
    _layoutWidth = MediaQuery.sizeOf(context).width;
    _layoutTypeface = widget.state.readerFontId;
    final appTheme = Theme.of(context);
    final appDark = appOriginalBrightness(appTheme) == Brightness.dark;
    return PopScope<void>(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: ReaderAppearance(
        state: widget.state,
        appTheme: appTheme,
        child: Builder(
          builder: (context) => _readerScaffold(context, chapter, appDark),
        ),
      ),
    );
  }

  Widget _readerScaffold(
    BuildContext context,
    NovelChapter chapter,
    bool appDark,
  ) => Scaffold(
    // The catalogue owns the keyboard inset; keep the obscured article and
    // its saved scroll geometry fixed while searching in the drawer.
    resizeToAvoidBottomInset: false,
    body: Atmosphere(
      shareGlass: true,
      archiveBackdrop: false,
      child: Stack(
        children: [
          ReaderScreenBinding(state: widget.state, onPage: _pageBy),
          Positioned.fill(
            child: NativeGlassGroup(
              enabled: false,
              inherit: false,
              child: RepaintBoundary(
                key: const ValueKey('reader-article-boundary'),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                          _pageBy(1),
                      const SingleActivator(LogicalKeyboardKey.space): () =>
                          _pageBy(1),
                      const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                          _pageBy(-1),
                      const SingleActivator(LogicalKeyboardKey.home): () =>
                          _seekProgress(0),
                      const SingleActivator(LogicalKeyboardKey.end): () =>
                          _seekProgress(1),
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        control: true,
                      ): _findInChapter,
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        meta: true,
                      ): _findInChapter,
                    },
                    child: Focus(
                      autofocus: true,
                      child: Semantics(
                        customSemanticsActions: {
                          const CustomSemanticsAction(label: '切换阅读控件'):
                              _toggleChrome,
                        },
                        child: ReaderSelection(
                          controller: _selection,
                          vertical: _readerMode == ReaderMode.vertical,
                          onBookmark: _saveQuote,
                          onIllustrations: _volumeIllustrations,
                          onSelect: () {
                            _stopAutoScroll();
                            _suspendListeningFollow();
                          },
                          child: GestureDetector(
                            key: const ValueKey('reader-content-tap'),
                            behavior: HitTestBehavior.translucent,
                            onTapUp: _contentTap,
                            child: _article(context, chapter, appDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ReaderChromeLayer(
              key: const ValueKey('reader-chrome-edge-blur'),
              animation: _chrome,
              child: ReaderEdgeBlur(
                animation: _chrome,
                topInset: _chromeStatusInset(context),
                compact: _hideSystemStatus,
                blurBottom: !_hideSystemStatus || _paginated,
              ),
            ),
          ),
          if (LocalPlatform.android)
            Positioned(
              left: 0,
              width: 20,
              top: MediaQuery.paddingOf(context).top + 80,
              bottom: MediaQuery.paddingOf(context).bottom + 116,
              child: ReaderBrightnessGesture(
                state: widget.state,
                onChanged: _applyReaderPreferences,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(top: _chromeStatusInset(context)),
              child: FrostedHeader(
                blurBackground: false,
                child: ReaderChromeLayer(
                  key: const ValueKey('reader-chrome-header'),
                  animation: _chrome,
                  slide: const Offset(0, -1),
                  child: ActiveListenableBuilder(
                    listenable: widget.state.settingsChanges,
                    builder: (context) => ArchiveHeaderBar(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassIconButton(
                            icon: CupertinoIcons.back,
                            label: widget.directEntry ? '返回' : '返回详情',
                            onPressed: () {
                              dismissNovelFeedback(context);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      title: ArchiveRouteTitle(
                        title: _sourceBook.title,
                        code:
                            'READ / ${ArchiveDesign.fileCode(widget.novel.id)}',
                      ),
                      actions: [
                        if (widget.state.directReading) ...[
                          GlassIconButton(
                            key: const ValueKey('reader-details-entry'),
                            icon: CupertinoIcons.info_circle,
                            label: '进入详情页',
                            onPressed: _bookDetails,
                          ),
                        ],
                        const SizedBox(width: 4),
                        GlassIconButton(
                          key: const ValueKey('reader-settings-entry'),
                          icon: CupertinoIcons.textformat_size,
                          label: '阅读设置',
                          onPressed: _settings,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                22 + MediaQuery.paddingOf(context).left,
                0,
                22 + MediaQuery.paddingOf(context).right,
                MediaQuery.paddingOf(context).bottom + 12,
              ),
              child: ReaderChromeLayer(
                key: const ValueKey('reader-chrome-dock'),
                animation: _chrome,
                slide: const Offset(0, 1),
                paintPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_autoPaused)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_autoPaused)
                              GlassTextButton(
                                key: const ValueKey('reader-auto-resume'),
                                onPressed: _startAutoScroll,
                                child: AppText(
                                  _paginated ? '继续自动翻页' : '继续自动滚动',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ActiveListenableBuilder(
                      listenable: widget.state.settingsChanges,
                      builder: (context) => GlassDock(
                        key: const ValueKey('reader-liquid-dock'),
                        selectedIndex: 1,
                        reduceMotion: widget.state.reduceMotion,
                        items: [
                          GlassDockItem(
                            CupertinoIcons.arrow_left,
                            '上一章',
                            enabled: _chapter > 0,
                          ),
                          GlassDockItem(
                            CupertinoIcons.book,
                            '${widget.novel.chapters.isEmpty ? 0 : _chapter + 1} / ${widget.novel.chapters.length}',
                            id: 'reader-catalogue',
                            enabled: widget.novel.chapters.isNotEmpty,
                            selectableOnDrag: false,
                            semanticLabel:
                                '目录，当前第 ${widget.novel.chapters.isEmpty ? 0 : _chapter + 1} 章，共 ${widget.novel.chapters.length} 章',
                          ),
                          GlassDockItem(
                            CupertinoIcons.arrow_right,
                            '下一章',
                            enabled:
                                _chapter + 1 < widget.novel.chapters.length,
                          ),
                        ],
                        onSelected: (index) {
                          if (index == 1) {
                            _catalogue();
                          } else {
                            _go(_chapter + (index == 0 ? -1 : 1));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_listening != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: ValueListenableBuilder<bool>(
                valueListenable: _followPrompt,
                builder: (context, visible, _) => ReaderFollowDock(
                  visible: visible,
                  chrome: _chrome,
                  extraControlsHeight: _autoPaused ? 64 : 0,
                  reduceMotion: widget.state.reduceMotion,
                  onEnable: _enableListeningFollow,
                ),
              ),
            ),
          if (_hideSystemStatus)
            Positioned(
              left: MediaQuery.viewPaddingOf(context).left + 26,
              right: MediaQuery.viewPaddingOf(context).right + 26,
              top: 0,
              child: const ReaderStatusFooter(),
            ),
        ],
      ),
    ),
  );

  Widget _article(
    BuildContext context,
    NovelChapter chapter,
    bool dark,
  ) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    builder: (context, child) => FutureBuilder<({ReaderContent? content, Object? error})>(
      future: _content,
      builder: (context, snapshot) {
        final prefs = widget.state.readerPreferences;
        _layoutKey = prefs.layoutKey;
        _layoutTextScale =
            MediaQuery.textScalerOf(context).scale(widget.state.fontSize) /
            widget.state.fontSize;
        // Scroll offsets are relative to the inset, clipped viewport, not the
        // status bar. Keep that band clear even after all glass is hidden.
        _readingInset = _scrollReadingInset(prefs);
        final content = _currentContent;
        final ready = content != null;
        final failed =
            snapshot.connectionState == ConnectionState.done &&
            (snapshot.hasError || snapshot.data?.error != null);
        _ready = ready;
        if (ready) {
          _restoreAfterLayout();
          _scheduleChromeHint();
        }
        final paragraphs = ready ? content.paragraphs : const <String>[];
        _paragraphCount = paragraphs.length;
        // Pagination must measure the exact resolved style that Text paints,
        // including the theme's leading distribution and fallback metrics.
        // Android emoji/CJK fallback otherwise makes the final line taller
        // than the fragment measured with a standalone partial TextStyle.
        final paragraphStyle = DefaultTextStyle.of(context).style
            .merge(
              TextStyle(
                fontFamily: widget.state.readerFontFamily ?? 'Roboto',
                fontSize: widget.state.fontSize,
                height: widget.state.lineHeight,
                letterSpacing: .1,
                color: prefs.foreground(dark),
              ),
            )
            .copyWith(inherit: false);
        final rowSpec = (
          content,
          _contentGeneration,
          paragraphStyle,
          prefs.indent,
          prefs.justify,
          prefs.paragraphGap,
          widget.state.fontSize,
          _listening,
          _chapterRevealFirst,
          _illustrationsRefreshing,
          widget.state.reduceMotion,
        );
        if (_paragraphWidgetSpec != rowSpec) {
          _paragraphWidgetSpec = rowSpec;
          _paragraphWidgets.clear();
        }
        final safe = MediaQuery.viewPaddingOf(context);
        final pagedPadding = EdgeInsets.fromLTRB(
          prefs.leftMargin + safe.left,
          (prefs.hideSystemStatus ? _systemStatusExtent(context) : safe.top) +
              prefs.marginTop +
              (_chromeReserved ? FrostedHeader.toolbarHeight + 4 : 0),
          prefs.rightMargin + safe.right,
          safe.bottom +
              (_chromeReserved ? 70 + (_autoPaused ? 64 : 0) : 0) +
              prefs.marginBottom,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: novelSystemUiStyle(
            ThemeData.estimateBrightnessForColor(prefs.background(dark)),
          ),
          child: ReaderBackgroundSurface(
            preferences: prefs,
            paper: prefs.background(dark),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: prefs.foreground(dark)),
              child: _paginated && !ready && !failed
                  ? ReaderPageSkeleton(
                      title: chapter.title,
                      padding: pagedPadding,
                      style: paragraphStyle,
                      vertical: prefs.mode == ReaderMode.vertical,
                      margin: prefs.bindingMargin,
                    )
                  : _paginated && ready
                  ? ReaderPagedView(
                      key: ValueKey('reader-pages-$_contentGeneration'),
                      content: content,
                      controller: _paged,
                      preferences: prefs,
                      style: paragraphStyle,
                      title: chapter.title,
                      position: _restorePending,
                      padding: pagedPadding,
                      reduceMotion: widget.state.reduceMotion,
                      onReady: _pagedReady,
                      onChanged: _saveWhenIdle,
                      onUserScroll: () {
                        _cancelExitRequest();
                        _stopAutoScroll();
                        _suspendListeningFollow(userDrag: true);
                        _clearBookmarkLanding();
                      },
                      onBoundary: _pageBy,
                      pageBuilder: (page) => _pagedLeaf(page, paragraphStyle),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.depth == 0) {
                          if (notification is ScrollStartNotification) {
                            _idleSave?.cancel();
                            if (notification.dragDetails != null) {
                              _cancelExitRequest();
                              _scrollGesture = true;
                              _edgeDrag = 0;
                              _scrollDirection = 0;
                              _stopAutoScroll();
                              _suspendListeningFollow(userDrag: true);
                              _clearBookmarkLanding();
                              _restoreTicket++;
                              _restorePending = null;
                              _restoring = false;
                              _revealChapter();
                            }
                          } else if (notification is ScrollUpdateNotification &&
                              _scrollGesture) {
                            final delta = notification.scrollDelta ?? 0;
                            if (delta.abs() > .1) {
                              _scrollDirection = delta.sign.toInt();
                            }
                          } else if (notification is OverscrollNotification &&
                              notification.dragDetails != null &&
                              _scrollGesture) {
                            _edgeDrag += notification.overscroll;
                            if (_edgeDrag.abs() > 40) {
                              _continueChapter(_edgeDrag > 0 ? 1 : -1);
                            }
                          } else if (notification is ScrollEndNotification) {
                            // A new drag stops the old fling and emits scroll-end
                            // inside its input callback. Do no anchor/storage work in
                            // that callback; save only after genuine, stable idle.
                            _saveWhenIdle();
                            if (_scrollGesture &&
                                _scrollDirection > 0 &&
                                notification.metrics.extentAfter <= .5) {
                              _continueChapter(1);
                            }
                            _scrollGesture = false;
                          }
                        }
                        return false;
                      },
                      child: Padding(
                        padding: EdgeInsets.only(
                          top:
                              (prefs.hideSystemStatus
                                  ? _systemStatusExtent(context)
                                  : safe.top) +
                              prefs.marginTop,
                          left: safe.left,
                          right: safe.right,
                          bottom:
                              safe.bottom +
                              (prefs.hideSystemStatus ? 0 : prefs.marginBottom),
                        ),
                        child: ClipRect(
                          key: const ValueKey('reader-scroll-safe-viewport'),
                          child: CustomScrollView(
                            key: const ValueKey('reader-scroll'),
                            controller: _scroll,
                            physics: const ClampingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            cacheExtent:
                                (MediaQuery.sizeOf(context).height * .75).clamp(
                                  250.0,
                                  900.0,
                                ),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  prefs.leftMargin,
                                  prefs.hideSystemStatus
                                      ? 16
                                      : FrostedHeader.toolbarHeight + 16,
                                  prefs.rightMargin,
                                  28,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          AppText(
                                            '第 ${_chapter + 1} 章',
                                            style: TextStyle(
                                              color: prefs
                                                  .foreground(dark)
                                                  .withValues(alpha: .65),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: ArchiveCode(
                                                'CH.${(_chapter + 1).toString().padLeft(3, '0')} / TEXT',
                                                color: prefs
                                                    .foreground(dark)
                                                    .withValues(alpha: .65),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      AppText(
                                        chapter.title,
                                        key: const ValueKey(
                                          'reader-chapter-title',
                                        ),
                                        style: TextStyle(
                                          color: prefs.foreground(dark),
                                          fontSize: 23,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (failed)
                                SliverToBoxAdapter(
                                  child: Column(
                                    children: [
                                      const AppText('章节加载失败'),
                                      GlassTextButton(
                                        onPressed: () => setState(() {
                                          _content = _loadContent();
                                        }),
                                        child: const AppText('重试'),
                                      ),
                                    ],
                                  ),
                                )
                              else if (!ready)
                                SliverPadding(
                                  padding: EdgeInsets.only(
                                    left: prefs.leftMargin,
                                    right: prefs.rightMargin,
                                  ),
                                  sliver: const SliverToBoxAdapter(
                                    child: ReaderSkeleton(),
                                  ),
                                )
                              else ...[
                                SliverPadding(
                                  padding: EdgeInsets.only(
                                    left: prefs.leftMargin,
                                    right: prefs.rightMargin,
                                  ),
                                  sliver: ReaderScrollSliver(
                                    anchor: _scrollAnchor,
                                    itemCount:
                                        content.readingOrder?.length ??
                                        paragraphs.length,
                                    itemBuilder: (context, row) {
                                      final index =
                                          content.readingOrder?[row] ?? row;
                                      // A bounded LRU retains nearby widget
                                      // descriptions, not eager render objects.
                                      // Chrome and behavior-only changes reuse
                                      // the exact mounted prose subtree.
                                      if (_paragraphWidgets.remove(index)
                                          case final cached?) {
                                        _paragraphWidgets[index] = cached;
                                        return cached;
                                      }
                                      final child = ReaderParagraph(
                                        key: ValueKey(
                                          'paragraph-anchor-$_contentGeneration-$index',
                                        ),
                                        registry: _paragraphRegistry,
                                        index: index,
                                        textOffset: prefs.indent
                                            ? readerIndentLength
                                            : 0,
                                        child: LoadedContentItem(
                                          key: ValueKey(
                                            'reader-paragraph-reveal-$index',
                                          ),
                                          index: row - _chapterRevealFirst,
                                          animation: _chapterReveal,
                                          placeholder: const LoadingSkeleton(
                                            layout: SkeletonLayout.reader,
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              bottom: prefs.paragraphGap,
                                            ),
                                            child: ValueListenableBuilder<int?>(
                                              valueListenable: _bookmarkLanding,
                                              child: _listening == null
                                                  ? _paragraphContent(
                                                      paragraphs,
                                                      index,
                                                      paragraphStyle,
                                                    )
                                                  : ListeningParagraphHighlight(
                                                      controller: _listening!,
                                                      novelId: widget.novel.id,
                                                      chapter: _chapter,
                                                      paragraph: index,
                                                      onDoubleTap: () =>
                                                          _doubleTapListeningParagraph(
                                                            index,
                                                          ),
                                                      interactive:
                                                          readerIllustrationUrl(
                                                                paragraphs[index],
                                                              ) ==
                                                              null &&
                                                          paragraphs[index]
                                                                  .trim() !=
                                                              '[插图]' &&
                                                          hasSpeechText(
                                                            paragraphs[index],
                                                          ),
                                                      child: _paragraphContent(
                                                        paragraphs,
                                                        index,
                                                        paragraphStyle,
                                                      ),
                                                    ),
                                              builder:
                                                  (
                                                    context,
                                                    selected,
                                                    child,
                                                  ) => selected == index
                                                  ? ReaderLandingHighlight(
                                                      key: ValueKey(
                                                        'bookmark-landing-$index',
                                                      ),
                                                      reduceMotion: widget
                                                          .state
                                                          .reduceMotion,
                                                      child: child!,
                                                    )
                                                  : child!,
                                            ),
                                          ),
                                        ),
                                      );
                                      final result =
                                          content.inlineOwners.containsKey(
                                            index,
                                          )
                                          ? _paragraphContent(
                                              paragraphs,
                                              index,
                                              paragraphStyle,
                                            )
                                          : child;
                                      if (_paragraphWidgets.length >= 96) {
                                        _paragraphWidgets.remove(
                                          _paragraphWidgets.keys.first,
                                        );
                                      }
                                      return _paragraphWidgets[index] = result;
                                    },
                                  ),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.only(
                                    top: 48,
                                    bottom: prefs.hideSystemStatus
                                        ? 32 + prefs.marginBottom
                                        : 108,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          width: 30,
                                          child: Divider(
                                            color: prefs
                                                .foreground(dark)
                                                .withValues(alpha: .25),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        AppText(
                                          '本章完',
                                          style: TextStyle(
                                            color: prefs
                                                .foreground(dark)
                                                .withValues(alpha: .65),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (_chapter + 1 <
                                            widget.novel.chapters.length)
                                          const AppText(
                                            '继续向下阅读下一章',
                                            style: TextStyle(fontSize: 12),
                                          )
                                        else
                                          AppText(
                                            '已读至当前目录末章',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: prefs
                                                  .foreground(dark)
                                                  .withValues(alpha: .65),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    ),
  );

  Future<void> _settings({bool bookmarks = false, String? initialTab}) async {
    _cancelExitRequest();
    if (_toolsOpen || _catalogueOpen || _findOpen) return;
    _selection.clear();
    _stopAutoScroll();
    _toolsOpen = true;
    _followTicket++;
    _followScroll.cancel();
    final position = _currentPosition();
    final preview = ValueNotifier(false);

    try {
      final action = await showJellySheet<ReaderToolAction>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        previewing: preview,
        heightFactor: .86,
        surfaceWrapper: _readerSurface,
        builder: (context) => ReaderTools(
          novel: widget.novel,
          state: widget.state,
          position: position,
          onAddBookmark: _addBookmark,
          onFontSize: (value) => _applyTypography(fontSize: value),
          onLineHeight: (value) => _applyTypography(lineHeight: value),
          onFontPreview: (value) =>
              _applyTypography(fontSize: value, persist: false),
          onLineHeightPreview: (value) =>
              _applyTypography(lineHeight: value, persist: false),
          onPreviewChanged: (value) {
            _typographyPreviewing = value;
            preview.value = value;
          },
          onReset: () {
            _applyTypography(fontSize: 19, lineHeight: 1.72);
            _applyReaderPreferences(
              widget.state.readerPreferences.copyWith(
                margin: 26,
                marginTop: 8,
                marginBottom: 8,
                paragraphGap: 12,
                indent: false,
                justify: false,
              ),
              true,
            );
          },
          initialBookmarks: bookmarks,
          initialTab: initialTab,
          listeningBuilder: _listening == null
              ? null
              : (_) => ListeningPanel(
                  controller: _listening!,
                  novel: widget.novel,
                  chapter: _chapter,
                  paragraph: position?.paragraphIndex ?? 0,
                  embedded: true,
                ),
          onPreferencesChanged: _applyReaderPreferences,
          onIllustrations: isLocalBook(widget.novel.id)
              ? null
              : () => Navigator.pop(context, const ReaderOpenIllustrations()),
        ),
      );
      if (!mounted) return;
      await _handleReaderAction(action);
    } finally {
      _toolsOpen = false;
      _typographyPreviewing = false;
      preview.dispose();
      _listeningTarget = null;
      if (mounted) _listeningChanged();
      _savePosition(notify: false);
    }
  }

  Future<void> _handleReaderAction(ReaderToolAction? action) async {
    switch (action) {
      case ReaderEnterFocus():
        _showChrome(false);
      case ReaderSeekProgress(:final fraction):
        await _seekProgress(fraction);
      case ReaderOpenBookmark(:final bookmark):
        final chapter = widget.state.chapterForPosition(
          widget.novel,
          bookmark.position,
        );
        if (chapter != null) {
          _go(chapter, position: bookmark.position, highlightBookmark: true);
        }
      case ReaderOpenFind():
        // The settings surface has fully collapsed before opening the next.
        _toolsOpen = false;
        await _findInChapter();
      case ReaderStartAutoScroll():
        _toolsOpen = false;
        _startAutoScroll();
      case ReaderOpenIllustrations():
        _toolsOpen = false;
        await _openIllustrationLayout();
      case null:
        break;
    }
  }

  Future<void> _findInChapter() async {
    _cancelExitRequest();
    final content = _currentContent;
    if (!_ready ||
        content == null ||
        _findOpen ||
        _toolsOpen ||
        _catalogueOpen) {
      return;
    }
    _stopAutoScroll();
    _clearBookmarkLanding();
    _suspendListeningFollow();
    _findOpen = true;
    final generation = _contentGeneration;
    try {
      final match = await showJellySheet<ReaderMatch>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
        builder: (_) => ReaderFindPanel(content: content),
      );
      if (!mounted || match == null || generation != _contentGeneration) return;
      _highlightTimer?.cancel();
      _findMatch.value = match;
      // A manual drag can interrupt lazy positioning before it completes.
      // Expiration belongs to selection, not to successful restoration.
      _highlightTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) _findMatch.value = null;
      });
      if (_paginated) {
        _paged.reveal(ReaderTextAnchor(match.paragraph, match.start));
        _saveWhenIdle();
        _showChrome(true);
        return;
      }
      final ticket = ++_restoreTicket;
      _restoring = true;
      for (var step = 0; step < 20; step++) {
        if (!mounted ||
            generation != _contentGeneration ||
            ticket != _restoreTicket ||
            !_scroll.hasClients) {
          return;
        }
        final precise = _paragraphRegistry.matchOffset(
          match.paragraph,
          match.start,
          match.end,
          _readingInset + 8,
        );
        final estimate = _paragraphRegistry.target((
          index: match.paragraph,
          fraction: 0,
        ), _readingInset + 8);
        final target = precise ?? estimate?.offset;
        if (target == null) break;
        _scroll.jumpTo(target.clamp(0.0, double.infinity));
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            generation != _contentGeneration ||
            ticket != _restoreTicket ||
            !_scroll.hasClients) {
          return;
        }
        final refined = _paragraphRegistry.matchOffset(
          match.paragraph,
          match.start,
          match.end,
          _readingInset + 8,
        );
        if (refined != null &&
            (_scroll.offset -
                        refined.clamp(0.0, _scroll.position.maxScrollExtent))
                    .abs() <
                1) {
          break;
        }
      }
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket) {
        return;
      }
      _restoring = false;
      _savePosition(notify: false);
      _showChrome(true);
    } finally {
      _findOpen = false;
    }
  }
}
