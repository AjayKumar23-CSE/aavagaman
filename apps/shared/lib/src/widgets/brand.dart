import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Aavagaman brand (D-057): colours from the brand board, the mark drawn as
/// vector code so it is crisp at every size, and the "route" loaders.
abstract final class Brand {
  /// Splash backdrop inside this package (`Image.asset(..., package: 'ride_shared')`).
  static const splashAsset = 'assets/splash_india_gate.jpg';

  static const name = 'Aavagaman';
  static const tagline = 'Safar • Aapke Saath';

  static const deepGreen = Color(0xFF0F3D2E); // trust, nature
  static const freshGreen = Color(0xFF22C55E); // progress, energy
  static const leaf = Color(0xFF15803D);
  static const mint = Color(0xFF4ADE80);
  static const saffron = Color(0xFFF59E0B); // India, warmth
  static const charcoal = Color(0xFF080F14); // premium, focus
  static const road = Color(0xFF111827);
}

/// The mark alone: a green "A" with a road climbing through it to a saffron pin.
/// Transparent background; [light] draws a white letter for green backgrounds.
class AavagamanMark extends StatefulWidget {
  const AavagamanMark({super.key, this.size = 64, this.light = false, this.animated = false});

  final double size;
  final bool light;

  /// Drives the road: dashes travel up towards the pin and the pin pulses
  /// (splash screens). Off by default so icons and goldens stay still.
  final bool animated;

  /// One trip of the dashes plus one pin pulse.
  static const cycle = Duration(milliseconds: 1600);

  @override
  State<AavagamanMark> createState() => _AavagamanMarkState();
}

class _AavagamanMarkState extends State<AavagamanMark> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animated) _start();
  }

  @override
  void didUpdateWidget(AavagamanMark old) {
    super.didUpdateWidget(old);
    if (widget.animated && _c == null) _start();
    if (!widget.animated && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  void _start() => _c = AnimationController(vsync: this, duration: AavagamanMark.cycle)..repeat();

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _MarkPainter(light: widget.light),
      );
    }
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _MarkPainter(light: widget.light, phase: c.value, pulse: c.value),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.light, this.phase = 0, this.pulse = 0});

  final bool light;

  /// 0..1: how far the dashes have travelled along one dash+gap period.
  final double phase;

  /// 0..1: the pin's pulse ring, from tight and bright to wide and gone.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final dx = (size.width - s) / 2, dy = (size.height - s) / 2;
    canvas.translate(dx, dy);

    final letter = Path()
      ..moveTo(0.13 * s, 0.90 * s)
      ..lineTo(0.46 * s, 0.14 * s)
      ..lineTo(0.79 * s, 0.90 * s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.21 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Soft shadow under the letter.
    canvas.save();
    canvas.translate(0, 0.025 * s);
    canvas.drawPath(
      letter,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.21 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.03 * s),
    );
    canvas.restore();

    stroke.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: light ? const [Colors.white, Color(0xFFD1FAE5)] : const [Brand.mint, Brand.leaf],
    ).createShader(Rect.fromLTWH(0, 0, s, s));
    canvas.drawPath(letter, stroke);

    // The road climbs from the bottom left, through the letter, to the pin.
    final road = Path()
      ..moveTo(0.20 * s, 1.00 * s)
      ..quadraticBezierTo(0.42 * s, 0.70 * s, 0.80 * s, 0.34 * s);
    canvas.drawPath(
      road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.12 * s
        ..strokeCap = StrokeCap.round
        ..color = Brand.road,
    );
    canvas.drawPath(
      dashed(road, 0.055 * s, 0.045 * s, offset: phase * (0.055 + 0.045) * s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018 * s
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    // Saffron pin at the end of the road.
    final c = Offset(0.80 * s, 0.20 * s);
    final r = 0.115 * s;
    // Head and tail are filled separately: one path would leave a winding hole where they overlap.
    final tail = Path()
      ..moveTo(c.dx - r * 0.72, c.dy + r * 0.70)
      ..lineTo(c.dx, c.dy + r * 2.0)
      ..lineTo(c.dx + r * 0.72, c.dy + r * 0.70)
      ..close();
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.025 * s);
    canvas.drawPath(tail.shift(Offset(0, 0.02 * s)), shadow);
    canvas.drawCircle(c + Offset(0, 0.02 * s), r, shadow);
    final saffron = Paint()..color = Brand.saffron;
    if (pulse > 0) {
      // Pulse ring: a "you are here" ping spreading out from the pin head.
      final eased = Curves.easeOut.transform(pulse);
      canvas.drawCircle(
        c,
        r * (1 + 1.1 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.22 * (1 - eased) + 0.5
          ..color = Brand.saffron.withValues(alpha: 0.55 * (1 - eased)),
      );
    }
    canvas.drawPath(tail, saffron);
    canvas.drawCircle(c, r, saffron);
    // The white dot breathes with the pulse.
    final dot = r * 0.42 * (1 + 0.18 * math.sin(pulse * math.pi));
    canvas.drawCircle(c, dot, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.light != light || old.phase != phase || old.pulse != pulse;
}

/// [src] as dashes of [dash] length separated by [gap]; [offset] slides the
/// pattern forward along the path (0 .. dash+gap for one full step).
Path dashed(Path src, double dash, double gap, {double offset = 0}) {
  final out = Path();
  final period = dash + gap;
  for (final metric in src.computeMetrics()) {
    var d = (offset % period) - period;
    while (d < metric.length) {
      final a = math.max(d, 0.0), b = math.min(d + dash, metric.length);
      if (b > a) out.addPath(metric.extractPath(a, b), Offset.zero);
      d += period;
    }
  }
  return out;
}

enum BrandIconStyle { dark, light, green }

/// App icon: the mark on a rounded tile (also the in-app brand badge).
class AavagamanIcon extends StatelessWidget {
  const AavagamanIcon({super.key, this.size = 64, this.style = BrandIconStyle.dark, this.radiusFactor = 0.24});

  final double size;
  final BrandIconStyle style;
  final double radiusFactor;

  @override
  Widget build(BuildContext context) {
    final (gradient, light) = switch (style) {
      BrandIconStyle.dark => (const [Color(0xFF12302A), Brand.charcoal], false),
      BrandIconStyle.light => (const [Color(0xFFF8FAF9), Color(0xFFE8EFEB)], false),
      BrandIconStyle.green => (const [Color(0xFF16A34A), Brand.leaf], true),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
        borderRadius: BorderRadius.circular(size * radiusFactor),
      ),
      child: Center(
        child: AavagamanMark(size: size * 0.70, light: light),
      ),
    );
  }
}

/// Faint road curves for dark brand screens (splash, headers).
class RoadBackdrop extends StatelessWidget {
  const RoadBackdrop({super.key, this.opacity = 1});

  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _RoadBackdropPainter(opacity), size: Size.infinite),
  );
}

