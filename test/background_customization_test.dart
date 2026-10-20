import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:wenku8_flutter/app_background.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/background_settings_page.dart';
import 'package:wenku8_flutter/book_documents.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/library_backup.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/reader_appearance.dart';
import 'package:wenku8_flutter/reader_background.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';

import 'reader_modes_test.dart' as reader;
import 'support/visual_review.dart';

class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences() : super.empty();
  bool fail = false;
  @override
  Future<bool> setValue(String type, String key, Object value) =>
      fail ? Future.value(false) : super.setValue(type, key, value);
}

class _Documents extends BookDocuments {
  _Documents(this.path);
  String? path;
  int releases = 0;
  @override
  Future<BookDocumentSelection?> pickBackgroundImage() async => path == null
      ? null
      : BookDocumentSelection(name: 'background.png', path: path);
  @override
  Future<void> releaseBooks(Iterable<BookDocumentSelection> books) async {
    releases++;
  }
}

Future<File> _picture(
  Directory root, {
  int width = 400,
  int height = 300,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xff86a8a0),
  );
  canvas.drawCircle(
    Offset(width * .7, height * .3),
    height * .18,
    Paint()..color = const Color(0xffeed6a1),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return await File(
      '${root.path}/original.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _io(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (until?.call() ?? (i > 5)) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  late Directory root;
  late ReaderBackgroundStore store;
  late LibraryState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'reduceMotion': true,
      'readerChromeVisible': true,
      'readerChromeHintSeen': true,
    });
    root = await Directory.systemTemp.createTemp('wenku-background-test-');
    store = ReaderBackgroundStore(directory: Directory('${root.path}/managed'));
    state = LibraryState(
      await SharedPreferences.getInstance(),
      backgrounds: store,
    );
  });
  tearDown(() async {
    state.dispose();
    await root.delete(recursive: true);
  });

  test(
    'home color persists, backs up, restores and stays independent of reader paper',
    () async {
      const color = Color(0xff152a35);
      var notifications = 0;
      state.applicationChanges.addListener(() => notifications++);
      await state.setHomeBackgroundColor(color);
      final prefs = await SharedPreferences.getInstance();
      final restarted = LibraryState(prefs, backgrounds: store);
      addTearDown(restarted.dispose);
      expect(restarted.homeBackgroundColor, color);
      final backup = await state.createBackup();
      expect(backup.records['homeBackground'], '#152A35');
      await state.setHomeBackgroundColor(null);
      expect(state.homeBackgroundColor, isNull);
      await state.restoreBackup(backup, importPreferences: true);
      expect(state.homeBackgroundColor, color);
      expect(notifications, greaterThanOrEqualTo(3));
      for (final brightness in Brightness.values) {
        final original = novelTheme(brightness);
        final custom = withAppBackground(original, color);
        expect(custom.scaffoldBackgroundColor, color);
        expect(custom.brightness, brightness);
        expect(custom.colorScheme.brightness, brightness);
        expect(custom.cupertinoOverrideTheme!.brightness, brightness);
        expect(
          custom.colorScheme.onSurface.computeLuminance(),
          greaterThan(.8),
        );
        final actual = readerTheme(custom, const ReaderPreferences());
        final expected = readerTheme(original, const ReaderPreferences());
        expect(
          actual.scaffoldBackgroundColor,
          expected.scaffoldBackgroundColor,
        );
        expect(actual.extension<AppBackground>(), isNull);
      }
    },
  );

  test(
    'light and dark backgrounds persist, restore and reset independently',
    () async {
      const light = Color(0xffe4ebdd);
      const dark = Color(0xff263442);
      await state.setHomeBackgroundColor(light);
      await state.setHomeBackgroundColor(dark, brightness: Brightness.dark);
      final restarted = LibraryState(await SharedPreferences.getInstance());
      addTearDown(restarted.dispose);
      expect(restarted.homeBackgroundFor(Brightness.light), light);
      expect(restarted.homeBackgroundFor(Brightness.dark), dark);
      final backup = await state.createBackup();
      expect(backup.records['homeBackgroundDark'], '#263442');
      await state.setHomeBackgroundColor(null);
      await state.setHomeBackgroundColor(null, brightness: Brightness.dark);
      await state.restoreBackup(backup, importPreferences: true);
      expect(state.homeBackgroundFor(Brightness.light), light);
      expect(state.homeBackgroundFor(Brightness.dark), dark);
      await state.setHomeBackgroundColor(null, brightness: Brightness.dark);
      expect(state.homeBackgroundFor(Brightness.light), light);
      expect(state.homeBackgroundFor(Brightness.dark), isNull);
      await expectLater(
        LibraryBackup.fromRecords({'homeBackgroundDark': '#invalid'}),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'custom backgrounds preserve manual and system appearance switching',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      const light = Color(0xffe4ebdd);
      const dark = Color(0xff263442);
      await tester.runAsync(() async {
        await state.setHomeBackgroundColor(light);
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: NovelApp(
            state: state,
            repository: const DemoNovelRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ThemeData current() => Theme.of(tester.element(find.byType(HomeShell)));
      expect(current().brightness, Brightness.light);
      expect(current().scaffoldBackgroundColor, light);
      await state.setTheme(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(current().brightness, Brightness.dark);
      expect(current().scaffoldBackgroundColor, ArchiveDesign.darkBackground);
      expect(
        SystemChrome.latestStyle!.statusBarIconBrightness,
        Brightness.light,
      );
      final saved = state.setHomeBackgroundColor(
        dark,
        brightness: Brightness.dark,
      );
      await _io(tester);
      await saved;
      expect(current().scaffoldBackgroundColor, dark);
      await captureReview(tester, boundary, 'home-background-dark-mode');
      await state.setTheme(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(current().brightness, Brightness.light);
      expect(current().scaffoldBackgroundColor, light);
      expect(
        SystemChrome.latestStyle!.statusBarIconBrightness,
        Brightness.dark,
      );
      await captureReview(tester, boundary, 'home-background-light-mode');
      await state.setTheme(ThemeMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(current().brightness, Brightness.dark);
      expect(current().scaffoldBackgroundColor, dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(current().brightness, Brightness.light);
      expect(current().scaffoldBackgroundColor, light);
    },
  );

  testWidgets(
    'background editor keeps separate drafts and saves only the selected mode',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.dark),
          home: HomeBackgroundPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('home-background-hex'));
      final save = find.byKey(const ValueKey('save-home-background'));
      final lightChip = find.byKey(const ValueKey('home-background-light'));
      final darkChip = find.byKey(const ValueKey('home-background-dark'));
      Future<void> editMode(Finder chip) async {
        await tester.scrollUntilVisible(
          chip,
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(chip), alignment: .25);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          field,
          250,
          scrollable: find.byType(Scrollable).first,
        );
      }

      Future<void> enter(String color) async {
        await tester.scrollUntilVisible(
          field,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(field, color);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      Future<void> saveColor() async {
        await tester.scrollUntilVisible(
          save,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(save);
        await _io(tester);
      }

      expect(tester.widget<ChoiceChip>(darkChip).selected, isTrue);
      await tester.scrollUntilVisible(
        field,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        backgroundHex(ArchiveDesign.darkBackground),
      );
      await enter('#263442');
      await editMode(lightChip);
      expect(
        tester.widget<TextField>(field).controller!.text,
        backgroundHex(ArchiveDesign.background),
      );
      await enter('#E4EBDD');
      await editMode(darkChip);
      expect(tester.widget<TextField>(field).controller!.text, '#263442');
      await saveColor();
      expect(state.homeBackgroundFor(Brightness.dark), const Color(0xff263442));
      expect(state.homeBackgroundFor(Brightness.light), isNull);
      await editMode(lightChip);
      expect(tester.widget<TextField>(field).controller!.text, '#E4EBDD');
      await saveColor();
      expect(
        state.homeBackgroundFor(Brightness.light),
        const Color(0xffe4ebdd),
      );
      await editMode(darkChip);
      final reset = find.byKey(const ValueKey('reset-home-background'));
      await tester.scrollUntilVisible(
        reset,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(reset);
      await _io(tester);
      expect(state.homeBackgroundFor(Brightness.dark), isNull);
      expect(
        state.homeBackgroundFor(Brightness.light),
        const Color(0xffe4ebdd),
      );
    },
  );

  test(
    'failed persistence does not publish a color and the next save can recover',
    () async {
      SharedPreferences.resetStatic();
      final storage = _FailingPreferences();
      SharedPreferencesStorePlatform.instance = storage;
      final library = LibraryState(await SharedPreferences.getInstance());
      addTearDown(library.dispose);
      storage.fail = true;
      await expectLater(
        library.setHomeBackgroundColor(Colors.blue),
        throwsA(isA<StateError>()),
      );
      expect(library.homeBackgroundColor, isNull);
      storage.fail = false;
      await library.setHomeBackgroundColor(Colors.green);
      expect(library.homeBackgroundColor?.toARGB32(), Colors.green.toARGB32());
    },
  );

  test(
    'old preferences migrate; unsafe paths and invalid controls are rejected',
    () async {
      expect(
        ReaderPreferences.fromJson({'paper': 'sage'}).backgroundImage,
        isNull,
      );
      final id = 'background_${'a' * 64}';
      final before = const ReaderPreferences(
        mode: ReaderMode.vertical,
        margin: 30,
      );
      final custom = before.copyWith(
        backgroundImage: id,
        backgroundFit: ReaderBackgroundFit.contain,
        backgroundOverlay: .42,
      );
      final restored = ReaderPreferences.fromJson(custom.toJson());
      expect(restored.backgroundImage, id);
      expect(restored.backgroundFit, ReaderBackgroundFit.contain);
      expect(restored.backgroundOverlay, .42);
      expect(restored.layoutKey, before.layoutKey);
      expect(
        custom.copyWith(clearBackgroundImage: true).backgroundImage,
        isNull,
      );
      for (final bad in [
        '../../original.png',
        'file:///private.png',
        '',
        'https://example.com/a.png',
      ]) {
        expect(
          () => ReaderPreferences.fromJson({'backgroundImage': bad}),
          throwsFormatException,
        );
        expect(await store.fileFor(bad), isNull);
      }
      for (final bad in [-.1, 1.1, double.nan]) {
        expect(
          () => ReaderPreferences.fromJson({'backgroundOverlay': bad}),
          throwsFormatException,
        );
      }
      await expectLater(
        LibraryBackup.fromRecords({'homeBackground': '#12345Z'}),
        throwsFormatException,
      );
      await state.setReaderPreferences(custom);
      final backup = await state.createBackup();
      expect(
        jsonDecode(
          backup.records['readerPreferences'] as String,
        )['backgroundImage'],
        id,
      );
    },
  );

  test(
    'image imports durably, bounds decoding and rejects corrupt input',
    () async {
      final original = await _picture(root, width: 4096, height: 2048);
      final id = await store.importFile(original.path);
      await original.delete();
      final restarted = ReaderBackgroundStore(
        directory: Directory('${root.path}/managed'),
      );
      final copy = (await restarted.fileFor(id))!;
      final codec = await ui.instantiateImageCodec(await copy.readAsBytes());
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (2048, 1024));
      frame.image.dispose();
      codec.dispose();
      final corrupt = await File(
        '${root.path}/broken.png',
      ).writeAsString('not an image');
      await expectLater(store.importFile(corrupt.path), throwsFormatException);
      expect(await copy.exists(), isTrue);
      await store.remove(id);
      expect(await restarted.fileFor(id), isNull);
    },
  );

  testWidgets('home color editor validates, saves and resets', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: novelTheme(Brightness.light),
          home: HomeBackgroundPage(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final palette = find.byKey(const ValueKey('home-color-palette'));
    await tester.ensureVisible(palette);
    await tester.pumpAndSettle();
    final rect = tester.getRect(palette);
    await tester.tapAt(rect.center);
    await tester.pump();
    var hexField = tester.widget<TextField>(
      find.byKey(const ValueKey('home-background-hex')),
    );
    final selected = HSVColor.fromColor(
      parseBackgroundHex(hexField.controller!.text)!,
    );
    expect(selected.saturation, closeTo(.5, .02));
    expect(selected.value, closeTo(.5, .02));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(rect.bottomRight + const Offset(20, 20));
    await gesture.up();
    await tester.pump();
    expect(hexField.controller!.text, '#000000');
    final hue = tester.widget<Slider>(
      find.byKey(const ValueKey('home-color-hue')),
    );
    hue.onChanged!(240);
    await tester.pump();
    await tester.tapAt(rect.topRight - const Offset(1, -1));
    await tester.pump();
    final blue = parseBackgroundHex(hexField.controller!.text)!;
    expect(blue.b, greaterThan(.98));
    expect(blue.r, lessThan(.02));
    expect(state.homeBackgroundColor, isNull);
    await captureReview(tester, boundary, 'home-color-palette');
    final field = find.byKey(const ValueKey('home-background-hex'));
    await tester.enterText(field, '#152A35');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('save-home-background'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _io(tester);
    expect(state.homeBackgroundColor, const Color(0xff152a35));
    await tester.ensureVisible(field);
    await tester.enterText(field, '#oops');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _io(tester);
    expect(find.text('请输入六位 HEX 色值，例如 #E4EBDD'), findsOneWidget);
    expect(state.homeBackgroundColor, const Color(0xff152a35));
    await tester.tap(find.byKey(const ValueKey('reset-home-background')));
    await tester.pumpAndSettle();
    expect(state.homeBackgroundColor, isNull);
    await tester.ensureVisible(field);
    await tester.enterText(field, '#DDE8EF');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await captureReview(tester, boundary, 'home-background-settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inset page backgrounds align with the full reader canvas without seams',
    (tester) async {
      final id = (await tester.runAsync(
        () async => store.importFile((await _picture(root)).path),
      ))!;
      final key = GlobalKey();
      final preferences = ReaderPreferences(
        backgroundImage: id,
        backgroundOverlay: .25,
        backgroundFit: ReaderBackgroundFit.fill,
      );
      Widget scene(bool inset) => MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 200,
              height: 300,
              child: ReaderBackgroundSurface(
                store: store,
                preferences: preferences,
                paper: Colors.white,
                child: Stack(
                  children: [
                    if (inset)
                      Positioned(
                        left: 20,
                        top: 65,
                        width: 160,
                        height: 150,
                        child: ReaderBackgroundSurface(
                          store: store,
                          preferences: preferences,
                          paper: Colors.white,
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<List<int>> pixels() async {
        final box =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = box.toImageSync();
        try {
          final data = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          return data!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }

      await tester.pumpWidget(scene(false));
      await _io(tester);
      final original = await pixels();
      await tester.pumpWidget(scene(true));
      await _io(tester);
      final composed = await pixels();
      expect(composed.length, original.length);
      expect(
        [
          for (var i = 0; i < original.length; i++)
            (original[i] - composed[i]).abs(),
        ].reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(1),
      );
    },
  );

  testWidgets('reader image selection can cancel, preview, persist and reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = await tester.runAsync(() => _picture(root));
    final documents = _Documents(null);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderBackgroundPage(state: state, documents: documents),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('choose-reader-background'));
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(state.readerPreferences.backgroundImage, isNull);
    documents.path = original!.path;
    await tester.tap(choose);
    await _io(tester, until: () => documents.releases == 1);
    expect(documents.releases, 1);
    expect(
      state.readerPreferences.backgroundImage,
      isNull,
      reason: 'Selecting only previews until saved.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('background-fit-contain')),
    );
    await tester.tap(find.byKey(const ValueKey('background-fit-contain')));
    final slider = find.byKey(const ValueKey('reader-background-overlay'));
    tester.widget<Slider>(slider).onChanged!(.35);
    await tester.pump();
    final save = find.byKey(const ValueKey('save-reader-background'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _io(tester);
    expect(state.readerPreferences.backgroundImage, isNotNull);
    expect(state.readerPreferences.backgroundFit, ReaderBackgroundFit.contain);
    expect(state.readerPreferences.backgroundOverlay, .35);
    final id = state.readerPreferences.backgroundImage!;
    await tester.runAsync(() => original.delete());
    expect(await tester.runAsync(() => store.fileFor(id)), isNotNull);
    await tester.ensureVisible(choose);
    await _io(tester);
    await captureReview(tester, boundary, 'reader-background-settings');
    final reset = find.byKey(const ValueKey('reset-reader-background'));
    await tester.scrollUntilVisible(
      reset,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reset);
    await _io(tester);
    expect(state.readerPreferences.backgroundImage, isNull);
    expect(await tester.runAsync(() => store.fileFor(id)), isNull);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ReaderMode.values) {
    testWidgets(
      '${mode.name} keeps image under text and changing it preserves the reading layout',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final id = (await tester.runAsync(
          () async => store.importFile((await _picture(root)).path),
        ))!;
        await tester.runAsync(
          () => state.setReaderPreferences(
            ReaderPreferences(mode: mode, backgroundImage: id),
          ),
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: reader.app(state)),
        );
        await reader.settleReader(tester);
        await _io(tester);
        expect(find.byType(Image), findsWidgets);
        final paged = mode.paginated
            ? tester
                  .widget<ReaderPagedView>(find.byType(ReaderPagedView))
                  .controller
            : null;
        final generation = paged?.debugLayoutGeneration;
        final changed = state.setReaderPreferences(
          state.readerPreferences.copyWith(
            backgroundOverlay: .25,
            backgroundFit: ReaderBackgroundFit.fill,
          ),
        );
        await _io(tester);
        await changed;
        await reader.settleReader(tester);
        if (paged != null) expect(paged.debugLayoutGeneration, generation);
        await captureReview(tester, boundary, 'reader-background-${mode.name}');
        await tester.runAsync(() => store.remove(id));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(reader.app(state));
        await reader.settleReader(tester);
        await _io(tester);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
