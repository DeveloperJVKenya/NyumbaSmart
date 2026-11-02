import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/theme/app_theme.dart';

/// Shared visual language for the entry flow (Welcome → Organization → Facility → Dashboard home).
///
/// Built on the existing NyumbaSmart tokens in app_theme.dart (indigo primary, amber accent) and
/// adds the "brand stage" look: a deep indigo backdrop with soft radial glows and a faint blueprint
/// grid, a display typeface for headlines, eyebrow labels, hover-lift cards and count-up stats.
class BrandColors {
  BrandColors._();

  /// Deep stage colours behind hero areas.
  static const Color ink = Color(0xFF0E0C2A);
  static const Color inkSoft = Color(0xFF1B1747);
  static const Color inkLift = Color(0xFF272266);

  static const LinearGradient stageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, inkSoft, Color(0xFF2B2581)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Thin indigo → amber bar under headlines (brand signature).
  static const LinearGradient accentBar = LinearGradient(
    colors: [AppColors.primaryLight, AppColors.accent, AppColors.accentLight],
  );

  static const LinearGradient ctaGradient = LinearGradient(
    colors: [AppColors.accent, AppColors.accentLight],
  );

  /// Stable, readable tile colour per name (monograms, cover fallbacks).
  static Color forName(String name) {
    const palette = [
      Color(0xFF4F46E5),
      Color(0xFF0EA5E9),
      Color(0xFF0D9488),
      Color(0xFFD97706),
      Color(0xFF7C3AED),
      Color(0xFFDB2777),
      Color(0xFF2563EB),
      Color(0xFF059669),
    ];
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}

class BrandFonts {
  BrandFonts._();

  /// Headlines: geometric, technical and confident — suits an engineering/FM product.
  static TextStyle display({
    double fontSize = 32,
    FontWeight fontWeight = FontWeight.w800,
    Color color = Colors.white,
    double height = 1.08,
    double letterSpacing = -0.8,
    List<Shadow>? shadows,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        shadows: shadows,
      );

  /// Body copy stays on Poppins, the app-wide body font.
  static TextStyle body({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double height = 1.5,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.poppins(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
}

/// True when the platform asks for reduced motion; entry animations and auto-zoom are skipped.
bool brandReduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Deep indigo stage with two soft glows and a faint blueprint grid.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, this.child, this.showGrid = true, this.glowScale = 1});

  final Widget? child;
  final bool showGrid;
  final double glowScale;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: BoxDecoration(gradient: BrandColors.stageGradient)),
        Positioned(
          right: -160 * glowScale,
          top: -140 * glowScale,
          child: _Glow(size: 560 * glowScale, color: AppColors.primaryLight, alpha: 0.32),
        ),
        Positioned(
          left: -120 * glowScale,
          bottom: -180 * glowScale,
          child: _Glow(size: 500 * glowScale, color: AppColors.accent, alpha: 0.18),
        ),
        if (showGrid)
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: BlueprintGridPainter())),
          ),
        ?child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color, required this.alpha});
  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Faint engineering-drawing grid: minor lines, stronger major lines and intersection dots.
class BlueprintGridPainter extends CustomPainter {
  const BlueprintGridPainter({this.color = Colors.white, this.spacing = 28});

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = color.withValues(alpha: 0.035)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = color.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    final dot = Paint()..color = color.withValues(alpha: 0.16);
    var i = 0;
    for (double x = 0; x <= size.width; x += spacing, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 4 == 0 ? major : minor);
    }
    i = 0;
    for (double y = 0; y <= size.height; y += spacing, i++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 4 == 0 ? major : minor);
    }
    for (double x = 0; x <= size.width; x += spacing * 4) {
      for (double y = 0; y <= size.height; y += spacing * 4) {
        canvas.drawCircle(Offset(x, y), 1.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(BlueprintGridPainter old) => old.color != color || old.spacing != spacing;
}

/// Small pill label above a headline ("FACILITY MANAGEMENT · CMMS").
class BrandEyebrow extends StatelessWidget {
  const BrandEyebrow({super.key, required this.label, this.onDark = true, this.icon});

  final String label;
  final bool onDark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? AppColors.accentLight : AppColors.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.08) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: (onDark ? AppColors.accent : AppColors.primary).withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: fg)
          else
            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: fg)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: BrandFonts.body(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg, letterSpacing: 1.8, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Short indigo → amber underline that grows in.
class BrandAccentBar extends StatelessWidget {
  const BrandAccentBar({super.key, this.width = 84});
  final double width;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: brandReduceMotion(context) ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => Container(
        width: width * t,
        height: 4,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), gradient: BrandColors.accentBar),
      ),
    );
  }
}

/// Pill call-to-action. Primary: amber gradient with glow. Secondary: glass outline (for dark stages)
/// or indigo outline (for light surfaces). Grows slightly on hover.
class BrandCta extends StatefulWidget {
  const BrandCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.onDark = true,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool onDark;
  final bool expand;
  final bool loading;

  @override
  State<BrandCta> createState() => _BrandCtaState();
}

