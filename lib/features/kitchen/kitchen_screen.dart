import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/food_emoji.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../../models/ingredient.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';

enum KitchenSort { name, expiry, category, quantity }

enum KitchenFilter { all, fresh, expiring, expired }

/// Pure filtering/sorting so it can be unit-tested.
List<Ingredient> applyKitchenView(List<Ingredient> items, {String query = '', KitchenFilter filter = KitchenFilter.all, String? category, KitchenSort sort = KitchenSort.expiry}) {
  final q = query.trim().toLowerCase();
  final out = items.where((i) {
    if (q.isNotEmpty && !i.name.toLowerCase().contains(q)) return false;
    if (category != null && i.category != category) return false;
    return switch (filter) {
      KitchenFilter.all => true,
      KitchenFilter.fresh => i.freshness() == Freshness.fresh || i.freshness() == Freshness.unknown,
      KitchenFilter.expiring => i.freshness() == Freshness.expiringSoon,
      KitchenFilter.expired => i.freshness() == Freshness.expired,
    };
  }).toList();
  int byName(Ingredient a, Ingredient b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  out.sort(switch (sort) {
    KitchenSort.name => byName,
    KitchenSort.expiry => (a, b) {
        final c = (a.daysLeft() ?? 9999).compareTo(b.daysLeft() ?? 9999);
        return c != 0 ? c : byName(a, b);
      },
    KitchenSort.category => (a, b) {
        final c = a.category.compareTo(b.category);
        return c != 0 ? c : byName(a, b);
      },
    KitchenSort.quantity => (a, b) => b.quantity.compareTo(a.quantity),
  });
  return out;
}

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  String _query = '';
  KitchenFilter _filter = KitchenFilter.all;
  String? _category;
  KitchenSort _sort = KitchenSort.expiry;

  Future<void> _delete(Ingredient i) async {
    final n = ref.read(ingredientsProvider.notifier);
    await n.remove(i);
    if (mounted) {
      showSnack(context, '${i.name} removed', action: 'UNDO', onAction: () => n.upsert(i));
    }
  }

  Future<void> _changeQty(Ingredient i, double delta) async {
    final step = (i.unit == 'g' || i.unit == 'ml') ? delta * 50 : delta;
    final q = (i.quantity + step);
    if (q <= 0) return _delete(i);
    await ref.read(ingredientsProvider.notifier).save(i.copyWith(quantity: double.parse(q.toStringAsFixed(2))));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ingredientsProvider);
    final all = async.value ?? const <Ingredient>[];
    final items = applyKitchenView(all, query: _query, filter: _filter, category: _category, sort: _sort);
    final counts = {
      KitchenFilter.all: all.length,
      KitchenFilter.fresh: applyKitchenView(all, filter: KitchenFilter.fresh).length,
      KitchenFilter.expiring: applyKitchenView(all, filter: KitchenFilter.expiring).length,
      KitchenFilter.expired: applyKitchenView(all, filter: KitchenFilter.expired).length,
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('My Kitchen'),
          const SizedBox(width: 10),
          if (ref.watch(sessionProvider).isDemo) const DemoBadge(),
        ]),
        actions: [
          PopupMenuButton<KitchenSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: KitchenSort.expiry, child: Text('Expiring first')),
              PopupMenuItem(value: KitchenSort.name, child: Text('Name A–Z')),
              PopupMenuItem(value: KitchenSort.category, child: Text('Category')),
              PopupMenuItem(value: KitchenSort.quantity, child: Text('Quantity')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ingredientsProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              sliver: SliverList.list(children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(hintText: 'Search ingredients', prefixIcon: Icon(Icons.search_rounded)),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in KitchenFilter.values) ...[
                      ChoiceChip(
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                        label: Text('${switch (f) {
                          KitchenFilter.all => 'All',
                          KitchenFilter.fresh => '🟢 Fresh',
                          KitchenFilter.expiring => '🟡 Expiring soon',
                          KitchenFilter.expired => '🔴 Expired',
                        }} (${counts[f]})'),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ]),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    FilterChip(label: const Text('All categories'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                    for (final c in AppConstants.categories) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text('${c.emoji} ${c.label}'),
                        selected: _category == c.id,
                        onSelected: (s) => setState(() => _category = s ? c.id : null),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
              ]),
            ),
            if (async.isLoading && all.isEmpty)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  emoji: all.isEmpty ? '🧺' : '🔍',
                  title: all.isEmpty ? 'Your kitchen is empty' : 'Nothing matches',
                  message: all.isEmpty ? 'Add the ingredients you have and Chef AI will suggest recipes.' : 'Try a different search or filter.',
                  action: all.isEmpty ? 'Add ingredient' : null,
                  onAction: () => context.push(Routes.addIngredient),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final ing = items[i];
                    return Dismissible(
                      key: ValueKey(ing.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(color: AppColors.expired, borderRadius: BorderRadius.circular(24)),
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) => _delete(ing),
                      child: _IngredientRow(
                        ingredient: ing,
                        onTap: () => context.push(Routes.addIngredient, extra: ing),
                        onMinus: () => _changeQty(ing, -1),
                        onPlus: () => _changeQty(ing, 1),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-ing',
        backgroundColor: AppColors.herb,
        foregroundColor: Colors.white,
        onPressed: () => context.push(Routes.addIngredient),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, required this.onTap, required this.onMinus, required this.onPlus});
  final Ingredient ingredient;
  final VoidCallback onTap, onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final cat = AppConstants.category(ingredient.category);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          IconChip(emoji: foodEmoji(ingredient.name, ingredient.category), color: cat.color, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ingredient.name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${ingredient.quantityLabel}${ingredient.unit == 'pieces' ? ' pieces' : ''} · ${cat.label}', style: context.text.bodySmall),
                const SizedBox(height: 6),
                FreshnessBadge(ingredient),
              ],
            ),
          ),
          _StepButton(icon: Icons.remove_rounded, onTap: onMinus, label: 'Decrease ${ingredient.name}'),
          _StepButton(icon: Icons.add_rounded, onTap: onPlus, label: 'Increase ${ingredient.name}'),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: context.palette.border.withValues(alpha: 0.5),
        ),
      );
}
