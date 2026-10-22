import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import '../../widgets/recipe_widgets.dart';

class SavedRecipesScreen extends ConsumerWidget {
  const SavedRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedRecipesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Recipes')),
      body: saved.isEmpty
          ? const EmptyState(emoji: '❤️', title: 'No saved recipes yet', message: 'Tap the heart on any recipe to keep it here — even offline.')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.78,
              ),
              itemCount: saved.length,
              itemBuilder: (_, i) {
                final r = saved[i];
                return AppCard(
                  padding: const EdgeInsets.all(10),
                  onTap: () => context.push(Routes.recipe, extra: r),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: RecipeArt(recipe: r, height: double.infinity, radius: 16, emojiSize: 44)),
                    const SizedBox(height: 10),
                    Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${r.totalTime} min · ${r.difficulty}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                );
              },
            ),
    );
  }
}
