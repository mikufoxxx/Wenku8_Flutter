import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';
import 'package:wenku8_flutter/offline_widgets.dart';
import 'package:wenku8_flutter/pages.dart';

import 'support/offline_fixture.dart';

const _readKey = ValueKey('detail-read-button');

Widget _app(Widget page, {GlobalKey? capture}) => RepaintBoundary(
  key: capture,
  child: MaterialApp(theme: novelTheme(Brightness.light), home: page),
);

double _phase(WidgetTester tester, String key) => tester
    .renderObject<ArchiveRevealRender>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(ArchiveReveal),
          )
          .first,
    )
    .progress;

class _PendingDetail extends DemoNovelRepository {
  final detailData = Completer<Novel>();
  final directory = Completer<List<NovelChapter>>();
  @override
  Future<Novel> detail(Novel novel) => detailData.future;
  @override
  Future<List<NovelChapter>> chapters(int id) => directory.future;
}

void main({
  Future<void> Function(WidgetTester tester, GlobalKey key, String name)?
  capture,
}) {
  late LibraryState state;
  late Directory directory;
  late OfflineCacheStore cache;
  final novel = offlineFixtureBook(83);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
    });
    state = await LibraryState.load();
    directory = await Directory.systemTemp.createTemp('novel8-detail-polish-');
    cache = OfflineCacheStore(directory);
  });
  tearDown(() async {
    state.dispose();
    cache.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'late author and corrected title share the ready-content cut-in',
    (tester) async {
      phoneViewport(tester);
      final brief = Novel(
        id: novel.id,
        title: '目录前标题',
        author: '',
        genre: novel.genre,
        summary: '',
        colors: novel.colors,
      );
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, loaded, _) => DetailPage(
              novel: loaded ? novel : brief,
              transitionNovel: brief,
              isLoading: !loaded,
              state: state,
              repository: const DemoNovelRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('detail-author-skeleton')),
        findsOneWidget,
      );
      ready.value = true;
      await tester.pump();
      expect(
        find.byKey(const ValueKey('detail-author-skeleton')),
        findsNothing,
      );
      expect(_phase(tester, 'detail-title-reveal'), 0);
      expect(_phase(tester, 'detail-author-reveal'), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _phase(tester, 'detail-title-reveal'),
        greaterThan(_phase(tester, 'detail-author-reveal')),
      );
      await tester.pumpAndSettle();
      expect(find.text(novel.author), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'detail counts and read action remain bones until directory ready',
    (tester) async {
      phoneViewport(tester);
      final pending = _PendingDetail();
      final repository = OfflineNovelRepository(remote: pending, cache: cache);
      addTearDown(repository.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          DetailLoaderPage(
            novel: novel.withChapters(const []),
            state: state,
            repository: repository,
          ),
          capture: key,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('detail-meta-skeleton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('detail-cache-skeleton')),
        findsOneWidget,
      );
      expect(find.byType(OfflineBookStatus), findsNothing);
      expect(find.textContaining('缓存'), findsNothing);
      expect(find.text('正在加载目录'), findsNothing);
      final button = tester.widget<GlassPillButton>(find.byKey(_readKey));
      expect(button.loading, isTrue);
      expect(button.onPressed, isNull);
      expect(tester.binding.transientCallbackCount, 0);
      final download = tester.widget<GlassIconButton>(
        find.byWidgetPredicate(
          (widget) => widget is GlassIconButton && widget.label == '离线缓存',
        ),
      );
      expect(download.onPressed, isNull);
      if (capture != null) await capture(tester, key, 'detail-polish-loading');
      pending.detailData.complete(novel);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('detail-cache-skeleton')),
        findsOneWidget,
      );
      pending.directory.complete(novel.chapters);
      // Readiness includes real filesystem writes. A fixed frame count gives
      // concurrent CI runs only 160ms of disk time, not a loading contract.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (find.byType(DetailSkeleton).evaluate().isNotEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        find.byType(DetailSkeleton),
        findsNothing,
        reason: 'The completed directory must replace its loading skeleton.',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(
        _phase(tester, 'detail-meta-reveal'),
        greaterThan(_phase(tester, 'detail-cache-reveal')),
      );
      expect(
        _phase(tester, 'detail-cache-reveal'),
        greaterThan(_phase(tester, 'detail-summary-reveal')),
      );
      await tester.pumpAndSettle();
      expect(find.text('缓存 0 / 3 章'), findsOneWidget);
      expect(find.text('开始阅读 · 第1章'), findsOneWidget);
      expect(find.byType(InlineSkeleton), findsNothing);
      if (capture != null) await capture(tester, key, 'detail-polish-ready');
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'detail resume label follows stable chapter IDs and clamps legacy indices',
    (tester) async {
      phoneViewport(tester);
      await tester.runAsync(
        () => state.savePosition(
          novel: novel,
          chapter: 1,
          offset: 0,
          maximum: 0,
          width: 412,
        ),
      );
      final inserted = novel.withChapters([
        const NovelChapter('新插入章节', '新正文。', id: 83099),
        ...novel.chapters,
      ]);
      await tester.pumpWidget(
        _app(
          DetailPage(
            novel: inserted,
            state: state,
            repository: const DemoNovelRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('继续阅读 · 第3章'), findsOneWidget);
      expect(find.text('上次阅读'), findsOneWidget);
      await tester.tap(find.byKey(_readKey));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).initialChapter,
        2,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      SharedPreferences.setMockInitialValues({
        'readerChromeVisible': true,
        'readerChromeHintSeen': true,
        'chapter_83': 99999,
        'reduceMotion': true,
      });
      final legacy = await LibraryState.load();
      addTearDown(legacy.dispose);
      await tester.pumpWidget(
        _app(
          DetailPage(
            novel: novel,
            state: legacy,
            repository: const DemoNovelRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('继续阅读 · 第3章'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'return from reader refreshes progress without replaying detail',
    (tester) async {
      phoneViewport(tester);
      await tester.pumpWidget(
        _app(
          DetailPage(
            novel: novel,
            state: state,
            repository: const DemoNovelRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('开始阅读 · 第1章'), findsOneWidget);
      await tester.tap(find.byKey(_readKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (widget) => widget is GlassIconButton && widget.label == '返回详情',
              ),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('继续阅读 · 第2章'), findsOneWidget);
      expect(find.text('上次阅读'), findsOneWidget);
      expect(_phase(tester, 'detail-summary-reveal'), 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty or failed detail never offers a misleading continue action',
    (tester) async {
      phoneViewport(tester);
      final repository = OfflineNovelRepository(
        remote: const DemoNovelRepository(),
        cache: cache,
      );
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        _app(
          DetailPage(
            novel: novel.withChapters(const []),
            state: state,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无可读章节'), findsOneWidget);
      expect(find.text('暂无章节缓存'), findsOneWidget);
      expect(find.textContaining('缓存 0 / 0'), findsNothing);
      expect(
        tester.widget<GlassPillButton>(find.byKey(_readKey)).onPressed,
        isNull,
      );
      var retries = 0;
      await tester.pumpWidget(
        _app(
          DetailPage(
            novel: novel.withChapters(const []),
            state: state,
            repository: repository,
            loadError: StateError('fixture detail failure'),
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重试加载目录'), findsOneWidget);
      expect(find.byType(OfflineBookStatus), findsNothing);
      expect(find.textContaining('缓存 0 / 0'), findsNothing);
      await tester.tap(find.byKey(_readKey));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cache count uses current directory instead of removed old chapters',
    (tester) async {
      final repository = OfflineNovelRepository(
        remote: const DemoNovelRepository(),
        cache: cache,
      );
      addTearDown(repository.dispose);
      await tester.runAsync(() async {
        final epoch = cache.epochFor(novel.id);
        await cache.saveBook(novel, epoch: epoch);
        await cache.saveChapter(
          novel.id,
          novel.chapters[0].id,
          '已缓存正文。',
          epoch: epoch,
        );
      });
      final changed = novel.withChapters([
        novel.chapters[1],
        novel.chapters[2],
      ]);
      await tester.pumpWidget(
        _app(OfflineBookStatus(repository: repository, novel: changed)),
      );
      await tester.pumpAndSettle();
      expect(find.text('缓存 0 / 2 章'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
