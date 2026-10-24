import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/reader_panels.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/glass_dock.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'reader_modes_test.dart' show settleReader;
import 'support/visual_review.dart';

class _LoadingRepository extends DemoNovelRepository {
  final ready = Completer<Novel>();
  @override
  Future<Novel> detail(Novel novel) => ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  testWidgets('direct-entry loading follows vertical typography', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
      'reduceMotion': true,
    });
    final state = await LibraryState.load();
    addTearDown(state.dispose);
    await state.setReaderPreferences(
      const ReaderPreferences(mode: ReaderMode.vertical),
    );
    final repository = _LoadingRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: ReaderLoaderPage(
          novel: demoNovels.first,
          state: state,
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<ReaderSkeleton>(find.byType(ReaderSkeleton)).vertical,
      true,
    );
    repository.ready.complete(demoNovels.first);
    await settleReader(tester);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final (name, size, scale, brightness) in [
    ('phone', const Size(390, 844), 1.0, Brightness.light),
    ('compact-large-text', const Size(320, 700), 1.5, Brightness.dark),
    ('tablet', const Size(1280, 800), 1.0, Brightness.light),
  ]) {
    testWidgets('usage settings and three-action reader dock fit $name', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'readerChromeVisible': true,
        'readerChromeHintSeen': true,
        'reduceMotion': true,
      });
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final capture = GlobalKey();
      Widget app(Widget home) => RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: novelTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 28, bottom: 20),
              viewPadding: const EdgeInsets.only(top: 28, bottom: 20),
            ),
            child: child!,
          ),
          home: home,
        ),
      );
      await tester.pumpWidget(app(Scaffold(body: SettingsPage(state: state))));
      await tester.pumpAndSettle();
      expect(find.byType(AppGlassSwitch), findsNothing);
      expect(find.byType(AppGlassSlider), findsNothing);
      await captureReview(tester, capture, 'settings-overview-$name');
      await tester.tap(find.byKey(const ValueKey('settings-usage-entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-direct-reading')));
      await tester.pumpAndSettle();
      expect(state.directReading, true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-direct-reading-discovery')),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-direct-reading-discovery')),
      );
      await tester.pumpAndSettle();
      expect(state.directReadingPages, {
        ReadingEntry.shelf,
        ReadingEntry.local,
      });
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-combined-shelf')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-combined-shelf')));
      await tester.pumpAndSettle();
      expect(state.combinedShelf, true);
      final settingsScroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('settings-usage')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      settingsScroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureReview(tester, capture, 'usage-settings-$name');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      for (final (id, title) in [
        ('reading', '阅读与外观'),
        ('effects', '性能与动效'),
        ('data', '数据与存储'),
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey('settings-$id-entry')));
        await tester.tap(find.byKey(ValueKey('settings-$id-entry')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('settings-$id-page')), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(
          tester.getRect(find.byType(ArchiveRouteTitle)).center.dx,
          closeTo(size.width / 2, 1),
        );
        expect(tester.takeException(), isNull);
        await captureReview(tester, capture, 'settings-$id-$name');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      await state.setReaderPreferences(
        const ReaderPreferences(mode: ReaderMode.paged),
      );
      await tester.pumpWidget(
        app(
          ReaderPage(
            novel: demoNovels.first,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await settleReader(tester);
      final dock = tester.getRect(
        find.byKey(const ValueKey('reader-liquid-dock')),
      );
      expect(dock.left, greaterThanOrEqualTo(0));
      expect(dock.right, lessThanOrEqualTo(size.width));
      final catalogue = tester.getRect(
        find.byKey(const ValueKey('dock-tab-0')),
      );
      expect(dock.contains(catalogue.center), true);
      final middle = tester.getRect(find.byKey(const ValueKey('dock-tab-2')));
      expect(middle.center.dx, closeTo(dock.center.dx, 1));
      final details = tester.getRect(
        find.byKey(const ValueKey('reader-details-entry')),
      );
      expect(details.center.dy, lessThan(100));
      expect(
        tester
            .widget<GlassDock>(find.byKey(const ValueKey('reader-liquid-dock')))
            .items
            .length,
        5,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('reader-page-count'))).bottom,
        lessThan(dock.top),
      );
      expect(tester.takeException(), isNull);
      await captureReview(tester, capture, 'reader-details-dock-$name');
      await tester.tap(readerPanelControl('进入详情页'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureReview(tester, capture, 'reader-detail-tags-$name');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
