import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/recipe.dart';
import 'common.dart';

/// Recipe artwork: real photo when available, otherwise a rich gradient
/// "plate" with the dish emoji. Never a broken image.
class RecipeArt extends StatelessWidget {
  const RecipeArt({super.key, required this.recipe, this.height = 150, this.radius = 22, this.emojiSize = 64, this.heroTag});
  final Recipe recipe;
  final double height, radius, emojiSize;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final g = AppColors.gradientFor(recipe.name);
    Widget art = Container(
      height: height,
      decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(radius)),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: height * 0.8,
              height: height * 0.8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.13)),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -40,
            child: Container(
              width: height * 0.9,
              height: height * 0.9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.06)),
            ),
          ),
          Center(
            child: Container(
              width: emojiSize * 1.6,
              height: emojiSize * 1.6,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.25),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Text(recipe.emoji, style: TextStyle(fontSize: emojiSize)),
            ),
          ),
          if (recipe.imageUrl != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Image.network(recipe.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
              ),
            ),
        ],
      ),
    );
    if (heroTag != null) art = Hero(tag: heroTag!, child: art);
    return art;
  }
}

class MetaPill extends StatelessWidget {
  const MetaPill({super.key, required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: c),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13.5)),
    ]);
  }
}

/// Suggestion card used on "What Can I Cook?".
class RecipeCard extends StatelessWidget {
  const RecipeCard({super.key, required this.recipe, required this.used, required this.missing, required this.onTap, this.badge});
  final Recipe recipe;
  final List<String> used, missing;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(children: [
            RecipeArt(recipe: recipe, height: 140, radius: 18, emojiSize: 52, heroTag: 'art-${recipe.id}'),
            if (badge != null)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
                  child: Text(badge!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${recipe.emoji} ${recipe.name}', style: context.text.titleLarge),
                if (recipe.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(recipe.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  MetaPill(icon: Icons.schedule_rounded, label: '${recipe.totalTime} min'),
                  MetaPill(icon: Icons.signal_cellular_alt_rounded, label: recipe.difficulty),
                  MetaPill(icon: Icons.people_alt_rounded, label: 'Serves ${recipe.servings}'),
                ]),
                if (used.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final u in used.take(5)) _IngTag('✓ $u', AppColors.fresh),
                    for (final m in missing.take(3)) _IngTag('+ $m', AppColors.expiring),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IngTag extends StatelessWidget {
  const _IngTag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(9)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
      );
}
