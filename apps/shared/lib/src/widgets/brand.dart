import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// BlinCab brand (D-059): the owner's logo, yellow and white line art of an
/// auto, a cab and a bike, on black. The three vehicles are cut out of
/// `docs/branding/blincab-logo-source.png` as a transparent PNG and are the
/// mark (icons, launch screen); the name is set in code where it is shown
/// inside the app, and the "road" loaders carry the motif.
abstract final class Brand {
  static const package = 'ride_shared';

  /// Splash backdrop inside this package (`Image.asset(..., package: Brand.package)`).
  static const splashAsset = 'assets/splash_india_gate.jpg';

  /// Auto, cab and bike (1010×440, transparent): the mark without the name.
  static const vehiclesAsset = 'assets/blincab_vehicles.png';

  static const name = 'BlinCab';
  static const tagline = 'Bike • Cab • Auto';

  static const yellow = Color(0xFFFFD714); // the cab, "Cab" in the wordmark
  static const amber = Color(0xFFC99A00); // yellow that reads on white
  static const black = Color(0xFF0A0A0A); // logo background, launch screen
  static const charcoal = Color(0xFF111111);
  static const grey = Color(0xFFBDBDBD); // the tagline
  static const road = Color(0xFF1F1F1F);
}

/// The mark: auto, cab and bike side by side, [width] wide (height follows the art).
class BlinCabVehicles extends StatelessWidget {
  const BlinCabVehicles({super.key, required this.width});

  final double width;

  /// Height / width of the art.
  static const ratio = 440 / 1010;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * ratio,
    child: Image.asset(Brand.vehiclesAsset, package: Brand.package, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
  );
}

/// The name set like the logo: white with "Cab" in yellow, the tagline spaced
/// out in grey underneath. [text] may carry a suffix ("BlinCab Driver").
class BlinCabWordmark extends StatelessWidget {
  const BlinCabWordmark({
    super.key,
    this.text = Brand.name,
    this.tagline,
    this.size = 36,
    this.color = Colors.white,
    this.accent = Brand.yellow,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String text;
  final String? tagline;

  /// Font size of the name; the tagline is a third of it.
  final double size;
  final Color color;
  final Color accent;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final base = (t.displaySmall ?? const TextStyle()).copyWith(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -size * 0.02,
      height: 1.1,
    );
    final i = text.indexOf('Cab');
    final spans = i < 0
        ? [TextSpan(text: text)]
        : [
            TextSpan(text: text.substring(0, i)),
            TextSpan(text: 'Cab', style: TextStyle(color: accent)),
            TextSpan(text: text.substring(i + 3)),
          ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text.rich(TextSpan(style: base, children: spans), textAlign: TextAlign.center),
        if (tagline != null)
          Padding(
            padding: EdgeInsets.only(top: size * 0.12),
            child: Text(
              tagline!.toUpperCase(),
              textAlign: TextAlign.center,
              style: (t.labelLarge ?? const TextStyle()).copyWith(
                color: color == Colors.white ? Brand.grey : color.withValues(alpha: 0.7),
                fontSize: size * 0.3,
                fontWeight: FontWeight.w700,
                letterSpacing: size * 0.08,
              ),
            ),
          ),
      ],
    );
  }
}

enum BrandIconStyle {
  /// Black tile: the rider app, the admin panel.
  dark,

  /// Black tile with a yellow rim: the driver app, so both icons tell apart.
  ring,
}

/// App icon: the vehicles on a rounded black tile (also the in-app brand badge).
class BlinCabIcon extends StatelessWidget {
  const BlinCabIcon({super.key, this.size = 64, this.style = BrandIconStyle.dark, this.radiusFactor = 0.24});

  final double size;
  final BrandIconStyle style;
  final double radiusFactor;

  @override
  Widget build(BuildContext context) {
    final rim = style == BrandIconStyle.ring ? size * 0.055 : 0.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.black,
        borderRadius: BorderRadius.circular(size * radiusFactor),
        border: rim > 0 ? Border.all(color: Brand.yellow, width: rim) : null,
      ),
      child: Center(child: BlinCabVehicles(width: size * 0.86)),
    );
  }
}

/// A strip of road: dark tarmac with yellow centre dashes. [animated] slides
/// the dashes towards the left, as if the vehicles above were driving on.
class BrandRoad extends StatefulWidget {
  const BrandRoad({super.key, required this.width, this.animated = false, this.height});

