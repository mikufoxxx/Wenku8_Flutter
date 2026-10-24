import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';

Finder readerPanelControl(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w is GlassIconButton && w.label == label,
      ),
      matching: find.byType(InkWell),
    )
    .first;

Future<void> openReaderPanel(WidgetTester tester, {String tab = '排版'}) async {
  if (tab == '听书') {
    await tester.tap(find.text('听书').first);
    await tester.pumpAndSettle();
    return;
  }
  if (tab == '书签') {
    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    return;
  }
  final mapped = switch (tab) {
    '操作' => '翻页',
    _ => tab,
  };
  await tester.tap(readerPanelControl('阅读设置'));
  await tester.pumpAndSettle();
  if (mapped != '排版') {
    await tester.tap(find.text(mapped));
    await tester.pumpAndSettle();
  }
}

Future<void> openReaderChapterProgress(WidgetTester tester) async {
  await tester.tap(find.text('目录'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('reader-progress-slider')), findsOneWidget);
}
