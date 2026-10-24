import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/pages.dart';

void main() {
  test(
    'peel moves down the cover and contact sweeps bottom-left to top-right',
    () {
      const lifting = PaperFlightPose(.10);
      expect(lifting.depthAt(0), greaterThan(0));
      expect(lifting.depthAt(1), 0);
      const traveling = PaperFlightPose(.5);
      for (final row in [0.0, .25, .5, .75, 1.0]) {
        expect(traveling.depthAt(row), greaterThan(0));
      }
      const landing = PaperFlightPose(.92);
      expect(landing.depthAt(1), 0);
      expect(landing.depthAt(0), greaterThan(0));
      expect(landing.lift, 0);
      expect(landing.roll, 0);
      expect(lifting.lift, greaterThan(0));
      for (final endpoint in [0.0, 1.0]) {
        for (var row = 0.0; row <= 1; row += .05) {
          expect(PaperFlightPose(endpoint).depthAt(row), 0);
        }
      }
    },
  );

  test('diagonal contact does not flatten an entire row at once', () {
    const firstContact = PaperFlightPose(.78);
    expect(firstContact.depthAt(1, column: 0), 0);
    expect(firstContact.depthAt(1, column: 1), greaterThan(0));
    expect(firstContact.depthAt(0, column: 0), greaterThan(0));
    const nearEnd = PaperFlightPose(.93);
    expect(nearEnd.depthAt(1, column: 1), 0);
    expect(nearEnd.depthAt(0, column: 0), 0);
    expect(nearEnd.depthAt(0, column: 1), greaterThan(0));
    for (final end in [0.0, 1.0]) {
      for (final row in [0.0, .25, .5, .75, 1.0]) {
        for (final column in [0.0, .25, .5, .75, 1.0]) {
          expect(PaperFlightPose(end).depthAt(row, column: column), 0);
        }
      }
    }
  });

  test(
    'flight starts by peeling, reaches target before contact, reverses exactly',
    () {
      const source = Rect.fromLTWH(24, 360, 56, 76);
      const target = Rect.fromLTWH(22, 104, 118, 166);
      final forward = PaperCoverRectTween(
        begin: source,
        end: target,
        returning: false,
      );
      final backward = PaperCoverRectTween(
        begin: target,
        end: source,
        returning: true,
      );
      expect(forward.lerp(0), source);
      expect(forward.lerp(.10), source);
      expect(forward.lerp(.82), target);
      expect(const PaperFlightPose(.82).depthAt(0), greaterThan(0));
      expect(forward.lerp(1), target);
      for (var index = 0; index <= 100; index++) {
        final p = index / 100;
        final a = forward.lerp(p);
        final b = backward.lerp(1 - p);
        expect(a.left, closeTo(b.left, .00001));
        expect(a.top, closeTo(b.top, .00001));
        expect(a.width, closeTo(b.width, .00001));
        expect(a.height, closeTo(b.height, .00001));
        expect(a.isFinite, isTrue);
        expect(a.width, inInclusiveRange(56, 118));
      }
    },
  );

  test('Hero easing is removed and contact keeps a full 420 ms window', () {
    for (var i = 0; i <= 100; i++) {
      final p = i / 100;
      expect(
        PaperFlightPose.heroTimeline(Curves.fastOutSlowIn.transform(p)),
        closeTo(p, .002),
      );
    }
    expect(NovelMotion.coverFlight.inMilliseconds * .42, closeTo(235.2, .01));
    expect(
      PaperCoverRectTween(
        begin: const Rect.fromLTWH(24, 360, 56, 76),
        end: const Rect.fromLTWH(22, 104, 118, 166),
        returning: false,
        heroCurve: true,
      ).lerp(Curves.fastOutSlowIn.transform(.65)),
      const Rect.fromLTWH(22, 104, 118, 166),
    );
    expect(const PaperFlightPose(.76).depthAt(1), 0);
    expect(const PaperFlightPose(.76).depthAt(.5), greaterThan(0));
    expect(const PaperFlightPose(.90).depthAt(0), greaterThan(0));
  });

  testWidgets('120 Hz ticks paint one mesh without rebuilding its face', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 32, 48),
      Paint()..color = Colors.blueGrey,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(32, 48);
    picture.dispose();
    final clock = AnimationController(
      vsync: tester,
      duration: NovelMotion.coverFlight,
    );
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 118,
            height: 166,
            child: PaperCoverBend(
              animation: clock,
              image: image,
              imageIsFitted: true,
              faceSize: const Size(118, 166),
              child: Builder(
                builder: (_) {
                  builds++;
                  return const ColoredBox(color: Colors.blueGrey);
                },
              ),
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<PaperCoverRender>(
      find.byType(PaperCoverBend),
    );
    final initial = render.debugMeshDraws;
    clock.forward();
    await tester.pump();
    final slice = Duration(
      microseconds: NovelMotion.coverFlight.inMicroseconds ~/ 120,
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(slice);
    }
    expect(render.debugMeshDraws - initial, inInclusiveRange(120, 121));
    expect(render.debugChildPaints, 0);
    expect(builds, 1);
    await tester.pump(NovelMotion.coverFlight);
    expect(clock.value, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    clock.dispose();
    image.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'only the overlay bends; landed cover is flat and stops painting',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      await tester.pumpWidget(
        NovelApp(state: state, repository: const DemoNovelRepository()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(demoNovels.first.title).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump();
      expect(find.byType(PaperCoverFlight), findsOneWidget);
      final bend = tester.renderObject<PaperCoverRender>(
        find.byType(PaperCoverBend),
      );
      expect(bend.config.image, isNotNull);
      expect(bend.debugMeshDraws, greaterThan(0));
      expect(bend.debugChildPaints, lessThanOrEqualTo(1));
      expect(bend.progress, inExclusiveRange(0, 1));
      expect(
        bend.progress,
        closeTo(220 / NovelMotion.coverFlight.inMilliseconds, .02),
      );
      await tester.pumpAndSettle();
      final landed = find.descendant(
        of: find.byType(DetailPage),
        matching: find.byType(NovelCover),
      );
      final rect = tester.getRect(landed);
      expect(find.byType(PaperCoverFlight), findsNothing);
      expect(find.byType(PaperCoverBend), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getRect(landed), rect);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('back during a paper flight cleans up its single overlay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = await LibraryState.load();
    await tester.pumpWidget(
      NovelApp(state: state, repository: const DemoNovelRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(demoNovels.first.title).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    Navigator.of(tester.element(find.byType(DetailPage))).pop();
    await tester.pump();
    expect(find.byType(PaperCoverFlight), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(PaperCoverFlight), findsNothing);
    expect(find.byType(DetailPage), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
