import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/network_status.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_catalogue.dart';
import 'package:wenku8_flutter/reading_history.dart';

Novel _directory(int id, {int count = 6, bool longTitles = false}) => Novel(
  id: id,
  title: '阅读作品 $id',
  author: '阅读作者',
  genre: '轻小说',
  summary: '用于目录跳转与阅读历史的界面样本。',
  colors: const [Color(0xFF202020), Color(0xFF333333)],
  chapters: [
    for (var index = 0; index < count; index++)
      NovelChapter(
        longTitles
            ? '第 ${index + 1} 章 ${'长章节标题自然换行 ' * 8}'
            : index == 42
            ? '重逢 Chapter GLASS'
            : index == 400
            ? '重逢后记'
            : '第 ${index + 1} 章',
        '',
        id: id * 10000 + index + 1,
      ),
  ],
);

String _body(int cid) => List.generate(
  60,
  (index) => '正文 $cid 段落 $index：目录跳转、离线读取和阅读位置回归。' * 3,
).join('\n\n');

class _ReaderRepository extends DemoNovelRepository {
  final books = <int, Novel>{71: _directory(71), 72: _directory(72)};
  final bodies = <int>[];
  final held = <int, Completer<String>>{};
  final failed = <int>{};
  bool failFind = false;
  int findCalls = 0;

  @override
  Future<List<Novel>> list() async => books.values.toList();
  @override
  Future<Novel?> find(int id) async {
    findCalls++;
    if (failFind) throw StateError('metadata fixture offline');
    return books[id];
  }

  @override
  Future<Novel> detail(Novel novel) async => books[novel.id]!;
  @override
  Future<List<NovelChapter>> chapters(int id) async => books[id]!.chapters;
  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) async {
    bodies.add(chapter.id);
    if (failed.contains(chapter.id)) throw StateError('body fixture failure');
    if (held[chapter.id] case final Completer<String> pending) {
      return pending.future;
    }
    return _body(chapter.id);
  }
}

Finder _control(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is GlassIconButton && widget.label == label,
      ),
      matching: find.byType(InkWell),
    )
    .first;

ScrollableState _scroll(WidgetTester tester, String key) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Finder _chapterControl(int index) => find
    .descendant(
      of: find.byKey(ValueKey('reader-chapter-$index')),
      matching: find.byType(InkWell),
    )
    .first;