class _BrandCtaState extends State<BrandCta> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final fg = widget.primary ? AppColors.textPrimary : (widget.onDark ? Colors.white : AppColors.primary);
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (widget.icon != null)
          Icon(widget.icon, size: 19, color: fg),
        if (widget.loading || widget.icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: BrandFonts.body(fontSize: 15, fontWeight: FontWeight.w700, color: fg, height: 1.2, letterSpacing: 0.2),
          ),
        ),
      ],
    );

    final decoration = widget.primary
        ? BoxDecoration(
            gradient: BrandColors.ctaGradient,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: _hover ? 0.55 : 0.35),
                blurRadius: _hover ? 26 : 18,
                offset: const Offset(0, 8),
              ),
            ],
          )
        : BoxDecoration(
            color: widget.onDark
                ? Colors.white.withValues(alpha: _hover ? 0.18 : 0.08)
                : (_hover ? AppColors.surfaceAlt : Colors.white),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: widget.onDark ? Colors.white.withValues(alpha: 0.5) : AppColors.primary.withValues(alpha: 0.5),
            ),
          );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover && enabled ? 1.03 : 1,
        duration: const Duration(milliseconds: 140),
        child: Opacity(
          opacity: enabled || widget.loading ? 1 : 0.55,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: decoration,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: enabled ? widget.onPressed : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a card so it lifts and gains a glow on hover / focus (desktop & web).
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.builder, this.enabled = true, this.scale = 1.02});

  final Widget Function(BuildContext context, bool hovered) builder;
  final bool enabled;
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _hover;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.builder(context, active),
      ),
    );
  }
}

/// Fades and slides its child in once, optionally after a delay (staggered entrances).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.06),
    this.duration = const Duration(milliseconds: 550),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (brandReduceMotion(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(_t),
        child: widget.child,
      ),
    );
  }
}

/// Number that counts up from 0 to [value] when first shown or when it changes.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, required this.style, this.suffix = ''});

  final int value;
  final TextStyle style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: brandReduceMotion(context) ? value.toDouble() : 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}

/// Glass stat tile for dark stages: icon chip, count-up value, label.
class BrandStatTile extends StatelessWidget {
  const BrandStatTile({super.key, required this.icon, required this.label, this.value, this.text, this.color = AppColors.accentLight});

  final IconData icon;
  final String label;
  final int? value;
  final String? text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final valueStyle = BrandFonts.display(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.1);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null) CountUpText(value: value!, style: valueStyle) else Text(text ?? '—', style: valueStyle),
              Text(label, style: BrandFonts.body(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72), height: 1.3)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Search field styled for dark stages (glass) or light surfaces.
class BrandSearchField extends StatelessWidget {
  const BrandSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onDark = true,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppColors.textPrimary;
    final muted = onDark ? Colors.white.withValues(alpha: 0.6) : AppColors.textSecondary;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: BrandFonts.body(fontSize: 14, color: fg),
        cursorColor: onDark ? AppColors.accentLight : AppColors.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: BrandFonts.body(fontSize: 14, color: muted),
          prefixIcon: Icon(Icons.search_rounded, color: muted),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.close_rounded, color: muted),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: onDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: onDark ? Colors.white.withValues(alpha: 0.14) : AppColors.surfaceAlt),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: onDark ? Colors.white.withValues(alpha: 0.14) : const Color(0xFFE0E7FF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: onDark ? AppColors.accentLight : AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Rounded initials badge with a per-name colour.
class BrandMonogram extends StatelessWidget {
  const BrandMonogram({super.key, required this.name, this.size = 48});
  final String name;
  final double size;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = BrandColors.forName(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, Color.lerp(c, Colors.black, 0.25)!],
        ),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Text(
        _initials,
        style: BrandFonts.display(fontSize: size * 0.36, fontWeight: FontWeight.w800, letterSpacing: 0.2, height: 1),
      ),
    );
  }
}

/// One step in the "Organization → Facility → Dashboard" progress shown during selection.
class BrandStep {
  const BrandStep(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Compact progress indicator for the entry flow, readable on dark stages.
class BrandStepper extends StatelessWidget {
  const BrandStepper({super.key, required this.steps, required this.current, this.compact = false});

  final List<BrandStep> steps;
  final int current;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final done = i < current;
      final active = i == current;
      final color = active ? AppColors.accentLight : (done ? Colors.white : Colors.white.withValues(alpha: 0.45));
      children.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.accent : (done ? AppColors.primaryLight : Colors.white.withValues(alpha: 0.08)),
              border: Border.all(color: active ? AppColors.accentLight : Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(done ? Icons.check_rounded : steps[i].icon, size: 14, color: active ? AppColors.textPrimary : Colors.white),
          ),
          if (!compact || active) ...[
            const SizedBox(width: 8),
            Text(
              steps[i].label,
              style: BrandFonts.body(fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color, height: 1.2),
            ),
          ],
        ],
      ));
      if (i < steps.length - 1) {
        children.add(Container(
          width: compact ? 16 : 28,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: i < current ? AppColors.primaryLight : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(1),
          ),
        ));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Section header used on the light content area (title + optional trailing action).
class BrandSectionHeader extends StatelessWidget {
  const BrandSectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BrandFonts.display(fontSize: 19, color: AppColors.textPrimary, letterSpacing: -0.3)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: BrandFonts.body(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
