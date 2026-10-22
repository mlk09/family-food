import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/food_emoji.dart';
import '../../core/utils/id.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../../models/shopping_item.dart';
import '../../widgets/common.dart';

/// Groups items into the shopping sections, in store-walk order (pure, tested).
Map<String, List<ShoppingItem>> groupShopping(List<ShoppingItem> items) {
  String groupOf(ShoppingItem i) => AppConstants.shoppingGroups.contains(i.category) ? i.category : 'other';
  return {
    for (final g in AppConstants.shoppingGroups)
      if (items.any((i) => groupOf(i) == g)) g: items.where((i) => groupOf(i) == g).toList(),
  };
}

class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _quick = TextEditingController();

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  Future<void> _quickAdd() async {
    final t = _quick.text.trim();
    if (t.isEmpty) return;
    _quick.clear();
    final names = t.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final n = await ref.read(shoppingProvider.notifier).addNames(names);
    if (mounted && n == 0) showSnack(context, 'Already on your list 👍');
  }

  Future<void> _edit([ShoppingItem? existing]) async {
    final result = await showModalBottomSheet<ShoppingItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemSheet(existing: existing),
    );
    if (result != null) await ref.read(shoppingProvider.notifier).save(result);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingProvider).value ?? const <ShoppingItem>[];
    final done = items.where((i) => i.checked).length;
    final groups = groupShopping(items);
    final n = ref.read(shoppingProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Shopping List'),
          const SizedBox(width: 10),
          if (ref.watch(sessionProvider).isDemo) const DemoBadge(),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'kitchen') {
                final moved = await n.moveCheckedToKitchen();
                if (context.mounted) showSnack(context, moved == 0 ? 'Tick the items you bought first' : '🧺 Moved $moved items to My Kitchen');
              } else if (v == 'clear') {
                await n.clearChecked();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'kitchen', child: Text('🧺 Move bought items to My Kitchen')),
              PopupMenuItem(value: 'clear', child: Text('🗑️ Clear bought items')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => n.refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _quick,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _quickAdd(),
                  decoration: const InputDecoration(hintText: 'Add items, e.g. "milk, bread"', prefixIcon: Icon(Icons.add_rounded)),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Add with details',
                style: IconButton.styleFrom(backgroundColor: AppColors.herb, minimumSize: const Size(56, 56)),
                onPressed: () => _edit(),
                icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
              ),
            ]),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  ProgressRing(value: items.isEmpty ? 0 : done / items.length, center: '$done/${items.length}', size: 64, color: AppColors.herb),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(done == items.length ? 'All done! 🎉' : '${items.length - done} items to buy', style: context.text.titleMedium),
                      Text(done > 0 ? 'Tap ⋮ to move bought items into your kitchen' : 'Shared with your family', style: context.text.bodySmall),
                    ]),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            if (items.isEmpty)
              const EmptyState(emoji: '🛒', title: 'Your list is empty', message: 'Add items above, or tap "Add missing" on any recipe.'),
            for (final e in groups.entries) ...[
              SectionHeader(AppConstants.category(e.key).label, emoji: AppConstants.category(e.key).emoji),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final (idx, item) in e.value.indexed) ...[
                    if (idx > 0) const Divider(indent: 64),
                    Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: AppColors.expired,
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        n.remove(item);
                        showSnack(context, '${item.name} removed', action: 'UNDO', onAction: () => n.upsert(item));
                      },
                      child: _ItemRow(item: item, onToggle: () => n.toggle(item), onTap: () => _edit(item)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onToggle, required this.onTap});
  final ShoppingItem item;
  final VoidCallback onToggle, onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Transform.scale(
            scale: 1.3,
            child: Checkbox(
              value: item.checked,
              onChanged: (_) => onToggle(),
              activeColor: AppColors.herb,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 4),
          Text(foodEmoji(item.name, item.category), style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                item.name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: item.checked ? TextDecoration.lineThrough : null,
                  color: item.checked ? muted : null,
                ),
              ),
              if (item.quantity.isNotEmpty || item.recipeName != null)
                Text([if (item.quantity.isNotEmpty) item.quantity, if (item.recipeName != null) 'for ${item.recipeName}'].join(' · '),
                    style: context.text.bodySmall),
            ]),
          ),
          if (item.priority == 2) const Padding(padding: EdgeInsets.only(right: 8), child: Text('🔥', style: TextStyle(fontSize: 18))),
          if (item.priority == 0) Padding(padding: const EdgeInsets.only(right: 8), child: Text('later', style: context.text.bodySmall)),
        ]),
      ),
    );
  }
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({this.existing});
  final ShoppingItem? existing;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _qty = TextEditingController(text: widget.existing?.quantity ?? '');
  late String _category = widget.existing?.category ?? 'vegetables';
  late int _priority = widget.existing?.priority ?? 1;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text(widget.existing == null ? 'Add item' : 'Edit item', style: context.text.headlineSmall),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) {
            final c = IngredientMatcher.categoryFor(v);
            if (c != 'other') setState(() => _category = AppConstants.shoppingGroups.contains(c) ? c : 'other');
          },
          decoration: const InputDecoration(labelText: 'Item name'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Quantity', hintText: 'e.g. 2 kg, 1 packet')),
        const SizedBox(height: 16),
        Text('Category', style: context.text.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in AppConstants.shoppingGroups)
            ChoiceChip(
              label: Text('${AppConstants.category(g).emoji} ${AppConstants.category(g).label}'),
              selected: _category == g,
              onSelected: (_) => setState(() => _category = g),
            ),
        ]),
        const SizedBox(height: 16),
        Text('Priority', style: context.text.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Later')),
            ButtonSegment(value: 1, label: Text('Normal')),
            ButtonSegment(value: 2, label: Text('🔥 Urgent')),
          ],
          selected: {_priority},
          onSelectionChanged: (s) => setState(() => _priority = s.first),
        ),
        const SizedBox(height: 20),
        GradientButton(
          label: widget.existing == null ? 'Add to list' : 'Save',
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final base = widget.existing ?? ShoppingItem(id: newId(), name: name);
            Navigator.pop(
              context,
              base.copyWith(name: name[0].toUpperCase() + name.substring(1), quantity: _qty.text.trim(), category: _category, priority: _priority),
            );
          },
        ),
      ]),
    );
  }
}
