import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../data/session.dart';
import 'app_router.dart';

/// Bottom navigation (Home, My Kitchen, Meal Plan, Shopping, Profile) with the
/// floating 🤖 Chef AI button.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_rounded, Icons.home_outlined, 'Home'),
    (Icons.kitchen_rounded, Icons.kitchen_outlined, 'My Kitchen'),
    (Icons.calendar_month_rounded, Icons.calendar_month_outlined, 'Meal Plan'),
    (Icons.shopping_basket_rounded, Icons.shopping_basket_outlined, 'Shopping'),
    (Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityProvider).value == false;
    return Scaffold(
      body: Column(
        children: [
          if (offline)
            Material(
              color: AppColors.expiring,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(children: const [
                    Icon(Icons.cloud_off_rounded, size: 18, color: Colors.black87),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text("Offline — changes are saved and will sync later",
                          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ]),
                ),
              ),
            ),
          Expanded(child: shell),
        ],
      ),
      floatingActionButton: _ChefFab(onTap: () => context.push(Routes.chef)),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF120F18) : Colors.white,
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _NavItem(
                      selected: shell.currentIndex == i,
                      icon: shell.currentIndex == i ? _tabs[i].$1 : _tabs[i].$2,
                      label: _tabs[i].$3,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        shell.goBranch(i, initialLocation: i == shell.currentIndex);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.selected, required this.icon, required this.label, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.saffron : context.palette.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? AppColors.saffron.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 25),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontSize: 11.5, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ChefFab extends StatefulWidget {
  const _ChefFab({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ChefFab> createState() => _ChefFabState();
}

class _ChefFabState extends State<_ChefFab> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask Chef AI',
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppColors.tomato.withValues(alpha: 0.25 + 0.2 * _c.value), blurRadius: 18 + 10 * _c.value, spreadRadius: 1),
            ],
          ),
          child: child,
        ),
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(gradient: AppColors.aiGradient, shape: BoxShape.circle),
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onTap();
              },
              child: const Center(child: Text('🤖', style: TextStyle(fontSize: 30))),
            ),
          ),
        ),
      ),
    );
  }
}
