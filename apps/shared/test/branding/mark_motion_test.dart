// Frames of the splash road animation (the dashes slide left behind the
// vehicles), for a visual check. Skipped unless RIDE_BRAND_OUT points at an
// output directory.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'brand_assets_test.dart' show loadArt;

final out = Platform.environment['RIDE_BRAND_OUT'];

void main() {
  if (out == null) return;
  testWidgets('road motion frames', (tester) async {
    await loadArt(tester);
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const w = 300.0;
    await tester.pumpWidget(const MaterialApp(
      home: ColoredBox(
        color: Brand.black,
        child: Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: w,
              height: w * BlinCabVehicles.ratio,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(top: w * 0.355, child: BrandRoad(width: w * 0.98, animated: true)),
                  BlinCabVehicles(width: w),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 175));
      await expectLater(find.byType(RepaintBoundary).last, matchesGoldenFile(Uri.file('$out/road-motion-$i.png')));
    }
  });
}
