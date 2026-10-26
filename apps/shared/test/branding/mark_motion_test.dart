// Frames of the animated mark (splash), for a visual check.
// Skipped unless RIDE_BRAND_OUT points at an output directory.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

final out = Platform.environment['RIDE_BRAND_OUT'];

void main() {
  if (out == null) return;
  testWidgets('mark motion frames', (tester) async {
    tester.view.physicalSize = const Size(320, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: ColoredBox(color: Brand.charcoal, child: Center(child: RepaintBoundary(child: AavagamanMark(size: 256, animated: true)))),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 320));
      await expectLater(find.byType(RepaintBoundary).last, matchesGoldenFile(Uri.file('$out/mark-motion-$i.png')));
    }
  });
}