Future<void> _settleIo(WidgetTester tester) async {
  for (var step = 0; step < 12; step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main({
  Future<void> Function(WidgetTester tester, GlobalKey key, String name)?
  capture,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;
  late _ReaderRepository remote;
  late Directory directory;
  late OfflineCacheStore cache;
  late OfflineNovelRepository offline;
  late GlobalKey imageKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
      'reduceMotion': true,
    });
    state = await LibraryState.load();
    remote = _ReaderRepository();
    directory = await Directory.systemTemp.createTemp('novel8-reading-ui-');
    cache = OfflineCacheStore(directory);
    await cache.load();
    offline = OfflineNovelRepository(remote: remote, cache: cache);
    imageKey = GlobalKey();
  });
  tearDown(() async {
    offline.dispose();
    cache.dispose();
    state.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> shot(WidgetTester tester, String name) async {
    if (capture != null) await capture(tester, imageKey, name);
  }

  Future<void> reader(
    WidgetTester tester, {
    Novel? novel,
    int chapter = 0,
    NovelRepository? repository,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: imageKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: novelTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: state.reduceMotion,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: ReaderPage(
            novel: novel ?? remote.books[71]!,
            state: state,
            repository: repository ?? remote,
            initialChapter: chapter,
          ),
        ),
      ),
    );
    if (repository is OfflineNovelRepository) {
      await _settleIo(tester);
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> history(
    WidgetTester tester, {
    NovelRepository? repository,
  }) async {
    final source = repository ?? remote;
    await tester.pumpWidget(
      RepaintBoundary(
        key: imageKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: novelTheme(Brightness.light),
          home: ReadingHistoryPage(
            state: state,
            repository: source,
            onOpen: (context, id, novel) =>
                openDetail(context, novel ?? remote.books[id]!, state, source),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCatalogue(WidgetTester tester) async {
    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    if (find.text('章节目录').evaluate().isNotEmpty) {
      await tester.tap(find.text('章节目录'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'reader Dock opens a lazy long directory and numeric search jumps within the same reader',
    (tester) async {
      final novel = _directory(71, count: 1200);
      remote.books[71] = novel;
      await state.setReduceMotion(false);
      await reader(tester, novel: novel, chapter: 876);
      final prepared = List.of(remote.bodies);
      expect(prepared.toSet(), {
        for (final index in [875, 876, 877]) novel.chapters[index].id,
      });
      await openCatalogue(tester);
      expect(find.byType(ReaderCatalogue), findsOneWidget);
      expect(find.byType(GlassOverlaySurface), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-chapter-876')), findsOneWidget);
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget is JellyTapSurface &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'reader-chapter-',
            ),
      );
      expect(rows.evaluate().length, lessThan(40));
      expect(find.byKey(const ValueKey('reader-chapter-0')), findsNothing);
      await shot(tester, 'reader-directory-long');
      await tester.enterText(
        find.byKey(const ValueKey('reader-chapter-search')),
        '1200',
      );
      await tester.pumpAndSettle();
      expect(find.text('找到 1 章'), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-chapter-1199')), findsOneWidget);
      expect(remote.bodies, prepared);
      await shot(tester, 'reader-directory-search');
      await tester.tap(_chapterControl(1199));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCatalogue), findsNothing);
      expect(find.byType(ReaderPage), findsOneWidget);
      expect(_scroll(tester, 'reader-scroll').position.pixels, 0);
      expect(state.positionFor(71)!.chapterId, novel.chapters.last.id);
      expect(remote.bodies, [
        ...prepared,
        novel.chapters.last.id,
        novel.chapters[1198].id,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current chapter selection and system dismissal retain the reader offset without refetching',
    (tester) async {
      await reader(tester, chapter: 1);
      final prepared = List.of(remote.bodies);
      final scroll = _scroll(tester, 'reader-scroll');
      scroll.position.jumpTo(900);
      await tester.pumpAndSettle();
      final offset = scroll.position.pixels;
      final dock = find.byKey(const ValueKey('reader-liquid-dock'));
      final center = tester.getCenter(dock);
      final drag = await tester.startGesture(center);
      await drag.moveTo(center + const Offset(38, 0));
      await tester.pump(const Duration(milliseconds: 80));
      await drag.moveTo(center);
      await tester.pump(const Duration(milliseconds: 100));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCatalogue), findsNothing);
      expect(remote.bodies, prepared);
      await openCatalogue(tester);
      final viewport = scroll.position.viewportDimension;
      tester.view.viewInsets = FakeViewPadding(
        bottom: 200 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(scroll.position.viewportDimension, viewport);
      expect(scroll.position.pixels, offset);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(_chapterControl(1));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, offset);
      await openCatalogue(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCatalogue), findsNothing);
      expect(scroll.position.pixels, offset);
      expect(remote.bodies, prepared);
      expect(state.positionFor(71)!.offset, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chapter title search, empty results, clear and current locator do not request bodies',
    (tester) async {
      final novel = _directory(71, count: 500);
      remote.books[71] = novel;
      await reader(
        tester,
        novel: novel,
        chapter: 350,
        brightness: Brightness.dark,
      );
      final prepared = List.of(remote.bodies);
      await openCatalogue(tester);
      final search = find.byKey(const ValueKey('reader-chapter-search'));
      await tester.enterText(search, '重逢');
      await tester.pumpAndSettle();
      expect(find.text('找到 2 章'), findsOneWidget);
      await tester.enterText(search, 'glass');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-chapter-42')), findsOneWidget);
      for (final query in ['0', '-1', '501', '未出现的标题']) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的章节'), findsOneWidget);
      }
      await tester.tap(_control('定位当前章节'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, '');
      expect(find.byKey(const ValueKey('reader-chapter-350')), findsOneWidget);
      expect(remote.bodies, prepared);
      await shot(tester, 'reader-directory-dark');
      await tester.tap(_control('关闭目录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed directory jump preserves the old position and a successful retry starts at zero',
    (tester) async {
      final novel = remote.books[71]!;
      await reader(tester);
      _scroll(tester, 'reader-scroll').position.jumpTo(700);
      await tester.pumpAndSettle();
      remote.failed.add(novel.chapters[2].id);
      await openCatalogue(tester);
      await tester.tap(_chapterControl(2));
      await tester.pumpAndSettle();
      expect(find.text('章节未能载入，当前正文已保留，请重试'), findsOneWidget);
      expect(state.positionFor(71)!.chapterId, novel.chapters.first.id);
      expect(state.positionFor(71)!.offset, 700);
      remote.failed.clear();
      await openCatalogue(tester);
      await tester.tap(_chapterControl(2));
      await tester.pumpAndSettle();
      expect(state.positionFor(71)!.chapterId, novel.chapters[2].id);
      expect(_scroll(tester, 'reader-scroll').position.pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late body from an earlier directory jump never replaces the selected chapter',
    (tester) async {
      final novel = remote.books[71]!;
      final pending = Completer<String>();
      remote.held[novel.chapters[1].id] = pending;
      await reader(tester);
      await openCatalogue(tester);
      await tester.tap(_chapterControl(1));
      await tester.pumpAndSettle();
      await openCatalogue(tester);
      await tester.tap(_chapterControl(2));
      await tester.pumpAndSettle();
      pending.complete('过时章节正文');
      await tester.pumpAndSettle();
      expect(find.text('过时章节正文'), findsNothing);
      expect(find.textContaining('正文 ${novel.chapters[2].id}'), findsWidgets);
      expect(state.positionFor(71)!.chapterId, novel.chapters[2].id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline directory marks stored bodies and switches cached chapters without remote calls',
    (tester) async {
      final novel = remote.books[71]!;
      await tester.runAsync(() async {
        final epoch = cache.epochFor(71);
        await cache.saveBook(novel, epoch: epoch);
        for (final chapter in novel.chapters.take(2)) {
          await cache.saveChapter(
            71,
            chapter.id,
            _body(chapter.id),
            epoch: epoch,
          );
        }
      });
      final network = NetworkStatus(initial: NetworkReachability.offline);
      final cached = OfflineNovelRepository(
        remote: remote,
        cache: cache,
        network: network,
      );
      addTearDown(() {
        cached.dispose();
        network.dispose();
      });
      await reader(tester, repository: cached);
      await openCatalogue(tester);
      expect(find.text('已缓存'), findsNWidgets(2));
      await shot(tester, 'reader-directory-offline');
      await tester.tap(_chapterControl(1));
      await _settleIo(tester);
      expect(remote.bodies, isEmpty);
      expect(state.positionFor(71)!.chapterId, novel.chapters[1].id);
      expect(find.textContaining('正文 ${novel.chapters[1].id}'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shelf history finds unshelved books and continues by stable chapter ID',
    (tester) async {
      final old = remote.books[71]!;
      await tester.runAsync(
        () => state.savePosition(
          novel: old,
          chapter: 1,
          offset: 700,
          maximum: 10000,
          width: 800,
        ),
      );
      remote.books[71] = old.withChapters([
        const NovelChapter('插入的新章节', '', id: 710000),
        ...old.chapters,
      ]);
      await tester.pumpWidget(
        RepaintBoundary(
          key: imageKey,
          child: NovelApp(state: state, repository: remote),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dock-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(_control('阅读历史'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-book-71')), findsOneWidget);
      expect(state.shelf, isEmpty);
      expect(remote.findCalls, 0);
      await shot(tester, 'reading-history');
      await tester.tap(find.text('阅读作品 71'));
      await _settleIo(tester);
      await tester.tap(find.byKey(const ValueKey('detail-read-button')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).initialChapter,
        2,
      );
      expect(state.positionFor(71)!.chapterId, old.chapters[1].id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history remove, undo and confirmed clear keep shelf and resume data after reload',
    (tester) async {
      final novel = remote.books[71]!;
      await tester.runAsync(() async {
        await state.toggleShelf(71, novel: novel);
        await state.savePosition(
          novel: novel,
          chapter: 1,
          offset: 900,
          maximum: 3000,
          width: 390,
        );
      });
      final saved = state.positionFor(71)!.toJson();
      await history(tester);
      await tester.tap(_control('阅读作品 71阅读记录操作'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassMenuSurface), findsOneWidget);
      await tester.tap(find.text('移除这条历史'));
      await _settleIo(tester);
      expect(find.text('暂无阅读历史'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await _settleIo(tester);
      expect(find.byKey(const ValueKey('history-book-71')), findsOneWidget);
      await tester.tap(_control('清空阅读历史'));
      await tester.pumpAndSettle();
      await shot(tester, 'reading-history-clear-menu');
      await tester.tap(find.text('保留阅读历史'));
      await tester.pumpAndSettle();
      expect(state.readingHistoryIds, [71]);
      await tester.tap(_control('清空阅读历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空历史，保留进度'));
      await _settleIo(tester);
      await shot(tester, 'reading-history-empty');
      final reopened = await LibraryState.load();
      addTearDown(reopened.dispose);
      expect(reopened.readingHistoryIds, isEmpty);
      expect(reopened.shelf, {71});
      expect(reopened.positionFor(71)!.toJson(), saved);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing history metadata remains removable and can retry independently',
    (tester) async {
      remote.books[99] = _directory(99);
      remote.failFind = true;
      await tester.runAsync(() => state.setChapter(99, 2));
      await history(tester);
      expect(find.text('书籍 99'), findsOneWidget);
      expect(find.text('重试载入书名'), findsOneWidget);
      expect(state.readingHistoryIds, [99]);
      await shot(tester, 'reading-history-missing');
      remote.failFind = false;
      await tester.tap(find.text('重试载入书名'));
      await tester.pumpAndSettle();
      expect(find.text('阅读作品 99'), findsOneWidget);
      expect(state.cachedNovel(99)!.title, '阅读作品 99');
      expect(state.shelf, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings provides history and the new history list builds only visible rows',
    (tester) async {
      await tester.runAsync(() async {
        for (var id = 100; id < 400; id++) {
          final book = _directory(id);
          await state.rememberNovel(book);
          await state.setChapter(id, 0);
        }
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: imageKey,
          child: NovelApp(state: state, repository: remote),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dock-tab-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('my-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-data-entry')));
      await tester.pumpAndSettle();
      final settingsScroll = find.byKey(const PageStorageKey('settings-data'));
      await tester.scrollUntilVisible(
        find.text('阅读历史'),
        200,
        scrollable: find
            .descendant(of: settingsScroll, matching: find.byType(Scrollable))
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('阅读历史')),
        alignment: .4,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('阅读历史'));
      await tester.pumpAndSettle();
      expect(find.text('300 本书'), findsOneWidget);
      final visible = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('history-book-'),
      );
      expect(visible.evaluate().length, lessThan(20));
      expect(remote.findCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large text and a small keyboard viewport keep the catalogue scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 440);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final novel = _directory(71, count: 30, longTitles: true);
      remote.books[71] = novel;
      await reader(tester, novel: novel, chapter: 15, scale: 2);
      await openCatalogue(tester);
      expect(find.byType(ReaderCatalogue), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-chapter-15')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-chapter-15'))).height,
        greaterThan(52),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty directories disable the catalogue control and create no reading history',
    (tester) async {
      await reader(tester, novel: _directory(71, count: 0));
      await tester.tap(find.text('目录'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCatalogue), findsNothing);
      expect(find.text('目录'), findsWidgets);
      expect(state.readingHistoryIds, isEmpty);
      expect(remote.bodies, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
