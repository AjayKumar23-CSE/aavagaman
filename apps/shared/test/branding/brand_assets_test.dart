// Renders the BlinCab mark to PNG for app icons, the launch screen, the admin
// panel and docs (D-059). Skipped unless RIDE_BRAND_OUT points at an output directory:
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

/// Decodes the brand PNGs so they are painted on the first frame (asset
/// images load asynchronously in tests).
Future<void> loadArt(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  final context = tester.element(find.byType(SizedBox));
  await tester.runAsync(() async {
    for (final asset in [Brand.vehiclesAsset, Brand.splashAsset]) {
      await precacheImage(AssetImage(asset, package: Brand.package), context);
    }
  });
}

Future<void> render(WidgetTester tester, Widget w, double px, String name, {double? height}) async {
  tester.view.physicalSize = Size(px, height ?? px);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Center(child: RepaintBoundary(child: SizedBox(width: px, height: height ?? px, child: w))),
    ),
  );
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/$name.png')));
}

void main() {
  if (out == null) {
    test('brand assets', () {}, skip: 'Set RIDE_BRAND_OUT to render the brand assets');
    return;
  }
  // Real file I/O must happen outside the test zone.
  setUpAll(loadFonts);
  for (final (app, style) in [('rider', BrandIconStyle.dark), ('driver', BrandIconStyle.ring)]) {
    testWidgets('$app icons', (tester) async {
      await loadArt(tester);
      for (final MapEntry(key: bucket, value: m) in densities.entries) {
        // Legacy launcher icon (48 dp) with the tile baked in.
        await render(tester, BlinCabIcon(size: 48 * m, style: style, radiusFactor: 0.18), 48 * m, '$app-ic_launcher-$bucket');
        // Adaptive foreground: 108 dp canvas, art inside the 66 dp safe zone, on the
        // black @color/ic_launcher_background.
        await render(
          tester,
          Center(
            child: style == BrandIconStyle.ring
                ? Container(
                    width: 62 * m,
                    height: 62 * m,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.yellow, width: 3 * m)),
                    child: Center(child: BlinCabVehicles(width: 48 * m)),
                  )
                : BlinCabVehicles(width: 62 * m),
          ),
          108 * m,
          '$app-ic_launcher_foreground-$bucket',
        );
        // Launch-screen art (transparent, 160×70 dp) on @color/launch_background.
        await render(tester, Center(child: BlinCabVehicles(width: 160 * m)), 160 * m, '$app-launch_logo-$bucket', height: 70 * m);
      }
      await render(tester, BlinCabIcon(size: 512, style: style, radiusFactor: 0.18), 512, '$app-icon-512');
    });
  }
  testWidgets('splash', (tester) async {
    await loadArt(tester);
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
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/splash-1080x2400.png')));
  });

  testWidgets('logo', (tester) async {
    await loadArt(tester);
    await render(tester, const BlinCabIcon(size: 1024), 1024, 'blincab-tile-1024');
    await render(tester, const BlinCabIcon(size: 192), 192, 'admin-logo-192');
  });
}
