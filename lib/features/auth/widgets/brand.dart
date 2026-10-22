import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [BoxShadow(color: AppColors.tomato.withValues(alpha: 0.45), blurRadius: size * 0.45, offset: Offset(0, size * 0.12))],
      ),
      child: Text('🍳', style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Family', style: TextStyle(color: context.colors.onSurface)),
        const TextSpan(text: 'Food', style: TextStyle(color: AppColors.saffron)),
      ]),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.5),
    );
  }
}

/// Warm radial glow background used on splash/auth screens.
class BrandBackground extends StatelessWidget {
  const BrandBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.9),
          radius: 1.2,
          colors: dark
              ? [const Color(0xFF3A1D24), const Color(0xFF1A1220), AppColors.darkBg]
              : [const Color(0xFFFFE2CC), const Color(0xFFFFF1E6), AppColors.lightBg],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: child,
    );
  }
}
