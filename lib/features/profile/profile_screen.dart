import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/env.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_error.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../../data/settings.dart';
import '../../models/profile.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profile = ref.watch(profileProvider).value ?? UserProfile(id: session.ownerId);
    final family = ref.watch(familyProvider).value;
    final theme = ref.watch(themeModeProvider);
    final notif = ref.watch(notificationPrefsProvider);
    final notifN = ref.read(notificationPrefsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
        children: [
          // ── Header ──
          AppCard(
            gradient: LinearGradient(colors: [AppColors.saffron.withValues(alpha: 0.18), AppColors.tomato.withValues(alpha: 0.10)]),
            child: Row(children: [
              _Avatar(profile: profile, canUpload: session.isCloud),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile.name.isEmpty ? 'Add your name' : profile.name, style: context.text.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    session.isDemo ? 'Demo Mode · data stays on this device' : (session.email ?? 'Signed in'),
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text('🔥 ${profile.currentStreak()} day streak · ${AppConstants.ageGroupLabels[profile.ageGroup] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Edit food profile',
            icon: Icons.edit_rounded,
            height: 56,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _EditProfileSheet(profile: profile),
            ),
          ),
          const SizedBox(height: 16),

          // ── Food profile summary ──
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SummaryRow('🥗', 'Diet', AppConstants.dietLabels[profile.diet] ?? profile.diet),
              _SummaryRow('🌶️', 'Spice', AppConstants.spiceLevels[profile.spiceLevel]),
              _SummaryRow('😋', 'Favourites', profile.favoriteFoods.isEmpty ? '—' : profile.favoriteFoods.join(', ')),
              _SummaryRow('🙅', 'Dislikes', profile.dislikedFoods.isEmpty ? '—' : profile.dislikedFoods.join(', ')),
              _SummaryRow('🍜', 'Preferences', profile.foodPreferences.isEmpty ? '—' : profile.foodPreferences.join(', ')),
              _SummaryRow('⚠️', 'Allergies', profile.allergies.isEmpty ? 'None added' : profile.allergies.join(', ')),
              if (profile.allergies.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SafetyBanner(AppConstants.allergyWarning),
              ],
            ]),
          ),

          const SizedBox(height: 18),
          const SectionHeader('Family & recipes', emoji: '👨‍👩‍👧'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                minTileHeight: 64,
                leading: const IconChip(emoji: '🏠', color: AppColors.herb, size: 40),
                title: Text(family?.name ?? 'Create or join a family'),
                subtitle: Text(family == null ? 'Share kitchen, list & plan' : '${family.members.length} members'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.family),
              ),
              const Divider(indent: 72),
              ListTile(
                minTileHeight: 64,
                leading: const IconChip(emoji: '❤️', color: AppColors.tomato, size: 40),
                title: const Text('Saved recipes'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.saved),
              ),
            ]),
          ),

          const SizedBox(height: 18),
          const SectionHeader('Appearance', emoji: '🎨'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {theme},
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
          ),

          const SizedBox(height: 18),
          const SectionHeader('Notifications', emoji: '🔔'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              SwitchListTile(
                value: notif.expiry,
                onChanged: (v) => notifN.update(notif.copyWith(expiry: v)),
                title: const Text('🍅 Ingredient expiry'),
                subtitle: const Text('"Your tomatoes may expire soon"'),
              ),
              SwitchListTile(
                value: notif.meals,
                onChanged: (v) => notifN.update(notif.copyWith(meals: v)),
                title: const Text('🍽️ Meal reminders'),
                subtitle: const Text('30 min before breakfast, lunch & dinner'),
              ),
              SwitchListTile(
                value: notif.shopping,
                onChanged: (v) => notifN.update(notif.copyWith(shopping: v)),
                title: const Text('🛒 Shopping reminders'),
              ),
              SwitchListTile(
                value: notif.plan,
                onChanged: (v) => notifN.update(notif.copyWith(plan: v)),
                title: const Text('📅 Weekly plan reminder'),
                subtitle: const Text('Sundays at 6 PM'),
              ),
            ]),
          ),

          const SizedBox(height: 18),
          const SectionHeader('Account', emoji: '🔐'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (session.isDemo)
                ListTile(
                  minTileHeight: 60,
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Reset demo data'),
                  onTap: () async {
                    await ref.read(sessionProvider.notifier).resetDemo();
                    if (context.mounted) showSnack(context, 'Demo data restored');
                  },
                ),
              if (session.isDemo && Env.isSupabaseConfigured)
                ListTile(
                  minTileHeight: 60,
                  leading: const Icon(Icons.person_add_alt_rounded, color: AppColors.saffron),
                  title: const Text('Create a real account'),
                  subtitle: const Text('Sync with your family across devices'),
                  onTap: () => ref.read(sessionProvider.notifier).signOut(),
                ),
              ListTile(
                minTileHeight: 60,
                leading: const Icon(Icons.logout_rounded),
                title: Text(session.isDemo ? 'Exit demo mode' : 'Log out'),
                onTap: () => ref.read(sessionProvider.notifier).signOut(),
              ),
              if (session.isCloud)
                ListTile(
                  minTileHeight: 60,
                  leading: const Icon(Icons.delete_forever_rounded, color: AppColors.expired),
                  title: const Text('Delete account', style: TextStyle(color: AppColors.expired)),
                  subtitle: const Text('Permanently removes your data'),
                  onTap: () => _confirmDelete(context, ref),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppConstants.appName} · v1.0.0\nRecipes and nutrition are estimates, not medical advice.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This permanently deletes your profile, kitchen, recipes, plans and chats. This cannot be undone.'),
          const SizedBox(height: 14),
          TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expired),
            onPressed: () => Navigator.pop(c, ctl.text.trim().toUpperCase() == 'DELETE'),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (ok != true) return;
    try {
      await ref.read(authServiceProvider).deleteAccount();
      await ref.read(localStoreProvider).clearNamespace();
      await ref.read(sessionProvider.notifier).signOut();
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e));
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.emoji, this.label, this.value);
  final String emoji, label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 30, child: Text(emoji, style: const TextStyle(fontSize: 18))),
          SizedBox(width: 100, child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
        ]),
      );
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.profile, required this.canUpload});
  final UserProfile profile;
  final bool canUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: !canUpload
          ? null
          : () async {
              try {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
                if (f == null) return;
                final ext = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
                final url = await ref.read(profileProvider.notifier).uploadAvatar(await f.readAsBytes(), ext);
                if (url != null) await ref.read(profileProvider.notifier).save(profile.copyWith(avatarUrl: url));
              } catch (e) {
                if (context.mounted) showSnack(context, friendlyError(e));
              }
            },
      child: Stack(children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: AppColors.saffron,
          backgroundImage: profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
          child: profile.avatarUrl == null
              ? Text(profile.firstName[0].toUpperCase(), style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w800))
              : null,
        ),
        if (canUpload)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: context.palette.card, shape: BoxShape.circle, border: Border.all(color: context.palette.border)),
              child: const Icon(Icons.photo_camera_rounded, size: 14),
            ),
          ),
      ]),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.profile.name);
  late String _age = widget.profile.ageGroup;
  late String _diet = widget.profile.diet;
  late double _spice = widget.profile.spiceLevel.toDouble();
  late List<String> _prefs = [...widget.profile.foodPreferences];
  late List<String> _allergies = [...widget.profile.allergies];
  late List<String> _fav = [...widget.profile.favoriteFoods];
  late List<String> _dislike = [...widget.profile.dislikedFoods];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
        Text('Your food profile', style: context.text.headlineSmall),
        const SizedBox(height: 4),
        Text('Chef AI uses this to personalise every suggestion.', style: context.text.bodySmall),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: _age == 'child' ? 'Nickname' : 'Name'),
        ),
        const SizedBox(height: 18),
        Text('Age group', style: context.text.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in AppConstants.ageGroups)
            ChoiceChip(label: Text(AppConstants.ageGroupLabels[a]!), selected: _age == a, onSelected: (_) => setState(() => _age = a)),
        ]),
        if (_age == 'child') ...[
          const SizedBox(height: 10),
          const SafetyBanner('For children we only keep a nickname and age group — no birthday, photo or contact details. '
              'Cooking steps will always remind them to ask a grown-up for help.'),
        ],
        const SizedBox(height: 18),
        Text('Diet', style: context.text.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in AppConstants.diets) ChoiceChip(label: Text(AppConstants.dietLabels[d]!), selected: _diet == d, onSelected: (_) => setState(() => _diet = d)),
        ]),
        const SizedBox(height: 18),
        Text('Spice preference: ${AppConstants.spiceLevels[_spice.round()]}', style: context.text.titleMedium),
        Slider(value: _spice, min: 0, max: 4, divisions: 4, label: AppConstants.spiceLevels[_spice.round()], onChanged: (v) => setState(() => _spice = v)),
        _ChipEditor(label: '🍜 Food preferences', hint: 'e.g. South Indian, quick meals', values: _prefs, onChanged: (v) => setState(() => _prefs = v)),
        _ChipEditor(label: '😋 Favourite foods', hint: 'e.g. paneer', values: _fav, onChanged: (v) => setState(() => _fav = v)),
        _ChipEditor(label: '🙅 Disliked foods', hint: 'e.g. bitter gourd', values: _dislike, onChanged: (v) => setState(() => _dislike = v)),
        _ChipEditor(label: '⚠️ Allergies', hint: 'e.g. peanuts, dairy, gluten', values: _allergies, onChanged: (v) => setState(() => _allergies = v)),
        const SafetyBanner(AppConstants.allergyWarning),
        const SizedBox(height: 20),
        GradientButton(
          label: 'Save profile',
          icon: Icons.check_rounded,
          onPressed: () async {
            await ref.read(profileProvider.notifier).save(widget.profile.copyWith(
                  name: _name.text.trim(),
                  ageGroup: _age,
                  diet: _diet,
                  spiceLevel: _spice.round(),
                  foodPreferences: _prefs,
                  allergies: _allergies,
                  favoriteFoods: _fav,
                  dislikedFoods: _dislike,
                ));
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}

class _ChipEditor extends StatefulWidget {
  const _ChipEditor({required this.label, required this.hint, required this.values, required this.onChanged});
  final String label, hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ChipEditor> createState() => _ChipEditorState();
}

class _ChipEditorState extends State<_ChipEditor> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _add() {
    final parts = _c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty && !widget.values.contains(e));
    if (parts.isEmpty) return;
    widget.onChanged([...widget.values, ...parts]);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: context.text.titleMedium),
          const SizedBox(height: 8),
          if (widget.values.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in widget.values)
                InputChip(label: Text(v), onDeleted: () => widget.onChanged(widget.values.where((e) => e != v).toList())),
            ]),
          const SizedBox(height: 8),
          TextField(
            controller: _c,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: IconButton(onPressed: _add, icon: const Icon(Icons.add_circle_rounded, color: AppColors.saffron)),
            ),
          ),
        ]),
      );
}
