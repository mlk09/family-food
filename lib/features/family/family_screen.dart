import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_error.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../../models/profile.dart';
import '../../widgets/common.dart';

class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, success);
    } on PostgrestException catch (e) {
      if (mounted) {
        showSnack(context, e.message.contains('invalid_code') ? 'That invite code was not found. Please check it.' : friendlyError(e));
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createOrJoin({required bool join}) async {
    final profile = ref.read(profileProvider).value;
    final nameCtl = TextEditingController();
    final meCtl = TextEditingController(text: profile?.firstName ?? '');
    var role = 'member';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            Text(join ? 'Join a family' : 'Create a family', style: c.text.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtl,
              textCapitalization: join ? TextCapitalization.characters : TextCapitalization.words,
              decoration: InputDecoration(
                labelText: join ? 'Invite code' : 'Family name',
                hintText: join ? 'e.g. K7P2QX' : 'e.g. Sharma Family',
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: meCtl, decoration: const InputDecoration(labelText: 'Your name in the family')),
            const SizedBox(height: 14),
            Text('Your role', style: c.text.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in AppConstants.memberRoles.entries)
                ChoiceChip(label: Text(e.value), selected: role == e.key, onSelected: (_) => set(() => role = e.key)),
            ]),
            const SizedBox(height: 20),
            GradientButton(label: join ? 'Join family' : 'Create family', onPressed: () => Navigator.pop(c, true)),
          ]),
        ),
      ),
    );
    final name = nameCtl.text.trim(), me = meCtl.text.trim().isEmpty ? 'Member' : meCtl.text.trim();
    nameCtl.dispose();
    meCtl.dispose();
    if (ok != true || name.isEmpty) return;
    final n = ref.read(familyProvider.notifier);
    await _run(
      () => join ? n.join(name, me, role) : n.create(name, me, role),
      join ? '🎉 You joined the family!' : '🎉 Family created! Share the invite code.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final family = ref.watch(familyProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (family == null) ...[
              const SizedBox(height: 20),
              const Center(child: Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 72))),
              const SizedBox(height: 14),
              Text('Cook together', textAlign: TextAlign.center, style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text('Share your kitchen inventory, shopping list, meal plan and favourite recipes with everyone at home.',
                  textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 26),
              if (!session.isCloud)
                const SafetyBanner('Family sharing needs a signed-in account. Create an account from the Profile tab to invite your family.')
              else ...[
                GradientButton(label: 'Create a family', icon: Icons.add_home_rounded, onPressed: () => _createOrJoin(join: false)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _createOrJoin(join: true),
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('Join with an invite code'),
                ),
              ],
            ] else ...[
              AppCard(
                gradient: AppColors.gradientFor(family.name),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('🏠 ${family.name}', style: context.text.headlineSmall?.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('${family.members.length} members · everything is shared', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      const Text('Invite code', style: TextStyle(color: Colors.white)),
                      const Spacer(),
                      Text(family.inviteCode,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 3)),
                      IconButton(
                        tooltip: 'Copy code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: family.inviteCode));
                          showSnack(context, 'Invite code copied');
                        },
                        icon: const Icon(Icons.copy_rounded, color: Colors.white),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              const SectionHeader('Members', emoji: '👥'),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  for (final m in family.members) _MemberTile(m),
                ]),
              ),
              const SizedBox(height: 18),
              const SectionHeader('Shared with everyone', emoji: '🔗'),
              const AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('🧺  Kitchen inventory'),
                  SizedBox(height: 8),
                  Text('🛒  Shopping list'),
                  SizedBox(height: 8),
                  Text('📅  Meal plan'),
                  SizedBox(height: 8),
                  Text('❤️  Favourite recipes'),
                ]),
              ),
              const SizedBox(height: 22),
              if (session.isCloud)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Leave family?'),
                        content: const Text('You will stop seeing the shared kitchen, list and plan. Items you added go with you.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
                        ],
                      ),
                    );
                    if (ok == true) await _run(() => ref.read(familyProvider.notifier).leave(), 'You left the family');
                  },
                  icon: const Icon(Icons.logout_rounded, color: AppColors.expired),
                  label: const Text('Leave family', style: TextStyle(color: AppColors.expired)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile(this.m);
  final FamilyMember m;

  @override
  Widget build(BuildContext context) {
    final role = AppConstants.memberRoles[m.role] ?? AppConstants.memberRoles['member']!;
    return ListTile(
      minTileHeight: 62,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.saffron.withValues(alpha: 0.18),
        child: Text(role.split(' ').first, style: const TextStyle(fontSize: 22)),
      ),
      title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(role.split(' ').skip(1).join(' ')),
      trailing: m.isAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.saffron.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
              child: const Text('Admin', style: TextStyle(color: AppColors.saffron, fontWeight: FontWeight.w700, fontSize: 12)),
            )
          : null,
    );
  }
}
