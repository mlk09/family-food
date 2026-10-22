import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../routes/app_router.dart';
import 'widgets/brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void initState() {
    super.initState();
    // Short, purely cosmetic splash — data is already loading from cache.
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) context.go(Routes.home); // router redirects to auth if needed
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackground(
        child: Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
            child: FadeTransition(
              opacity: _c,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BrandLogo(size: 96),
                const SizedBox(height: 22),
                const BrandTitle(),
                const SizedBox(height: 8),
                Text("Your family's smart kitchen assistant", style: TextStyle(color: context.palette.muted, fontSize: 15)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
