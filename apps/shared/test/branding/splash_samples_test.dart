// Side-by-side samples of splash backdrop treatments, for picking a look.
// Skipped unless RIDE_BRAND_OUT points at an output directory:
//   RIDE_BRAND_OUT=/tmp/brand flutter test --update-goldens test/branding/splash_samples_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'brand_assets_test.dart' show loadArt, loadFonts;

final out = Platform.environment['RIDE_BRAND_OUT'];

const samples = <String, SplashLook>{
  'A · plain black (brand board)': SplashLook(photo: false),
  'B · night (shipped)': SplashLook.standard,
  'C · dusk': SplashLook(dim: 0.4, saturation: 0.6),
  'D · soft blur': SplashLook(dim: 0.5, saturation: 0.6, blur: 2.5),
  'E · untouched': SplashLook(dim: 0, saturation: 1),
};

void main() {
  if (out == null) return;
  setUpAll(loadFonts);
  testWidgets('splash samples', (tester) async {
    await loadArt(tester);
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
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(Uri.file('$out/splash-looks.png')));
  });
}
