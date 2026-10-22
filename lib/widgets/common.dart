import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../models/ingredient.dart';

/// Rounded card with a hairline border, the base surface of the app.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color, this.gradient, this.radius = 24, this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? context.palette.card) : null,
          gradient: gradient,
          borderRadius: r,
          border: Border.all(color: borderColor ?? context.palette.border),
        ),
        child: InkWell(
          borderRadius: r,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small rounded square holding an icon/emoji on a tinted background.
class IconChip extends StatelessWidget {
  const IconChip({super.key, this.icon, this.emoji, required this.color, this.size = 44});
  final IconData? icon;
  final String? emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: emoji != null
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.48))
          : Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Dashboard tile: icon, label, big value and a hint — like the video's grid.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, required this.hint, required this.color, this.icon, this.emoji, this.onTap, this.progress});
  final String label, value, hint;
  final Color color;
  final IconData? icon;
  final String? emoji;
  final VoidCallback? onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconChip(icon: icon, emoji: emoji, color: color, size: 40),
          const SizedBox(height: 14),
          Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 5,
                backgroundColor: context.palette.border,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Large, high-contrast gradient call-to-action (≥ 60px tall for elderly users).
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.gradient = AppColors.primaryGradient, this.height = 60, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final double height;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.tomato.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      onPressed!();
                    }
                  : null,
              child: Center(
                child: loading
                    ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[Icon(icon, color: Colors.white, size: 24), const SizedBox(width: 10)],
                          Flexible(
                            child: Text(label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.emoji});
  final String title;
  final String? emoji;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 20)), const SizedBox(width: 8)],
          Expanded(child: Text(title, style: context.text.titleLarge)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Circular progress ring with centred label (hero card).
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.center, this.caption, this.size = 92, this.color = AppColors.saffron});
  final double value;
  final String center;
  final String? caption;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(v, color, context.palette.border),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1)),
                if (caption != null)
                  Text(caption!, style: context.text.bodySmall?.copyWith(fontSize: 10.5), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track);
  final double v;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..shader = SweepGradient(colors: [color, AppColors.tomato, color], transform: const GradientRotation(-math.pi / 2))
          .createShader(Rect.fromCircle(center: c, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color || old.track != track;
}

class FreshnessBadge extends StatelessWidget {
  const FreshnessBadge(this.ingredient, {super.key, this.compact = false});
  final Ingredient ingredient;
  final bool compact;

  static (Color, String, String) info(Ingredient i) {
    final d = i.daysLeft();
    return switch (i.freshness()) {
      Freshness.fresh => (AppColors.fresh, '🟢', 'Fresh · $d days'),
      Freshness.expiringSoon => (AppColors.expiring, '🟡', d == 0 ? 'Expires today' : 'Expires in $d day${d == 1 ? '' : 's'}'),
      Freshness.expired => (AppColors.expired, '🔴', 'Expired'),
      Freshness.unknown => (AppColors.darkMuted, '⚪', 'No expiry date'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (color, dot, label) = info(ingredient);
    if (compact) return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, required this.message, this.action, this.onAction});
  final String emoji, title, message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: context.text.bodyMedium?.copyWith(color: context.palette.muted), textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add_rounded), label: Text(action!)),
          ],
        ],
      ),
    );
  }
}

/// Animated loading placeholder.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.height = 120, this.radius = 22});
  final double height, radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.palette.card;
    final hi = context.isDark ? const Color(0xFF2A2333) : const Color(0xFFFFEBDD);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: context.palette.border),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + 3 * _c.value, 0),
            end: Alignment(-0.5 + 3 * _c.value, 0),
            colors: [base, hi, base],
          ),
        ),
      ),
    );
  }
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.turmeric.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.turmeric.withValues(alpha: 0.5)),
      ),
      child: const Text('DEMO DATA', style: TextStyle(color: AppColors.turmeric, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.8)),
    );
  }
}

class SafetyBanner extends StatelessWidget {
  const SafetyBanner(this.message, {super.key, this.big = false});
  final String message;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(big ? 16 : 12),
      decoration: BoxDecoration(
        color: AppColors.expiring.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.expiring.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🛡️', style: TextStyle(fontSize: big ? 24 : 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(fontSize: big ? 18 : 14, height: 1.35, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// Very small markdown subset for chat: **bold**, _italic_, bullet lines.
class RichMessage extends StatelessWidget {
  const RichMessage(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? context.text.bodyLarge!;
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|(?<![\w])_(.+?)_(?![\w])');
    var last = 0;
    final t = text.replaceAll(RegExp(r'^#{1,4}\s*', multiLine: true), '').replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
    for (final m in re.allMatches(t)) {
      if (m.start > last) spans.add(TextSpan(text: t.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        spans.add(TextSpan(text: m.group(2), style: TextStyle(fontStyle: FontStyle.italic, color: context.palette.muted)));
      }
      last = m.end;
    }
    if (last < t.length) spans.add(TextSpan(text: t.substring(last)));
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}

void showSnack(BuildContext context, String message, {String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: action == null ? null : SnackBarAction(label: action, textColor: AppColors.turmeric, onPressed: onAction ?? () {}),
    ));
}
