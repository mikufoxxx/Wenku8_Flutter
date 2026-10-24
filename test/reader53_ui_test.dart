import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_interactions.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/cloud_library_page.dart';
import 'package:wenku8_flutter/cloud_sources.dart';
import 'package:wenku8_flutter/discovery_filters.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/listening/controller.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/listening/widgets.dart';
import 'package:wenku8_flutter/local_platform.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_catalogue.dart';
import 'reader53_selection_test.dart' show selectionBook;
import 'reader_modes_test.dart' show settleReader;
import 'support/listening_fixture.dart';
import 'support/visual_review.dart';
import 'support/background_fixture.dart';

Finder control(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w is GlassIconButton && w.label == label,
      ),
      matching: find.byType(InkWell),
    )
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'reduceMotion': true,
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
    }),
  );
  void phone(WidgetTester tester, {double scale = 1}) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    tester.view.viewPadding = tester.view.padding;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget app(
    Widget home, {
    GlobalKey? boundary,
    ListeningController? listening,
  }) => RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: novelTheme(Brightness.light),
      builder: (context, child) =>
          ListeningScope(controller: listening, child: child!),
      home: home,
    ),
  );

  testWidgets(
    'one reader settings entry owns four tabs and the bottom always opens the catalogue',
    (tester) async {
      phone(tester);
      final state = LibraryState(
            await SharedPreferences.getInstance(),
            backgrounds: EmptyReaderBackgrounds(),
          ),
          boundary = GlobalKey();
      addTearDown(state.dispose);
      await state.setDirectReading(true);
      final listening = ListeningController(
        repository: const DemoNovelRepository(),
        audio: FakeSpeechAudio(),
        store: ListeningStore(await SharedPreferences.getInstance()),
        outputFactory: (_) async => FakeListeningOutput(),
      );
      await tester.pumpWidget(
        app(
          ReaderPage(
            novel: selectionBook,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
            directEntry: true,
          ),
          boundary: boundary,
          listening: listening,
        ),
      );
      await settleReader(tester);
      expect(
        find.byKey(const ValueKey('reader-listening-entry')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reader-bookmarks-entry')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reader-details-entry')),
        findsOneWidget,
      );
      await tester.tap(control('阅读设置'));
      await tester.pumpAndSettle();
      for (final tab in ['外观', '排版', '翻页', '显示']) {
        expect(find.text(tab), findsWidgets);
      }
      expect(
        find.byKey(const ValueKey('reader-progress-slider')),
        findsNothing,
      );
      await captureReview(tester, boundary, 'unified-reader-settings');
      await tester.tap(control('关闭阅读设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('听书').first);
      await tester.pumpAndSettle();
      expect(find.byType(ListeningPanel), findsOneWidget);
      expect(find.text('听书'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is GlassIconButton && w.label == '关闭听书面板',
        ),
        findsOneWidget,
      );
      await captureReview(tester, boundary, 'embedded-listening');
      await tester.tap(control('关闭听书面板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('目录'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderCatalogue), findsOneWidget);
      expect(find.byType(DetailPage), findsNothing);
      expect(find.text('章节进度'), findsOneWidget);
      for (final label in ['回到章首', '跳至章末', '章内查找']) {
        expect(find.text(label), findsOneWidget);
      }
      await captureReview(tester, boundary, 'catalogue-chapter-progress');
      final slider = tester.widget<AppGlassSlider>(
        find.byKey(const ValueKey('reader-progress-slider')),
      );
      slider.onChangeStart!(slider.value);
      slider.onChanged!(.65);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GlassOverlaySurface>(find.byType(GlassOverlaySurface))
            .transparent,
        isTrue,
      );
      expect(find.text('回到章首').hitTestable(), findsNothing);
      slider.onChangeEnd!(.65);
      await settleReader(tester);
      expect(
        tester
            .widget<GlassOverlaySurface>(find.byType(GlassOverlaySurface))
            .transparent,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('reader-return-position')),
        findsNothing,
      );
      await tester.tap(control('关闭目录'));
      await tester.pumpAndSettle();
      await tester.tap(control('进入详情页'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final closing = listening.dispose();
      await tester.pump();
      await tester.runAsync(listeningMicrotasks);
      await tester.pump();
      await closing;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'status-bar preference persists and system broadcasts update only the top status line',
    (tester) async {
      phone(tester);
      final state = await LibraryState.load(),
          calls = <Map<Object?, Object?>>[],
          boundary = GlobalKey();
      addTearDown(state.dispose);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(LocalPlatform.readerControls, (
        call,
      ) async {
        if (call.method == 'apply') {
          calls.add(Map<Object?, Object?>.from(call.arguments as Map));
        }
        return null;
      });
      const statusChannel = MethodChannel('org.mewx.wenku8/reader_status');
      messenger.setMockMethodCallHandler(statusChannel, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(LocalPlatform.readerControls, null);
        messenger.setMockMethodCallHandler(statusChannel, null);
      });
      await tester.pumpWidget(
        app(
          ReaderPage(
            novel: selectionBook,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
          boundary: boundary,
        ),
      );
      await settleReader(tester);
      await state.setReaderPreferences(
        state.readerPreferences.copyWith(hideSystemStatus: true),
      );
      await settleReader(tester);
      expect(calls.last['hideStatusBar'], true);
      expect(
        (await LibraryState.load()).readerPreferences.hideSystemStatus,
        true,
      );
      final article = tester.widget(find.byKey(const ValueKey('paragraph-0')));
      ServicesBinding.instance.channelBuffers.push(
        'org.mewx.wenku8/reader_status',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'time': DateTime(2026, 10, 18, 9, 41).millisecondsSinceEpoch,
          'battery': 71,
          'charging': false,
        }),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('09:41'), findsOneWidget);
      expect(find.text('71%'), findsOneWidget);
      expect(
        tester.widget(find.byKey(const ValueKey('paragraph-0'))),
        same(article),
      );
      final footer = tester.getRect(
        find.byKey(const ValueKey('reader-system-footer')),
      );
      final dock = tester.getRect(
        find.byKey(const ValueKey('reader-liquid-dock')),
      );
      expect(footer.bottom, lessThan(dock.top));
      expect(footer.top, lessThan(40));
      await captureReview(tester, boundary, 'reader-top-system-status');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.last['hideStatusBar'], false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'language and appearance selectors align right and open anchored menus, not drawers',
    (tester) async {
      phone(tester);
      final state = await LibraryState.load(), boundary = GlobalKey();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        app(SettingsPage(state: state), boundary: boundary),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-reading-entry')));
      await tester.pumpAndSettle();
      expect(find.textContaining('App ·'), findsNothing);
      expect(find.textContaining('阅读器 ·'), findsNothing);
      for (final key in ['settings-appearance', 'settings-language']) {
        final row = find.byKey(ValueKey(key));
        final plate = find
            .descendant(of: row, matching: find.byType(LiquidGlass))
            .first;
        final anchor = tester.getRect(plate), rowBounds = tester.getRect(row);
        expect(anchor.right, closeTo(rowBounds.right, 1));
        await tester.tap(
          find.descendant(of: plate, matching: find.byType(InkWell)).first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(GlassMenuSurface), findsOneWidget);
        final popup = tester.getRect(find.byType(GlassMenuSurface));
        expect(popup.top, closeTo(anchor.top, 1));
        expect(popup.right, closeTo(anchor.right, 1));
        if (key == 'settings-language') {
          await captureReview(
            tester,
            boundary,
            'language-right-anchored-dropdown',
          );
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tag apply and clear appear before search and every tag', (
    tester,
  ) async {
    phone(tester, scale: 1.3);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: DiscoveryFilters(
            sort: NovelSort.lastUpdate,
            books: const [],
            selectedTags: const {'奇幻'},
            availableTags: ['奇幻', ...List.generate(100, (i) => '标签$i')],
          ),
        ),
        boundary: boundary,
      ),
    );
    await tester.pumpAndSettle();
    final apply = tester.getRect(
      find.byKey(const ValueKey('discover-tags-apply')),
    );
    final clear = tester.getRect(
      find.byKey(const ValueKey('discover-tags-clear')),
    );
    final query = tester.getRect(
      find.byKey(const ValueKey('discover-tag-input')),
    );
    expect(apply.bottom, lessThan(query.top));
    expect(clear.bottom, lessThan(query.top));
    expect(apply.bottom, lessThan(300));
    expect(apply.height, closeTo(clear.height, .01));
    await captureReview(tester, boundary, 'tag-actions-at-top');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cloud import uses the shared content panels and twenty-four dp gutters',
    (tester) async {
      phone(tester);
      final settings = CloudSourceSettings(), boundary = GlobalKey();
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        app(
          CloudLibraryPage(
            settings: settings,
            onImport: (_, _) async => selectionBook,
          ),
          boundary: boundary,
        ),
      );
      await tester.pumpAndSettle();
      for (final kind in CloudSourceKind.values) {
        final card = find.byKey(ValueKey('cloud-source-${kind.name}'));
        expect(tester.widget(card), isA<ContentPanel>());
        expect(tester.getRect(card).left, 24);
        expect(tester.getRect(card).right, 366);
      }
      await captureReview(tester, boundary, 'cloud-source-cards');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short notices auto-dismiss after two and a half seconds', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNovelFeedback(context, '已保存'),
            child: const Text('提示'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('提示'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已保存'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsNothing);
  });
}