class _RoadBackdropPainter extends CustomPainter {
  const _RoadBackdropPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final road = Path()
      ..moveTo(-0.1 * w, h * 1.02)
      ..cubicTo(0.35 * w, 0.78 * h, 0.55 * w, 0.95 * h, 1.15 * w, 0.62 * h);
    canvas.drawPath(
      road,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.26 * w
        ..color = Colors.white.withValues(alpha: 0.05 * opacity),
    );
    canvas.drawPath(
      dashed(road, 0.05 * w, 0.035 * w),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.012 * w
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.14 * opacity),
    );
    final hill = Path()
      ..moveTo(-0.05 * w, 0.80 * h)
      ..quadraticBezierTo(0.22 * w, 0.58 * h, 0.5 * w, 0.76 * h)
      ..quadraticBezierTo(0.78 * w, 0.92 * h, 1.05 * w, 0.70 * h);
    canvas.drawPath(
      hill,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Brand.mint.withValues(alpha: 0.10 * opacity),
    );
  }

  @override
  bool shouldRepaint(_RoadBackdropPainter old) => old.opacity != opacity;
}

/// Draws a saffron pin head at [at] (used on loaders and progress rings).
void paintPinHead(Canvas canvas, Offset at, double radius) {
  canvas.drawCircle(at, radius, Paint()..color = Brand.saffron);
  canvas.drawCircle(at, radius * 0.42, Paint()..color = Colors.white);
}

/// "Route progress" loader: a rotating arc that ends in a saffron pin.
class RouteLoader extends StatefulWidget {
  const RouteLoader({super.key, this.size = 44, this.stroke = 4.5, this.color, this.track});

  final double size;
  final double stroke;
  final Color? color;
  final Color? track;

  @override
  State<RouteLoader> createState() => _RouteLoaderState();
}

