import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand.dart';

/// Rounded gradient square with the taxi mark: splash, auth header, drawer.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64, this.onGradient = false});

  final double size;

  /// On dark brand backgrounds the mark is shown bare (no tile).
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    if (onGradient) return AavagamanMark(size: size);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: size * 0.25, offset: Offset(0, size * 0.1))],
      ),
      child: AavagamanIcon(size: size),
    );
  }
}

/// White card with a hairline border and a soft shadow.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = AppTheme.radiusLarge,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final shape = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: shape,
        border: Border.all(color: borderColor ?? scheme.outlineVariant),
        boxShadow: shadow ? [BoxShadow(color: colors.shadow, blurRadius: 20, offset: const Offset(0, 8))] : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Bottom panel over a map: rounded top, shadow, safe-area aware.
class SheetPanel extends StatelessWidget {
  const SheetPanel({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
    this.handle = true,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool handle;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxisAlignment,
          children: [
            if (handle) const DragHandle(),
            Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: crossAxisAlignment,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DragHandle extends StatelessWidget {
  const DragHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Gradient header block with rounded bottom corners (status screens).
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 32),
    this.radius = 32,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: colors.gradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      child: SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small uppercase-ish section heading with an optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.only(bottom: 8)});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text, style: t.labelMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Rounded status label: "Pending", "Paid", "Online"…
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon, this.filled = false});

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid background with white text instead of the tinted look.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Tinted circle with an icon.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 44, this.filled = false});

  final IconData icon;
  final Color? color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: filled ? Colors.white : c, size: size * 0.5),
    );
  }
}

/// Initials avatar on the brand gradient.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.radius = 24});

  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final initials = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p.characters.first.toUpperCase())
        .join();
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: colors.gradient, shape: BoxShape.circle),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
          fontFamily: AppTheme.fontFamily,
          package: AppTheme.fontPackage,
        ),
      ),
    );
  }
}

/// Indian number-plate style badge.
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.regNumber, {super.key, this.large = false});

  final String regNumber;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 8 : 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.onSurface, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        regNumber,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          package: AppTheme.fontPackage,
          fontWeight: FontWeight.w800,
          fontSize: large ? 18 : 14,
          letterSpacing: 1.2,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// Pickup (green dot) → drop (red pin) with a dotted connector.
class RoutePoints extends StatelessWidget {
  const RoutePoints({
    super.key,
    required this.pickup,
    required this.drop,
    this.pickupLabel,
    this.dropLabel,
    this.onChangePickup,
    this.onChangeDrop,
    this.changeLabel,
    this.dense = false,
  });

  final String pickup;
  final String drop;
  final String? pickupLabel;
  final String? dropLabel;
  final VoidCallback? onChangePickup;
  final VoidCallback? onChangeDrop;
  final String? changeLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final addressStyle = dense ? t.bodyMedium?.copyWith(color: scheme.onSurface) : t.bodyLarge;

    Widget row(Widget marker, String? label, String address, VoidCallback? onChange) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 24, child: Center(child: marker)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null && !dense) Text(label, style: t.labelSmall),
                  Text(address, style: addressStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onChange != null && changeLabel != null)
              TextButton(
                onPressed: onChange,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(changeLabel!),
              ),
          ],
        );

    return Column(
      children: [
        row(
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colors.success,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
              boxShadow: [BoxShadow(color: colors.success.withValues(alpha: 0.4), blurRadius: 6)],
            ),
          ),
          pickupLabel,
          pickup,
          onChangePickup,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 2,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 1.5),
                    decoration: BoxDecoration(color: scheme.outline, borderRadius: BorderRadius.circular(1)),
                  ),
              ],
            ),
          ),
        ),
        row(Icon(Icons.location_on, size: 20, color: scheme.error), dropLabel, drop, onChangeDrop),
      ],
    );
  }
}

/// Icon-in-a-circle action with a caption (Call · Share · SOS).
class ActionCircle extends StatelessWidget {
  const ActionCircle({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    final enabled = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            fixedSize: const Size(54, 54),
            backgroundColor: filled ? c : c.withValues(alpha: 0.12),
            foregroundColor: filled ? Colors.white : c,
            disabledBackgroundColor: scheme.surfaceContainerHigh,
            disabledForegroundColor: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

enum BannerTone { info, warning, success, error }

/// Tinted message box with an icon and an optional action.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.tone = BannerTone.info,
    this.title,
    this.icon,
    this.action,
  });

  final String message;
  final BannerTone tone;
  final String? title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final (bg, fg, defaultIcon) = switch (tone) {
      BannerTone.info => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.info_outline_rounded),
      BannerTone.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.warning_amber_rounded),
      BannerTone.success => (colors.successContainer, colors.onSuccessContainer, Icons.check_circle_outline_rounded),
      BannerTone.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: t.titleSmall?.copyWith(color: fg)),
                Text(message, style: t.bodyMedium?.copyWith(color: fg)),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 4),
            Theme(
              data: Theme.of(context).copyWith(
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: fg, visualDensity: VisualDensity.compact),
                ),
              ),
              child: action!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Centred illustration-style empty / outcome state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: IconBadge(icon: icon, color: color, size: 88)),
          const SizedBox(height: 20),
          Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!, style: t.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

/// Label above a big value (earnings, dashboard tiles).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color, this.caption});

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[IconBadge(icon: icon!, color: color, size: 32), const SizedBox(height: 10)],
          Text(label, style: t.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (caption != null) Text(caption!, style: t.bodySmall),
        ],
      ),
    );
  }
}

/// Circular progress with content in the middle (countdowns).
class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.value,
    required this.child,
    this.size = 120,
    this.stroke = 8,
    this.color,
    this.track,
    this.pin = false,
    this.gradient,
  });

  final double value;
  final Widget child;
  final double size;
  final double stroke;
  final Color? color;
  final Color? track;

  /// Saffron pin at the head of the arc (brand "route" style).
  final bool pin;

  /// Sweep gradient along the arc instead of a flat [color].
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: BrandRingPainter(
          value: value,
          stroke: stroke,
          color: color ?? scheme.primary,
          track: track ?? scheme.surfaceContainerHigh,
          pin: pin,
          gradient: gradient,
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Round floating button for map overlays (menu, locate me).
class FloatingCircleButton extends StatelessWidget {
  const FloatingCircleButton({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: scheme.onSurface),
        style: IconButton.styleFrom(shape: const CircleBorder(), minimumSize: const Size(48, 48)),
      ),
    );
  }
}

/// One line of a key/value list inside a card.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: scheme.onSurfaceVariant), const SizedBox(width: 10)],
          Expanded(child: Text(label, style: t.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Thin top strip ("Reconnecting…").
class StatusStrip extends StatelessWidget {
  const StatusStrip(this.text, {super.key, this.tone = BannerTone.warning});

  final String text;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      BannerTone.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      BannerTone.error => (scheme.errorContainer, scheme.onErrorContainer),
      BannerTone.success => (AppColors.of(context).successContainer, AppColors.of(context).onSuccessContainer),
      BannerTone.info => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
              const SizedBox(width: 8),
              Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
