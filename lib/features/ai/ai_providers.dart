import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/offline_chef.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/id.dart';
import '../../core/utils/ingredient_matcher.dart';
import '../../data/providers.dart';
import '../../data/session.dart';
import '../../data/sync_engine.dart';
import '../../models/profile.dart';
import '../../models/recipe.dart';

final aiServiceProvider = Provider<AIService>((ref) => AIService(client: ref.watch(supabaseClientProvider)));

/// Snapshot of everything Chef AI should know.
final aiContextProvider = Provider<AIContext>((ref) {
  final plan = ref.watch(mealPlanProvider).value;
  final family = ref.watch(familyProvider).value;
  return AIContext(
    ingredients: ref.watch(ingredientsProvider).value ?? const [],
    profile: ref.watch(profileProvider).value,
    savedRecipeNames: (ref.watch(savedRecipesProvider).value ?? const []).map((r) => r.name).toList(),
    mealPlanSummary: [
      for (final i in plan?.items ?? const [])
        '${AppConstants.weekdays[i.day]} ${i.mealType}: ${i.recipeName}',
    ],
    familySize: family?.members.length ?? plan?.people,
  );
});

// ───────────────────────── What Can I Cook? ─────────────────────────

class SuggestionsState {
  const SuggestionsState({
    this.instant = const [],
    this.ai = const [],
    this.aiLoading = false,
    this.aiError,
    this.request = '',
  });

  /// Zero-latency matches from the on-device recipe book.
  final List<RecipeMatch> instant;

  /// Personalised AI recipes (arrive a few seconds later).
  final List<Recipe> ai;
  final bool aiLoading;
  final String? aiError;
  final String request;

  SuggestionsState copyWith({
    List<RecipeMatch>? instant,
    List<Recipe>? ai,
    bool? aiLoading,
    String? aiError,
    bool clearError = false,
    String? request,
  }) =>
      SuggestionsState(
        instant: instant ?? this.instant,
        ai: ai ?? this.ai,
        aiLoading: aiLoading ?? this.aiLoading,
        aiError: clearError ? null : (aiError ?? this.aiError),
        request: request ?? this.request,
      );
}

class SuggestionsNotifier extends Notifier<SuggestionsState> {
  int _generation = 0;

  @override
  SuggestionsState build() => const SuggestionsState();

  /// Shows local matches immediately, then fetches AI recipes in parallel.
  Future<void> run({
    Set<String>? onlyIngredients,
    MatchFilters? filters,
    String request = '',
  }) async {
    final gen = ++_generation;
    final ctx = ref.read(aiContextProvider);
    final pantry = onlyIngredients == null
        ? ctx.ingredients
        : ctx.ingredients.where((i) => onlyIngredients.contains(i.id)).toList();
    final p = ctx.profile;
    final f = filters ?? MatchFilters(diet: p?.diet, allergies: p?.allergies ?? const []);

    state = SuggestionsState(
      instant: IngredientMatcher.match(pantry, filters: f),
      aiLoading: true,
      request: request,
    );

    final ai = ref.read(aiServiceProvider);
    if (!ai.isAvailable) {
      state = state.copyWith(aiLoading: false, aiError: 'offline');
      return;
    }
    try {
      final extra = [
        if (request.isNotEmpty) request,
        if (f.maxMinutes != null) 'Must be ready in ${f.maxMinutes} minutes or less.',
        if (f.kidsOnly) 'Make them child-friendly and mild.',
        if (f.mealType != null) 'Suitable for ${f.mealType}.',
      ].join(' ');
      final recipes = await ai.generateRecipes(
        AIContext(
          ingredients: pantry,
          profile: p,
          savedRecipeNames: ctx.savedRecipeNames,
          mealPlanSummary: ctx.mealPlanSummary,
          familySize: ctx.familySize,
        ),
        request: extra,
      );
      if (gen != _generation) return;
      state = state.copyWith(ai: recipes, aiLoading: false, clearError: true);
    } catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(aiLoading: false, aiError: friendlyError(e));
    }
  }
}

final suggestionsProvider = NotifierProvider<SuggestionsNotifier, SuggestionsState>(SuggestionsNotifier.new);

// ───────────────────────── Chef AI chat ─────────────────────────

