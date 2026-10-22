import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/food_emoji.dart';
import '../../core/utils/id.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../core/utils/validators.dart';
import '../../data/providers.dart';
import '../../models/ingredient.dart';
import '../../widgets/common.dart';
import '../ai/ai_providers.dart';

class AddIngredientScreen extends ConsumerStatefulWidget {
  const AddIngredientScreen({super.key, this.existing, this.startScan = false});
  final Ingredient? existing;
  final bool startScan;

  @override
  ConsumerState<AddIngredientScreen> createState() => _AddIngredientScreenState();
}

class _AddIngredientScreenState extends ConsumerState<AddIngredientScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _qty = TextEditingController(text: _fmt(widget.existing?.quantity ?? 1));
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String _unit = widget.existing?.unit ?? 'pieces';
  late String _category = widget.existing?.category ?? 'vegetables';
  late DateTime? _purchase = widget.existing?.purchaseDate ?? DateTime.now();
  late DateTime? _expiry = widget.existing?.expiryDate;
  bool _categoryTouched = false;
  bool _scanning = false;

  bool get _editing => widget.existing != null;

  static const _quick = ['Potato', 'Tomato', 'Onion', 'Eggs', 'Rice', 'Milk', 'Paneer', 'Spinach', 'Chicken', 'Bread', 'Banana', 'Curd'];

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    if (widget.startScan) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onNameChanged(String v) {
    if (_categoryTouched) return;
    final c = IngredientMatcher.categoryFor(v);
    if (c != 'other' && c != _category) setState(() => _category = c);
  }

  Future<void> _pickDate(bool expiry) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (expiry ? _expiry : _purchase) ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => expiry ? _expiry = d : _purchase = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final base = widget.existing ?? Ingredient(id: newId(), name: '');
    final item = Ingredient(
      id: base.id,
      userId: base.userId,
      familyId: base.familyId,
      name: _name.text.trim()[0].toUpperCase() + _name.text.trim().substring(1),
      quantity: double.parse(_qty.text.trim()),
      unit: _unit,
      category: _category,
      purchaseDate: _purchase,
      expiryDate: _expiry,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      updatedAt: DateTime.now(),
    );
    await ref.read(ingredientsProvider.notifier).save(item);
    if (!mounted) return;
    showSnack(context, _editing ? '✅ ${item.name} updated' : '✅ ${item.name} added to your kitchen');
    context.pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${widget.existing!.name}?'),
        content: const Text('This removes it from your kitchen for everyone in your family.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expired),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ingredientsProvider.notifier).remove(widget.existing!);
    if (mounted) context.pop();
  }

  /// 📷 Scan Ingredients: photo → Edge Function (vision) → confirm list.
  Future<void> _scan() async {
    final ai = ref.read(aiServiceProvider);
    if (!ai.isAvailable) {
      showSnack(context, '📷 Photo scanning needs the cloud AI backend. Add your Supabase keys to enable it (see README).');
      return;
    }
    // Always ask: on phones (app or browser) "camera" opens the rear camera directly.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Photo kaise doge?', style: c.text.titleLarge),
            const SizedBox(height: 12),
            GradientButton(
              label: '📷  Camera se photo lo',
              onPressed: () => Navigator.pop(c, ImageSource.camera),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(c, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Gallery se chuno'),
            ),
          ]),
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (file == null) return;
      setState(() => _scanning = true);
      final names = await ai.scanIngredients(await file.readAsBytes());
      if (!mounted) return;
      setState(() => _scanning = false);
      if (names.isEmpty) {
        showSnack(context, "Chef AI couldn't spot any food in that photo. Try a clearer, closer picture.");
        return;
      }
      await _confirmScanned(names);
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        showSnack(context, friendlyError(e));
      }
    }
  }

  Future<void> _confirmScanned(List<String> names) async {
    final selected = names.toSet();
    final add = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Chef AI spotted ${names.length} items', style: c.text.titleLarge),
              const SizedBox(height: 4),
              Text('Untick anything that is wrong. AI can make mistakes.', style: c.text.bodySmall),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.5),
                child: ListView(shrinkWrap: true, children: [
                  for (final n in names)
                    CheckboxListTile(
                      value: selected.contains(n),
                      onChanged: (v) => set(() => v! ? selected.add(n) : selected.remove(n)),
                      title: Text('${foodEmoji(n)}  $n'),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              GradientButton(label: 'Add ${selected.length} to kitchen', onPressed: selected.isEmpty ? null : () => Navigator.pop(c, true)),
            ]),
          ),
        ),
      ),
    );
    if (add != true) return;
    final now = DateTime.now();
    await ref.read(ingredientsProvider.notifier).addOrMerge([
      for (final n in selected)
        Ingredient(
          id: newId(),
          name: n[0].toUpperCase() + n.substring(1),
          category: IngredientMatcher.categoryFor(n),
          purchaseDate: now,
          notes: 'Added by photo scan',
        ),
    ]);
    if (!mounted) return;
    showSnack(context, '✅ Added ${selected.length} ingredients');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Ingredient' : 'Add Ingredient'),
        actions: [
          if (_editing) IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expired)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
          children: [
            if (!_editing) ...[
              AppCard(
                onTap: _scanning ? null : _scan,
                gradient: LinearGradient(colors: [AppColors.sky.withValues(alpha: 0.18), AppColors.berry.withValues(alpha: 0.14)]),
                child: Row(children: [
                  const IconChip(icon: Icons.photo_camera_rounded, color: AppColors.sky, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('📷 Scan Ingredients', style: context.text.titleMedium),
                      Text('Snap your fridge or groceries — Chef AI lists them', style: context.text.bodySmall),
                    ]),
                  ),
                  if (_scanning) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)) else const Icon(Icons.chevron_right_rounded),
                ]),
              ),
              const SizedBox(height: 18),
              Text('Quick add', style: context.text.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text('${foodEmoji(q)} $q'),
                    onPressed: () {
                      _name.text = q;
                      _onNameChanged(q);
                      if (q == 'Rice') setState(() => _unit = 'kg');
                      if (q == 'Milk') setState(() => _unit = 'litre');
                      if (q == 'Paneer' || q == 'Curd') setState(() => _unit = 'g');
                    },
                  ),
              ]),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onNameChanged,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'Ingredient name', hintText: 'e.g. Tomato', prefixIcon: Icon(Icons.eco_outlined)),
              validator: Validators.ingredientName,
            ),
            const SizedBox(height: 16),
            Row(children: [
              IconButton.filledTonal(
                iconSize: 28,
                onPressed: () {
                  final v = double.tryParse(_qty.text) ?? 1;
                  if (v > 1) _qty.text = _fmt(v - 1);
                },
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _qty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  validator: Validators.quantity,
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                iconSize: 28,
                onPressed: () => _qty.text = _fmt((double.tryParse(_qty.text) ?? 0) + 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Unit', style: context.text.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final u in AppConstants.units) ChoiceChip(label: Text(u), selected: _unit == u, onSelected: (_) => setState(() => _unit = u)),
            ]),
            const SizedBox(height: 18),
            Text('Category', style: context.text.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in AppConstants.categories)
                ChoiceChip(
                  label: Text('${c.emoji} ${c.label}'),
                  selected: _category == c.id,
                  onSelected: (_) => setState(() {
                    _category = c.id;
                    _categoryTouched = true;
                  }),
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: _DateField(label: 'Purchased', value: _purchase == null ? 'Not set' : df.format(_purchase!), onTap: () => _pickDate(false)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: 'Expires',
                  value: _expiry == null ? 'Not set' : df.format(_expiry!),
                  onTap: () => _pickDate(true),
                  onClear: _expiry == null ? null : () => setState(() => _expiry = null),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final d in const [(3, '3 days'), (7, '1 week'), (14, '2 weeks'), (30, '1 month')])
                ActionChip(
                  label: Text('⏳ ${d.$2}'),
                  onPressed: () => setState(() => _expiry = DateTime.now().add(Duration(days: d.$1))),
                ),
            ]),
            const SizedBox(height: 18),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. Top shelf of the fridge'),
            ),
            const SizedBox(height: 12),
            GradientButton(label: _editing ? 'Save changes' : 'Add to My Kitchen', icon: Icons.check_rounded, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.onClear});
  final String label, value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        radius: 16,
        child: Row(children: [
          const Icon(Icons.event_rounded, size: 20, color: AppColors.saffron),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: context.text.bodySmall),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          if (onClear != null) IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18), tooltip: 'Clear'),
        ]),
      );
}
