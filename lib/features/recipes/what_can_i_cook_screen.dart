import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/food_emoji.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../data/providers.dart';
import '../../models/ingredient.dart';
import '../../models/recipe.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import '../../widgets/recipe_widgets.dart';
import '../ai/ai_providers.dart';

class WhatCanICookScreen extends ConsumerStatefulWidget {
  const WhatCanICookScreen({super.key});

  @override
  ConsumerState<WhatCanICookScreen> createState() => _WhatCanICookScreenState();
}

class _WhatCanICookScreenState extends ConsumerState<WhatCanICookScreen> {
  Set<String>? _selected; // ingredient ids; null = all
  bool _quick = false, _kids = false;
  String? _meal;
  bool _showIngredients = false;
  final _request = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  void _run() {
    final p = ref.read(profileProvider).value;
    ref.read(suggestionsProvider.notifier).run(
          onlyIngredients: _selected,
          request: _request.text.trim(),
          filters: MatchFilters(
            diet: p?.diet,
            allergies: p?.allergies ?? const [],
            maxMinutes: _quick ? 30 : null,
            kidsOnly: _kids,
            mealType: _meal,
          ),
        );
  }

  void _open(Recipe r) => context.push(Routes.recipe, extra: r);

  @override
  Widget build(BuildContext context) {
    final pantry = (ref.watch(ingredientsProvider).value ?? const <Ingredient>[])
        .where((i) => i.freshness() != Freshness.expired)
        .toList()
      ..sort((a, b) => (a.daysLeft() ?? 999).compareTo(b.daysLeft() ?? 999));
    final s = ref.watch(suggestionsProvider);
    final usingCount = _selected?.length ?? pantry.length;

    return Scaffold(
      appBar: AppBar(title: const Text('What Can I Cook?')),
      body: pantry.isEmpty
          ? EmptyState(
              emoji: '🧺',
              title: 'Add a few ingredients first',
              message: 'Tell us what you have at home — even 3 or 4 items is enough for ideas.',
              action: 'Add ingredients',
              onAction: () => context.push(Routes.addIngredient),
            )
          : RefreshIndicator(
              onRefresh: () async => _run(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
                children: [
                  // ── Ingredients in use ──
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    onTap: () => setState(() => _showIngredients = !_showIngredients),
                    child: Row(children: [
                      const Text('🧺', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Using $usingCount of ${pantry.length} ingredients', style: context.text.titleMedium)),
                      Icon(_showIngredients ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    ]),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    child: !_showIngredients
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final i in pantry)
                                FilterChip(
                                  label: Text('${foodEmoji(i.name, i.category)} ${i.name}'),
                                  selected: _selected?.contains(i.id) ?? true,
                                  onSelected: (v) => setState(() {
                                    final cur = _selected ?? pantry.map((e) => e.id).toSet();
                                    v ? cur.add(i.id) : cur.remove(i.id);
                                    _selected = cur;
                                  }),
                                ),
                            ]),
                          ),
                  ),
                  const SizedBox(height: 12),
                  // ── Filters ──
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      FilterChip(label: const Text('⏱️ Under 30 min'), selected: _quick, onSelected: (v) => setState(() => _quick = v)),
                      const SizedBox(width: 8),
                      FilterChip(label: const Text('🧒 Kid-friendly'), selected: _kids, onSelected: (v) => setState(() => _kids = v)),
                      for (final m in const [('breakfast', '🍳 Breakfast'), ('lunch', '🥗 Lunch'), ('dinner', '🍛 Dinner')]) ...[
                        const SizedBox(width: 8),
                        ChoiceChip(label: Text(m.$2), selected: _meal == m.$1, onSelected: (v) => setState(() => _meal = v ? m.$1 : null)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _request,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _run(),
                    decoration: InputDecoration(
                      hintText: 'Anything special? e.g. "South Indian", "no frying"',
                      prefixIcon: const Icon(Icons.auto_awesome_rounded, color: AppColors.berry),
                      suffixIcon: IconButton(onPressed: _run, icon: const Icon(Icons.arrow_forward_rounded), tooltip: 'Find recipes'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GradientButton(label: 'Find Recipes', icon: Icons.restaurant_menu_rounded, gradient: AppColors.aiGradient, onPressed: _run),
                  const SizedBox(height: 22),

                  // ── AI section ──
                  if (s.aiLoading) ...[
                    const _AiThinking(),
                    const SizedBox(height: 18),
                  ] else if (s.ai.isNotEmpty) ...[
                    const SectionHeader('Chef AI picks for you', emoji: '✨'),
                    for (final r in s.ai) ...[
                      _FadeIn(
                        child: RecipeCard(
                          recipe: r,
                          badge: '✨ AI',
                          used: r.ingredients.where((i) => i.available).map((i) => i.name).toList(),
                          missing: r.missingIngredients,
                          onTap: () => _open(r),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ] else if (s.aiError != null && s.aiError != 'offline') ...[
                    AppCard(
                      onTap: _run,
                      child: Row(children: [
                        const Text('😴', style: TextStyle(fontSize: 26)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${s.aiError}\nHere are instant ideas from our recipe book meanwhile.', style: context.text.bodyMedium)),
                        const Icon(Icons.refresh_rounded),
                      ]),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // ── Instant section ──
                  if (s.instant.isNotEmpty) ...[
                    SectionHeader(s.aiError == 'offline' ? 'Recipes you can make' : 'Instant matches', emoji: '⚡'),
                    for (final m in s.instant) ...[
                      RecipeCard(
                        recipe: m.recipe,
                        badge: m.missing.isEmpty ? '✅ You have everything' : '${m.used.length}/${m.used.length + m.missing.length} in kitchen',
                        used: m.used,
                        missing: m.missing,
                        onTap: () => _open(m.recipe),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ] else if (!s.aiLoading && s.ai.isEmpty)
                    const EmptyState(
                      emoji: '🤔',
                      title: 'No matches yet',
                      message: 'Try removing a filter, or ask Chef AI for ideas using the 🤖 button.',
                    ),
                ],
              ),
            ),
    );
  }
}

class _AiThinking extends StatefulWidget {
  const _AiThinking();

  @override
  State<_AiThinking> createState() => _AiThinkingState();
}

class _AiThinkingState extends State<_AiThinking> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  static const _emojis = ['🥔', '🍅', '🧅', '🥚', '🍚', '🌶️'];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        gradient: LinearGradient(colors: [AppColors.berry.withValues(alpha: 0.16), AppColors.tomato.withValues(alpha: 0.12)]),
        child: Row(children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Text(_emojis[(_c.value * _emojis.length).floor() % _emojis.length], style: const TextStyle(fontSize: 30)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chef AI is cooking up ideas…', style: context.text.titleMedium),
              Text('Personalised for your family. Instant matches are below.', style: context.text.bodySmall),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      const Shimmer(height: 110),
    ]);
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: c)),
        child: child,
      );
}
