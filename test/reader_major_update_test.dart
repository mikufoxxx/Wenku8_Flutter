import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_backup.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_catalogue.dart';
import 'package:wenku8_flutter/reader_chrome.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_tools.dart';

const book = Novel(
  id: 567,
  title: '分卷目录',
  author: '测试',
  genre: '',
  summary: '',
  colors: [Colors.black, Colors.grey],
  chapters: [
    NovelChapter('序章', '卷一正文。', id: 101, volumeId: 10, volumeTitle: '第一卷 春'),
    NovelChapter('终章', '卷一结尾。', id: 102, volumeId: 10, volumeTitle: '第一卷 春'),
    NovelChapter('序章', '卷二正文。', id: 201, volumeId: 20, volumeTitle: '第二卷 夏'),
  ],
);
Future<LibraryState> state() async {
  SharedPreferences.setMockInitialValues({
    'readerChromeVisible': true,
    'readerChromeHintSeen': true,
    'reduceMotion': true,
  });
  return LibraryState.load();
}

Widget app(Widget child) =>
    MaterialApp(theme: novelTheme(Brightness.light), home: child);
void main() {
  test(
    'reader preferences and layout fingerprint round trip through safe backup',
    () async {
      final first = await state();
      addTearDown(first.dispose);
      await first.setReaderPreferences(
        const ReaderPreferences(
          paper: ReaderPaper.sage,
          margin: 38,
          paragraphGap: 18,
          indent: true,
          justify: true,
          tapPaging: true,
          tapBothSidesNext: true,
          volumePaging: true,
          autoScrollSpeed: 32,
          brightness: .6,
        ),
      );
      final backup = await first.createBackup();
      final prefs = ReaderPreferences.fromRecord(
        backup.records['readerPreferences'],
      );
      expect(prefs.margin, 38);
      expect(prefs.paper, ReaderPaper.sage);
      expect(prefs.volumePaging, isTrue);
      expect(prefs.tapBothSidesNext, isTrue);
      expect(prefs.layoutKey, isNotEmpty);
      final second = await state();
      addTearDown(second.dispose);
      await second.restoreBackup(backup, importPreferences: true);
      expect(
        second.readerPreferences.toJson(),
        first.readerPreferences.toJson(),
      );
      final bad = jsonDecode(await backup.encode()) as Map<String, dynamic>;
      (bad['records'] as Map)['readerPreferences'] = '{"margin":10000000}';
      await expectLater(
        LibraryBackup.parse(jsonEncode(bad)),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'detail volumes expand without changing the chosen chapter index',
    (tester) async {
      final library = await state();
      addTearDown(library.dispose);
      await tester.pumpWidget(
        app(
          DetailPage(
            novel: book,
            state: library,
            repository: const DemoNovelRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第一卷 春'), findsOneWidget);
      expect(find.text('终章'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('第二卷 夏'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('detail-scroll-567')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('第二卷 夏'));
      await tester.tap(find.text('第二卷 夏'));
      await tester.pumpAndSettle();
      expect(find.text('序章'), findsNWidgets(2));
      await Scrollable.ensureVisible(
        tester.element(find.text('序章').last),
        alignment: .35,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('序章').last);
      await tester.pumpAndSettle();
      final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
      expect(reader.initialChapter, 2);
    },
  );
  testWidgets(
    'refreshed volume metadata opens the current volume after cached loading',
    (tester) async {
      final library = await state();
      addTearDown(library.dispose);
      Widget detail({required bool loaded}) => app(
        DetailPage(
          novel: loaded
              ? book
              : book.withChapters([const NovelChapter('旧目录', '')]),
          state: library,
          repository: const DemoNovelRepository(),
          isLoading: !loaded,
        ),
      );
      await tester.pumpWidget(detail(loaded: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(detail(loaded: true));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('第一卷 春'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('detail-scroll-567')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('终章'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'live volume refresh reconciles cached keys but preserves manual collapse',
    (tester) async {
      final library = await state();
      addTearDown(library.dispose);
      Widget detail({required bool fresh}) => app(
        DetailPage(
          novel: fresh
              ? book
              : book.withChapters([const NovelChapter('旧目录', '')]),
          state: library,
          repository: const DemoNovelRepository(),
          fromCache: !fresh,
        ),
      );
      await tester.pumpWidget(detail(fresh: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(detail(fresh: true));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('第一卷 春'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('detail-scroll-567')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('终章'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('第一卷 春')),
        alignment: .45,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一卷 春'));
      await tester.pumpAndSettle();
      expect(find.text('终章'), findsNothing);
      await tester.pumpWidget(detail(fresh: true));
      await tester.pumpAndSettle();
      expect(find.text('终章'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reader catalogue opens current volume and searches across collapsed volumes',
    (tester) async {
      await tester.pumpWidget(
        app(Scaffold(body: ReaderCatalogue(novel: book, currentChapter: 2))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-chapter-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-chapter-1')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('reader-chapter-search')),
        '终章',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-chapter-1')), findsOneWidget);
      expect(find.text('第一卷 春'), findsOneWidget);
    },
  );
  testWidgets(
    'focus mode has no active edge filter and controls return together',
    (tester) async {
      final library = await state();
      addTearDown(library.dispose);
      await tester.pumpWidget(
        app(
          ReaderPage(
            novel: demoNovels.first,
            state: library,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderEdgeBlur), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reader-content-tap')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderEdgeBlur), findsNothing);
      expect(find.byKey(const ValueKey('reader-liquid-dock')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reader-content-tap')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderEdgeBlur), findsOneWidget);
      expect(find.byKey(const ValueKey('reader-liquid-dock')), findsOneWidget);
    },
  );
  testWidgets(
    'paper changes keep system bars and archive labels readable in dark appearance',
    (tester) async {
      final library = await state();
      addTearDown(library.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.dark),
          home: ReaderPage(
            novel: book,
            state: library,
            repository: const DemoNovelRepository(),
            initialChapter: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      SystemUiOverlayStyle barStyle() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.descendant(
              of: find.byKey(const ValueKey('reader-article-boundary')),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            ),
          )
          .value;
      BuildContext titleContext() => tester.element(
        find.descendant(
          of: find.byKey(const ValueKey('reader-chrome-header')),
          matching: find.text(book.chapters.first.title),
        ),
      );
      expect(barStyle().statusBarIconBrightness, Brightness.light);
      expect(Theme.of(titleContext()).brightness, Brightness.dark);
      await library.setReaderPreferences(
        const ReaderPreferences(paper: ReaderPaper.parchment),
      );
      await tester.pumpAndSettle();
      expect(barStyle().statusBarIconBrightness, Brightness.dark);
      expect(Theme.of(titleContext()).brightness, Brightness.light);
      expect(
        DefaultTextStyle.of(titleContext()).style.color!.computeLuminance(),
        lessThan(.2),
      );
      final label = tester.widget<Text>(find.text('CH.001 / TEXT'));
      expect(
        label.style!.color,
        library.readerPreferences.foreground(true).withValues(alpha: .65),
      );
      await library.setReaderPreferences(
        const ReaderPreferences(paper: ReaderPaper.night),
      );
      await tester.pumpAndSettle();
      expect(barStyle().statusBarIconBrightness, Brightness.light);
      expect(Theme.of(titleContext()).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('typography previews do not rebuild reader controls', (
    tester,
  ) async {
    final library = await state();
    addTearDown(library.dispose);
    await tester.pumpWidget(
      app(
        ReaderPage(
          novel: book,
          state: library,
          repository: const DemoNovelRepository(),
          initialChapter: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = tester.widget(
      find.byKey(const ValueKey('reader-chrome-header')),
    );
    await library.setFontSize(23, persist: false);
    await library.setLineHeight(1.9, persist: false);
    await tester.pumpAndSettle();
    expect(
      tester.widget(find.byKey(const ValueKey('reader-chrome-header'))),
      same(header),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'advanced reader tools expose all new settings and auto-scroll action',
    (tester) async {
      final library = await state();
      addTearDown(library.dispose);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SizedBox(
              height: 700,
              child: ReaderTools(
                novel: demoNovels.first,
                state: library,
                position: const ReadingPosition(
                  chapter: 0,
                  chapterId: 0,
                  offset: 0,
                  fraction: 0,
                  fontSize: 19,
                  width: 400,
                  updatedAt: 1,
                ),
                onAddBookmark: () async => null,
                onFontSize: (_) {},
                onLineHeight: (_) {},
                onReset: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      expect(find.text('阅读配色'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('reader-paper-parchment')),
      );
      await tester.tap(find.byKey(const ValueKey('reader-paper-parchment')));
      await tester.pumpAndSettle();
      expect(library.readerPreferences.paper, ReaderPaper.parchment);
      await tester.tap(find.text('翻页'));
      await tester.pumpAndSettle();
      expect(find.text('分区点按翻页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reader-auto-scroll-start')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