  final double width;
  final bool animated;

  /// Defaults to 7% of [width].
  final double? height;

  /// One dash+gap step.
  static const cycle = Duration(milliseconds: 700);

  @override
  State<BrandRoad> createState() => _BrandRoadState();
}

class _BrandRoadState extends State<BrandRoad> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animated) _start();
  }

  @override
  void didUpdateWidget(BrandRoad old) {
    super.didUpdateWidget(old);
    if (widget.animated && _c == null) _start();
    if (!widget.animated && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  void _start() => _c = AnimationController(vsync: this, duration: BrandRoad.cycle)..repeat();

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.height ?? widget.width * 0.07);
    final c = _c;
    if (c == null) return CustomPaint(size: size, painter: const _RoadPainter(0));
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) => CustomPaint(size: size, painter: _RoadPainter(c.value)),
    );
  }
}

class _RoadPainter extends CustomPainter {
  const _RoadPainter(this.phase);

  /// 0..1 of one dash+gap step.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = Radius.circular(h / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = Brand.road);
    // Fade the ends so the strip reads as a stretch of road, not a bar.
    final fade = Paint()
      ..shader = const LinearGradient(
        colors: [Brand.black, Color(0x000A0A0A), Color(0x000A0A0A), Brand.black],
        stops: [0, 0.18, 0.82, 1],
      ).createShader(Offset.zero & size);
    final dash = w * 0.07, gap = w * 0.045;
    final line = Path()
      ..moveTo(0, h / 2)
      ..lineTo(w, h / 2);
    // Dashes move left: offset the pattern backwards as phase grows.
    canvas.drawPath(
      dashed(line, dash, gap, offset: (1 - phase) * (dash + gap)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.22
        ..strokeCap = StrokeCap.round
        ..color = Brand.yellow,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), fade);
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.phase != phase;
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
        ..color = Brand.yellow.withValues(alpha: 0.35 * opacity),
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
        ..color = Colors.white.withValues(alpha: 0.10 * opacity),
    );
  }

  @override
  bool shouldRepaint(_RoadBackdropPainter old) => old.opacity != opacity;
}

/// Draws a yellow pin head at [at] (used on loaders and progress rings).
void paintPinHead(Canvas canvas, Offset at, double radius) {
  canvas.drawCircle(at, radius, Paint()..color = Brand.yellow);
  canvas.drawCircle(at, radius * 0.42, Paint()..color = Brand.black);
}

/// "Route progress" loader: a rotating arc that ends in a yellow pin.
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

/// The splash screen's look, without session logic (so it can be previewed):
/// how far the India Gate picture recedes behind the logo.
class SplashLook {
  const SplashLook({this.photo = true, this.dim = 0.62, this.saturation = 0.45, this.blur = 0, this.tint, this.logoFraction = 0.74});

  /// False shows the logo on plain black, as on the brand board.
  final bool photo;

  /// Black veil over the picture (0 = untouched, 1 = black).
  final double dim;

  /// 1 keeps the sunset colours; lower values mute them.
  final double saturation;

  /// Gaussian blur radius in logical pixels (0 = sharp).
  final double blur;

  /// Optional colour wash (alpha included).
  final Color? tint;

  /// Width of the vehicles as a fraction of the screen width.
  final double logoFraction;

  /// The shipped look (D-059): the picture sinks to a night scene so the
  /// yellow-and-white line art leads.
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
    // cropped to the screen and sunk to night; the mark and the name sit in the sky.
    Widget backdrop = Image.asset(
      Brand.splashAsset,
      package: Brand.package,
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
      color: Brand.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (look.photo) backdrop,
          if (look.photo && look.dim > 0) ColoredBox(color: Brand.black.withValues(alpha: look.dim)),
          if (look.tint != null) ColoredBox(color: look.tint!),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.35, 0.7, 1],
                colors: [Color(0xB30A0A0A), Color(0x000A0A0A), Color(0x000A0A0A), Color(0xCC0A0A0A)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth * look.logoFraction;
                  return Column(
                    children: [
                      const Spacer(flex: 1),
                      // The mark with the road running behind the wheels, the name set below.
                      SizedBox(
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
                      const SizedBox(height: 18),
                      BlinCabWordmark(text: appName, tagline: tagline, size: 40),
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
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
