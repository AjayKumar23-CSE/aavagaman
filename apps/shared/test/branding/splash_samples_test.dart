// Side-by-side samples of splash backdrop treatments, for picking a look.
// Skipped unless RIDE_BRAND_OUT points at an output directory:
//   RIDE_BRAND_OUT=/tmp/brand flutter test --update-goldens test/branding/splash_samples_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'brand_assets_test.dart' show loadFonts;

final out = Platform.environment['RIDE_BRAND_OUT'];

const samples = <String, SplashLook>{
  'A · untouched': SplashLook(dim: 0, saturation: 1, markSize: 88),
  'B · muted + dim (shipped)': SplashLook.standard,
  'C · dusk green tint': SplashLook(dim: 0.3, saturation: 0.6, tint: Color(0x400F3D2E)),
  'D · soft blur': SplashLook(dim: 0.32, saturation: 0.8, blur: 2.5),
  'E · night': SplashLook(dim: 0.55, saturation: 0.5),
};

void main() {
  if (out == null) return;
  setUpAll(loadFonts);
  testWidgets('splash samples', (tester) async {
    tester.view.physicalSize = Size(412.0 * samples.length, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RepaintBoundary(
          child: Row(
            children: [
              for (final MapEntry(key: name, value: look) in samples.entries)
                SizedBox(
                  width: 412,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SplashArt(
                        appName: Brand.name,
                        tagline: Brand.tagline,
                        quote: 'Har safar ka apna ek maqsad hota hai.',
                        footer: const SizedBox(height: 40),
                        look: look,
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Builder(
                          builder: (context) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.white,
                            child: Text(
                              name,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(Brand.splashAsset, package: 'ride_shared'),
        tester.element(find.byType(SplashArt).first),
      ),
    );
    await tester.pump();
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/splash-looks.png')));
  });
}