class ChatState {
  const ChatState({this.messages = const [], this.sending = false, this.offlineMode = false, this.recipe});
  final List<ChatMessage> messages;
  final bool sending;
  final bool offlineMode;
  final Recipe? recipe;

  ChatState copyWith({List<ChatMessage>? messages, bool? sending, bool? offlineMode, Recipe? recipe, bool clearRecipe = false}) =>
      ChatState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        offlineMode: offlineMode ?? this.offlineMode,
        recipe: clearRecipe ? null : (recipe ?? this.recipe),
      );
}

class ChatNotifier extends Notifier<ChatState> {
  String? _conversationId;

  @override
  ChatState build() {
    final store = ref.watch(localStoreProvider);
    final saved = store.readList('chat').map(ChatMessage.fromJson).toList();
    _conversationId = store.readMap('chat_meta')?['conversation_id'] as String?;
    return ChatState(messages: saved, offlineMode: !ref.read(aiServiceProvider).isAvailable);
  }

  void attachRecipe(Recipe? r) => state = r == null ? state.copyWith(clearRecipe: true) : state.copyWith(recipe: r);

  Future<void> clear() async {
    state = state.copyWith(messages: const []);
    _conversationId = null;
    final store = ref.read(localStoreProvider);
    await store.writeList('chat', const []);
    await store.writeMap('chat_meta', null);
  }

  Future<void> _persist() async {
    final done = state.messages.where((m) => !m.pending).toList();
    await ref.read(localStoreProvider).writeList('chat', done.map((m) => m.toJson()).toList());
  }

  Future<void> _remoteLog(ChatMessage m) async {
    final session = ref.read(sessionProvider);
    if (!session.isCloud) return;
    final sync = ref.read(syncEngineProvider);
    if (_conversationId == null) {
      _conversationId = newId();
      await ref.read(localStoreProvider).writeMap('chat_meta', {'conversation_id': _conversationId});
      await sync.enqueue(OutboxOp('upsert', 'ai_conversations', {
        'id': _conversationId,
        'user_id': session.ownerId,
        'title': m.content.length > 60 ? '${m.content.substring(0, 60)}…' : m.content,
      }));
    }
    await sync.enqueue(OutboxOp('upsert', 'ai_messages', {
      'id': newId(),
      'conversation_id': _conversationId,
      'user_id': session.ownerId,
      'role': m.role,
      'content': m.content,
    }));
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.sending) return;
    final userMsg = ChatMessage(role: 'user', content: q);
    state = state.copyWith(
      messages: [...state.messages, userMsg, const ChatMessage(role: 'assistant', content: '', pending: true)],
      sending: true,
    );
    unawaited(_remoteLog(userMsg));

    final ctx = ref.read(aiContextProvider);
    final ai = ref.read(aiServiceProvider);
    final recipe = state.recipe;
    var reply = '';

    void update(String content, {bool pending = true}) {
      final msgs = [...state.messages];
      msgs[msgs.length - 1] = ChatMessage(role: 'assistant', content: content, pending: pending);
      state = state.copyWith(messages: msgs);
    }

    if (ai.isAvailable) {
      try {
        final history = [
          for (final m in state.messages.where((m) => !m.pending && m.content.isNotEmpty))
            {'role': m.role, 'content': m.content},
        ];
        await for (final chunk in ai.askChefAI(history, ctx, recipeJson: recipe == null ? null : _recipeBrief(recipe))) {
          reply += chunk;
          update(reply);
        }
      } catch (e) {
        if (reply.isEmpty) {
          // Graceful degradation: answer from the on-device chef instead.
          reply = '${OfflineChef.reply(q, ctx, recipe: recipe)}\n\n_(${friendlyError(e)} Showing an offline answer.)_';
        }
      }
    } else {
      reply = OfflineChef.reply(q, ctx, recipe: recipe);
    }
    if (reply.trim().isEmpty) reply = OfflineChef.reply(q, ctx, recipe: recipe);

    update(reply, pending: false);
    state = state.copyWith(sending: false);
    await _persist();
    unawaited(_remoteLog(ChatMessage(role: 'assistant', content: reply)));
  }

  static String _recipeBrief(Recipe r) =>
      '${r.name}: ingredients ${r.ingredients.map((i) => '${i.quantity} ${i.name}'.trim()).join(', ')}. '
      'Steps: ${r.instructions.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join(' ')}';
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
