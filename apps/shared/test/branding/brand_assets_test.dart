// Renders the Aavagaman mark to PNG for app icons and docs (D-057).
// Skipped unless RIDE_BRAND_OUT points at an output directory:
//   RIDE_BRAND_OUT=/tmp/brand flutter test --update-goldens test/branding
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

final out = Platform.environment['RIDE_BRAND_OUT'];

Future<void> loadFonts() async {
  final jakarta = FontLoader('packages/ride_shared/PlusJakartaSans');
  for (final w in [400, 500, 600, 700, 800]) {
    jakarta.addFont(File('fonts/PlusJakartaSans-$w.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await jakarta.load();
}

/// Android densities: dp multiplier per bucket.
const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

Future<void> render(WidgetTester tester, Widget w, double px, String name) async {
  tester.view.physicalSize = Size(px, px);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Center(child: RepaintBoundary(child: SizedBox.square(dimension: px, child: w))));
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/$name.png')));
}

void main() {
  if (out == null) {
    test('brand assets', () {}, skip: 'Set RIDE_BRAND_OUT to render the brand assets');
    return;
  }
  // Real file I/O must happen outside the test zone.
  setUpAll(loadFonts);
  for (final (app, style, light) in [('rider', BrandIconStyle.dark, false), ('driver', BrandIconStyle.green, true)]) {
    testWidgets('$app icons', (tester) async {
      for (final MapEntry(key: bucket, value: m) in densities.entries) {
        // Legacy launcher icon (48 dp) with the tile baked in.
        await render(tester, AavagamanIcon(size: 48 * m, style: style, radiusFactor: 0.18), 48 * m, '$app-ic_launcher-$bucket');
        // Adaptive foreground: 108 dp canvas, mark inside the 66 dp safe zone.
        await render(tester, Center(child: AavagamanMark(size: 56 * m, light: light)), 108 * m, '$app-ic_launcher_foreground-$bucket');
        // Launch-screen logo (112 dp, transparent).
        await render(tester, Center(child: AavagamanMark(size: 112 * m, light: false)), 112 * m, '$app-launch_logo-$bucket');
      }
      await render(tester, AavagamanIcon(size: 512, style: style, radiusFactor: 0.18), 512, '$app-icon-512');
    });
  }
  testWidgets('splash', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const RepaintBoundary(
        child: SplashArt(
          appName: Brand.name,
          tagline: Brand.tagline,
          quote: 'Har safar ka apna ek maqsad hota hai.',
          footer: SizedBox(height: 40),
        ),
      ),
    ));
    await tester.pump();
    // Decode the backdrop picture (asset images load asynchronously in tests).
    await tester.runAsync(() => precacheImage(
          const AssetImage(Brand.splashAsset, package: 'ride_shared'),
          tester.element(find.byType(SplashArt)),
        ));
    await tester.pump();
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/splash-1080x2400.png')));
  });

  testWidgets('logo', (tester) async {
    await render(tester, const AavagamanMark(size: 1024), 1024, 'aavagaman-mark-1024');
    await render(tester, const AavagamanIcon(size: 1024, style: BrandIconStyle.light), 1024, 'aavagaman-tile-light-1024');
    await render(tester, const AavagamanIcon(size: 1024, style: BrandIconStyle.dark), 1024, 'aavagaman-tile-dark-1024');
  });
}
