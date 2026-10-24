import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/glass_dock.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/pages.dart';

Future<LibraryState> mountApp(
  WidgetTester tester, {
  NovelRepository repository = const DemoNovelRepository(),
}) async {
  SharedPreferences.setMockInitialValues({
    'readerChromeVisible': true,
    'readerChromeHintSeen': true,
  });
  final state = await LibraryState.load();
  await tester.pumpWidget(NovelApp(state: state, repository: repository));
  await tester.pumpAndSettle();
  return state;
}

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is GlassIconButton && widget.label == label,
);

// Explicitly finish the paper flight before advancing the staggered reveal.
Future<void> finishDetailIntro(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  test(
    'scroll edge has a strictly decreasing radius and a clear lower edge',
    () {
      expect(ScrollEdgeProfile.sigma(0), 20);
      expect(ScrollEdgeProfile.sigma(1), 0);
      expect(ScrollEdgeProfile.sigma(-1), 20);
      expect(ScrollEdgeProfile.sigma(2), 0);
      expect(ScrollEdgeProfile.sigma(.5), 5);
      expect(ScrollEdgeProfile.sigma(.99), lessThan(.003));
      var previous = 21.0;
      for (var i = 0; i <= 100; i++) {
        final sigma = ScrollEdgeProfile.sigma(i / 100);
        expect(sigma, lessThan(previous));
        previous = sigma;
      }
    },
  );

  testWidgets('top controls keep their rect during pull-down and scrolling', (
    tester,
  ) async {
    final dpr = tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(top: 48 * dpr, bottom: 24 * dpr);
    addTearDown(tester.view.resetPadding);
    await mountApp(tester);
    final initial = tester.getRect(control('搜索'));
    expect(initial.top, greaterThanOrEqualTo(48));
    final list = find.byKey(const PageStorageKey('discover'));
    final gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveBy(const Offset(0, 420));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(control('搜索')), initial);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getRect(control('搜索')), initial);
    await tester.tap(
      find.descendant(of: control('搜索'), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expanded-search-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dock is one capsule without an inner lens or tappable overlay', (
    tester,
  ) async {
    await mountApp(tester);
    final selection = find.byKey(const ValueKey('dock-fluid-surface'));
    expect(tester.widget(selection), isA<LiquidGlass>());
    expect(find.byType(DockSelectionLens), findsNothing);
    expect(
      find.descendant(of: selection, matching: find.byType(LiquidGlass)),
      findsNothing,
    );
    final nav = find.byKey(const ValueKey('dock-tab-1'));
    final ink = find.ancestor(of: nav, matching: find.byType(InkWell));
    expect(
      ink.evaluate().any(
        (element) => (element.widget as InkWell).onTap != null,
      ),
      isFalse,
    );
    await tester.tap(nav);
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.descendant(of: selection, matching: find.byType(LiquidGlass)),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('rapid tabs preserve the discovery viewport and settle once', (
    tester,
  ) async {
    await mountApp(tester);
    final list = find.byKey(const PageStorageKey('discover'));
    await tester.drag(list, const Offset(0, -420));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    final offset = scroll.position.pixels;
    expect(offset, greaterThan(0));
    for (final index in [1, 2, 1, 0]) {
      await tester.tap(find.byKey(ValueKey('dock-tab-$index')));
      await tester.pump(const Duration(milliseconds: 55));
    }
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, closeTo(offset, .01));
    expect(find.text('轻小说文库'), findsOneWidget);
    expect(find.text('书架还空着'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tab transitions keep a single stationary header outside page opacity',
    (tester) async {
      await mountApp(tester);
      final header = find.byType(FrostedHeader);
      final element = tester.element(header);
      final rect = tester.getRect(header);
      for (final index in [1, 2, 0]) {
        await tester.tap(find.byKey(ValueKey('dock-tab-$index')));
        await tester.pump(const Duration(milliseconds: 35));
        expect(header, findsOneWidget);
        expect(identical(tester.element(header), element), isTrue);
        expect(tester.getRect(header), rect);
        expect(
          find.ancestor(of: header, matching: find.byType(Opacity)),
          findsNothing,
        );
        expect(
          find.ancestor(of: header, matching: find.byType(Transform)),
          findsNothing,
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reader has a compact fluid dock, a bottom underlay and chapter boundaries',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'readerChromeVisible': true,
        'readerChromeHintSeen': true,
      });
      final state = await LibraryState.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderPage(
            novel: demoNovels.first,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dock = find.byKey(const ValueKey('reader-liquid-dock'));
      expect(tester.getSize(dock).width, closeTo(5 * 184 / 3 + 12, .01));
      expect(tester.getSize(dock).height, 54);
      expect(
        find.byKey(const ValueKey('reader-chrome-edge-blur')),
        findsOneWidget,
      );
      expect(tester.widget<GlassDock>(dock).items.first.label, '目录');
      await tester.tap(find.text('上一章'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 章'), findsWidgets);
      final surface = find.byKey(const ValueKey('dock-fluid-surface'));
      final rest = tester.getRect(surface);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('dock-tab-2'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.widget<LiquidGlass>(surface).activation, greaterThan(.9));
      await gesture.moveBy(
        const Offset(-75, 0),
        timeStamp: const Duration(milliseconds: 150),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(surface), rest);
      expect(find.text('第 1 章'), findsWidgets);
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 章'), findsWidgets);
      expect(tester.widget<GlassDock>(dock).items.first.enabled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dock responds on pointer-down, previews a drag and commits on up',
    (tester) async {
      await mountApp(tester);
      final lens = find.byKey(const ValueKey('dock-fluid-surface'));
      final rest = tester.getRect(lens);
      final first = tester.getCenter(find.byKey(const ValueKey('dock-tab-0')));
      final middle = tester.getCenter(find.byKey(const ValueKey('dock-tab-1')));
      final last = tester.getCenter(find.byKey(const ValueKey('dock-tab-3')));
      final gesture = await tester.startGesture(first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(lens).width, greaterThan(rest.width));
      expect(tester.getRect(lens).height, greaterThan(rest.height));
      expect(
        tester.widget<LiquidGlass>(lens).activation,
        greaterThan(.9),
        reason:
            'Contact must activate a visible meniscus, not only move geometry.',
      );
      await gesture.moveTo(last, timeStamp: const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 65));
      final rightTouch = tester.widget<LiquidGlass>(lens).touchPosition;
      expect(rightTouch, greaterThan(.8));
      expect(find.text('轻小说文库'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-settings')), findsNothing);
      await gesture.moveTo(
        middle,
        timeStamp: const Duration(milliseconds: 420),
      );
      await tester.pump(const Duration(milliseconds: 65));
      expect(
        tester.widget<LiquidGlass>(lens).touchPosition,
        lessThan(rightTouch),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('书架还空着'), findsOneWidget);
      expect(tester.getRect(lens).height, closeTo(rest.height, .01));
      expect(tester.getRect(lens).width, closeTo(rest.width, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled dock drag restores the whole capsule and selection', (
    tester,
  ) async {
    await mountApp(tester);
    final lens = find.byKey(const ValueKey('dock-fluid-surface'));
    final rest = tester.getRect(lens);
    final dock = tester.getRect(find.byKey(const ValueKey('liquid-dock')));
    final gesture = await tester.startGesture(rest.center);
    await tester.pump();
    await gesture.moveTo(Offset(dock.right + 100, rest.center.dy));
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getRect(lens).right, lessThanOrEqualTo(dock.right + 12));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(lens).left, closeTo(rest.left, .01));
    expect(tester.getRect(lens).size, rest.size);
    expect(find.text('轻小说文库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion dock still tracks a drag without deformation', (
    tester,
  ) async {
    final state = await mountApp(tester);
    await state.setReduceMotion(true);
    await tester.pumpAndSettle();
    final lens = find.byKey(const ValueKey('dock-fluid-surface'));
    final rest = tester.getRect(lens);
    final gesture = await tester.startGesture(rest.center);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(lens), rest);
    expect(tester.widget<LiquidGlass>(lens).activation, 0);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('dock-tab-3'))),
      timeStamp: const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(tester.getRect(lens).size, rest.size);
    await gesture.up(timeStamp: const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-settings')), findsOneWidget);
  });

  testWidgets('dock has one soft transmitting surface, without a second tint', (
    tester,
  ) async {
    await mountApp(tester);
    final surface = find.byKey(const ValueKey('dock-fluid-surface'));
    final glass = tester.widget<LiquidGlass>(surface);
    expect(find.byType(DockSelectionLens), findsNothing);
    expect(glass.blur, isNull);
    expect(glass.tintOpacity, isNull);
    expect(glass.elevated, isFalse);
  });

  testWidgets('dock has a Gallery-sized capsule with usable touch targets', (
    tester,
  ) async {
    await mountApp(tester);
    final dock = tester.getRect(find.byKey(const ValueKey('liquid-dock')));
    expect(dock.size.height, 54);
    expect(dock.size.width, closeTo(257.333, .01));
    expect(dock.center.dx, 400);
    for (var index = 0; index < 4; index++) {
      final target = tester.getRect(find.byKey(ValueKey('dock-tab-$index')));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
      expect(target.left, greaterThanOrEqualTo(dock.left));
      expect(target.right, lessThanOrEqualTo(dock.right));
    }
  });

  testWidgets('rapid back-and-forth motion deforms without a long press', (
    tester,
  ) async {
    await mountApp(tester);
    final surface = find.byKey(const ValueKey('dock-fluid-surface'));
    final rest = tester.getRect(surface);
    final first = tester.getCenter(find.byKey(const ValueKey('dock-tab-0')));
    final last = tester.getCenter(find.byKey(const ValueKey('dock-tab-3')));
    final gesture = await tester.startGesture(first);
    await tester.pump();
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(
        Offset.lerp(first, last, i / 12)!,
        timeStamp: Duration(milliseconds: i * 8),
      );
      await tester.pump(const Duration(milliseconds: 8));
    }
    final forward = tester.getRect(surface);
    final rightTouch = tester.widget<LiquidGlass>(surface).touchPosition;
    expect(forward.width, greaterThan(rest.width));
    expect(forward.center.dx, greaterThan(rest.center.dx));
    expect(rightTouch, greaterThan(.78));
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(
        Offset.lerp(last, first, i / 12)!,
        timeStamp: Duration(milliseconds: 96 + i * 8),
      );
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(tester.getRect(surface).center.dx, lessThan(rest.center.dx));
    expect(tester.widget<LiquidGlass>(surface).touchPosition, lessThan(.23));
    expect(find.text('轻小说文库'), findsOneWidget);
    await gesture.up(timeStamp: const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(tester.getRect(surface), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail uses a visible Cupertino push and interactive edge return',
    (tester) async {
      await mountApp(tester);
      await tester.tap(find.text(demoNovels.first.title).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final route = ModalRoute.of(
        tester.element(find.byType(DetailLoaderPage)),
      )!;
      expect(route, isA<CupertinoPageRoute>());
      expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
      await finishDetailIntro(tester);
      await tester.dragFrom(const Offset(3, 350), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(find.byType(DetailLoaderPage), findsNothing);
      expect(find.text('轻小说文库'), findsOneWidget);
    },
  );

  testWidgets(
    'cover is one shared flight and survives asynchronous detail loading',
    (tester) async {
      final repository = _DelayedDetailRepository();
      await mountApp(tester, repository: repository);
      final source = find.byWidgetPredicate(
        (widget) =>
            widget is NovelCover &&
            widget.novel.id == demoNovels.first.id &&
            widget.heroTag != null,
      );
      final sourceRect = tester.getRect(source);
      final tag = tester.widget<NovelCover>(source).heroTag;
      await tester.tap(find.text(demoNovels.first.title).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final flight = find.byKey(
        ValueKey('cover-flight-${demoNovels.first.id}'),
      );
      expect(flight, findsOneWidget);
      final firstRect = tester.getRect(flight);
      expect(firstRect.width, inInclusiveRange(sourceRect.width - 1, 119));
      final target = find.descendant(
        of: find.byType(DetailLoaderPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == tag,
        ),
      );
      expect(target, findsOneWidget);
      final targetElement = tester.element(target);
      expect(
        tester.widget<DetailPage>(find.byType(DetailPage)).isLoading,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(flight), isNot(firstRect));
      repository.detailResult.complete(demoNovels.first);
      await tester.pump();
      repository.chapterResult.complete(demoNovels.first.chapters);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(tester.element(target), targetElement), isTrue);
      expect(
        tester.widget<DetailPage>(find.byType(DetailPage)).isLoading,
        isFalse,
      );
      expect(flight, findsOneWidget);
      // Original and destination are placeholders, only one cover is painted.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 118 &&
              widget.constraints?.maxHeight == 166,
        ),
        findsOneWidget,
      );
      await finishDetailIntro(tester);
      expect(flight, findsNothing);
      expect(
        tester.getSize(
          find.descendant(
            of: find.byType(DetailPage),
            matching: find.byType(NovelCover),
          ),
        ),
        const Size(118, 166),
      );
      await tester.tap(
        find
            .descendant(of: control('返回'), matching: find.byType(InkWell))
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(flight, findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(DetailLoaderPage), findsNothing);
      expect(tester.getRect(source), sourceRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cover tags stay scoped when the same book appears in shelf and discovery',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = await mountApp(tester);
      await state.toggleShelf(demoNovels.first.id);
      await tester.tap(find.byKey(const ValueKey('dock-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('archive-shelf-open')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byKey(ValueKey('cover-flight-${demoNovels.first.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finishDetailIntro(tester);
      expect(find.byKey(const ValueKey('detail-read-button')), findsOneWidget);
    },
  );

  testWidgets('reduce motion disables route and tab movement', (tester) async {
    final state = await mountApp(tester);
    await state.setReduceMotion(true);
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsNothing);
    await tester.tap(find.text(demoNovels.first.title).last);
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(DetailLoaderPage)))!;
    expect(route.transitionDuration, Duration.zero);
    await tester.tap(
      find.descendant(of: control('返回'), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dock-tab-3')));
    await tester.pump();
    expect(find.byKey(const ValueKey('my-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long chapters only lay out nearby paragraphs', (tester) async {
    SharedPreferences.setMockInitialValues({
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
    });
    final state = await LibraryState.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        scrollBehavior: const NovelScrollBehavior(),
        home: ReaderPage(
          novel: demoNovels.first,
          state: state,
          repository: const _LongTextRepository(),
          initialChapter: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraphs = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('paragraph-'),
    );
    expect(paragraphs.evaluate().length, inInclusiveRange(1, 25));
    expect(find.byKey(const ValueKey('paragraph-900')), findsNothing);
    await tester.tap(find.text('下一章'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LongTextRepository extends DemoNovelRepository {
  const _LongTextRepository();

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) async =>
      List.generate(
        1000,
        (index) => '性能段落 $index：正文采用按需构建，不一次排版整章。',
      ).join('\n\n');
}

class _DelayedDetailRepository extends DemoNovelRepository {
  final detailResult = Completer<Novel>();
  final chapterResult = Completer<List<NovelChapter>>();

  @override
  Future<Novel> detail(Novel novel) => detailResult.future;

  @override
  Future<List<NovelChapter>> chapters(int id) => chapterResult.future;
}