class _RouteLoaderState extends State<RouteLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _ArcPainter(
              start: _c.value * 2 * math.pi,
              sweep: 1.55 * math.pi,
              stroke: widget.stroke,
              color: widget.color ?? scheme.primary,
              track: widget.track ?? scheme.primary.withValues(alpha: 0.15),
              pin: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Arc on a track, optionally with a pin at the arc's head.
class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.start,
    required this.sweep,
    required this.stroke,
    required this.color,
    required this.track,
    required this.pin,
    this.gradient,
  });

  final double start;
  final double sweep;
  final double stroke;
  final Color color;
  final Color track;
  final bool pin;
  final List<Color>? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = pin ? stroke * 1.3 : stroke / 2;
    final rect = Rect.fromLTWH(pad, pad, size.width - 2 * pad, size.height - 2 * pad);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base..color = track);
    if (sweep <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (gradient != null) {
      arc.shader = SweepGradient(
        startAngle: 0,
        endAngle: math.max(sweep, 0.01),
        colors: gradient!,
        transform: GradientRotation(start),
      ).createShader(rect);
    }
    canvas.drawArc(rect, start, sweep, false, arc);
    if (pin) {
      final a = start + sweep;
      final c = rect.center;
      final at = Offset(c.dx + rect.width / 2 * math.cos(a), c.dy + rect.height / 2 * math.sin(a));
      paintPinHead(canvas, at, stroke * 1.15);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.start != start || old.sweep != sweep || old.color != color || old.pin != pin || old.gradient != gradient;
}

/// Determinate ring (countdowns) in the brand style: see [RingProgress].
class BrandRingPainter extends CustomPainter {
  const BrandRingPainter({
    required this.value,
    required this.stroke,
    required this.color,
    required this.track,
    this.pin = false,
    this.gradient,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color track;
  final bool pin;
  final List<Color>? gradient;

  @override
  void paint(Canvas canvas, Size size) => _ArcPainter(
    start: -math.pi / 2,
    sweep: 2 * math.pi * value.clamp(0, 1),
    stroke: stroke,
    color: color,
    track: track,
    pin: pin,
    gradient: gradient,
  ).paint(canvas, size);

  @override
  bool shouldRepaint(BrandRingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.pin != pin || old.gradient != gradient;
}

/// The splash screen's look, without session logic (so it can be previewed).
/// How far the India Gate picture recedes behind the mark on the splash.
class SplashLook {
  const SplashLook({this.dim = 0.34, this.saturation = 0.7, this.blur = 0, this.tint, this.markSize = 104});

  /// Charcoal veil over the picture (0 = untouched, 1 = black).
  final double dim;

  /// 1 keeps the sunset colours; lower values mute them.
  final double saturation;

  /// Gaussian blur radius in logical pixels (0 = sharp).
  final double blur;

  /// Optional colour wash (alpha included), e.g. a deep-green dusk.
  final Color? tint;

  /// Size of the mark above the wordmark.
  final double markSize;

  /// The shipped look (chosen 2026-10-18): muted and dimmed so the mark leads.
  static const standard = SplashLook();

  /// Colour matrix that scales saturation (Rec. 601 luma weights).
  List<double> get saturationMatrix {
    const r = 0.299, g = 0.587, b = 0.114;
    final s = saturation, i = 1 - s;
    return [
      i * r + s, i * g, i * b, 0, 0, //
      i * r, i * g + s, i * b, 0, 0, //
      i * r, i * g, i * b + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }
}

class SplashArt extends StatelessWidget {
  const SplashArt({
    super.key,
    required this.appName,
    required this.tagline,
    required this.quote,
    required this.footer,
    this.look = SplashLook.standard,
  });

  final String appName;
  final String tagline;
  final String quote;

  /// Loader or error block under the quote.
  final Widget footer;

  final SplashLook look;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // The brand board's India Gate sunset (docs/branding/splash-india-gate-source.png),
    // cropped to the screen; the sky and road take the wordmark and the quote.
    Widget backdrop = Image.asset(
      Brand.splashAsset,
      package: 'ride_shared',
      fit: BoxFit.cover,
      alignment: Alignment.center,
    );
    if (look.saturation != 1) {
      backdrop = ColorFiltered(colorFilter: ColorFilter.matrix(look.saturationMatrix), child: backdrop);
    }
    if (look.blur > 0) {
      backdrop = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: look.blur, sigmaY: look.blur),
        child: backdrop,
      );
    }
    return ColoredBox(
      color: Brand.charcoal,
      child: Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          if (look.dim > 0) ColoredBox(color: Brand.charcoal.withValues(alpha: look.dim)),
          if (look.tint != null) ColoredBox(color: look.tint!),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.35, 0.7, 1],
                colors: [Color(0xB3080F14), Color(0x00080F14), Color(0x00080F14), Color(0xCC080F14)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                children: [
                  // Mark and wordmark in the sky above the sun; the quote over the road.
                  const Spacer(flex: 1),
                  AavagamanMark(size: look.markSize, animated: true),
                  const SizedBox(height: 12),
                  Text(
                    appName,
                    style: t.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tagline.toUpperCase(),
                    style: t.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.75), letterSpacing: 3),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(flex: 15),
                  Text(
                    quote,
                    style: t.titleSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  footer,
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
