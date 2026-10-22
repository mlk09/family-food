import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/voice_service.dart';
import '../../core/theme/app_colors.dart';
import '../../data/session.dart';
import '../../models/profile.dart';
import '../../models/recipe.dart';
import '../../widgets/common.dart';
import 'ai_providers.dart';

class ChefChatScreen extends ConsumerStatefulWidget {
  const ChefChatScreen({super.key, this.recipe, this.initialQuestion});
  final Recipe? recipe;

  /// Sent automatically when the screen opens (from Home shortcuts).
  final String? initialQuestion;

  @override
  ConsumerState<ChefChatScreen> createState() => _ChefChatScreenState();
}

class _ChefChatScreenState extends ConsumerState<ChefChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _voice = VoiceService.instance;

  static const _autoSpeakKey = 'chef_auto_speak';
  static const _voiceLangKey = 'chef_voice_lang';
  bool get _autoSpeak => ref.read(sharedPrefsProvider).getBool(_autoSpeakKey) ?? true;
  String get _voiceLang => ref.read(sharedPrefsProvider).getString(_voiceLangKey) ?? 'hi-IN';

  static const _general = [
    'Mere paas jo hai usse kya banau?',
    'Pyaz nahi hai, kya use karun?',
    'Sirf 20 minute hain, kya banau?',
    'Bachchon ke liye kya banau?',
    '₹300 mein family ke liye kya banau?',
    'Give me a healthy dinner.',
  ];
  static const _forRecipe = [
    'Kya ise bina ande ke bana sakte hain?',
    'Ise kam teekha kaise banau?',
    'Ise healthy kaise banau?',
    'Kya ye 20 minute mein ban sakta hai?',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).attachRecipe(widget.recipe);
      if (widget.initialQuestion != null) _send(widget.initialQuestion);
    });
  }

  @override
  void dispose() {
    _voice.stopSpeaking();
    _voice.stopListening();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    _input.clear();
    ref.read(chatProvider.notifier).send(t);
  }

  Future<void> _listen() async {
    if (_voice.listening.value) {
      await _voice.stopListening();
      return;
    }
    final ok = await _voice.listen(
      localeId: _voiceLang,
      onText: (t) => setState(() => _input.text = t),
      onDone: (t) {
        if (t.trim().isNotEmpty) _send(t);
      },
    );
    if (!ok && mounted) {
      showSnack(context, '🎤 Bolkar poochne ke liye mic ki permission do. (Web par Chrome browser use karo.)');
    }
  }

  Future<void> _toggleAutoSpeak() async {
    final next = !_autoSpeak;
    await ref.read(sharedPrefsProvider).setBool(_autoSpeakKey, next);
    if (!next) await _voice.stopSpeaking();
    setState(() {});
    if (mounted) showSnack(context, next ? '🔊 Chef ab jawab bolkar sunayega' : '🔇 Awaaz band');
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final ctx = ref.watch(aiContextProvider);
    ref.listen(chatProvider, (p, n) {
      if (p?.messages.length != n.messages.length || (n.messages.isNotEmpty && n.messages.last.pending)) _scrollToEnd();
      // A reply just finished → read it aloud.
      final wasPending = p != null && p.messages.isNotEmpty && p.messages.last.pending;
      if (wasPending && n.messages.isNotEmpty && !n.messages.last.pending && !n.messages.last.isUser && _autoSpeak) {
        _voice.speak(n.messages.last.content);
      }
    });
    final p = ctx.profile;
    final suggestions = chat.recipe != null ? _forRecipe : _general;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(gradient: AppColors.aiGradient, shape: BoxShape.circle),
            child: const Text('🤖', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Chef AI'),
              Text(chat.offlineMode ? 'Offline mode · on-device answers' : 'Your family cooking assistant',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: _autoSpeak ? 'Awaaz band karo' : 'Jawab bolkar sunao',
            icon: Icon(_autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            onPressed: _toggleAutoSpeak,
          ),
          PopupMenuButton<String>(
            tooltip: 'Bolne ki bhasha',
            icon: const Icon(Icons.translate_rounded),
            initialValue: _voiceLang,
            onSelected: (v) async {
              await ref.read(sharedPrefsProvider).setString(_voiceLangKey, v);
              setState(() {});
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'hi-IN', child: Text('🎤 Hindi mein bolunga')),
              PopupMenuItem(value: 'en-IN', child: Text('🎤 English mein bolunga')),
            ],
          ),
          if (chat.messages.isNotEmpty)
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(chatProvider.notifier).clear(),
            ),
        ],
      ),
      body: Column(
        children: [
          // What Chef AI knows
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _KnowChip('🧺 ${ctx.ingredients.length} ingredients'),
                if (p != null) _KnowChip('🥗 ${AppConstants.dietLabels[p.diet] ?? p.diet}'),
                if (p != null && p.allergies.isNotEmpty) _KnowChip('⚠️ Allergies: ${p.allergies.join(', ')}'),
                if (ctx.mealPlanSummary.isNotEmpty) const _KnowChip('📅 Meal plan'),
                if (ctx.savedRecipeNames.isNotEmpty) _KnowChip('❤️ ${ctx.savedRecipeNames.length} saved'),
              ],
            ),
          ),
          if (chat.recipe != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                radius: 16,
                child: Row(children: [
                  Text(chat.recipe!.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Talking about ${chat.recipe!.name}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(
                    tooltip: 'Remove recipe',
                    onPressed: () => ref.read(chatProvider.notifier).attachRecipe(null),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: chat.messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                    children: [
                      const Center(child: Text('👩‍🍳', style: TextStyle(fontSize: 64))),
                      const SizedBox(height: 12),
                      Text('Hi${p != null && p.name.isNotEmpty ? ' ${p.firstName}' : ''}! What shall we cook?',
                          textAlign: TextAlign.center, style: context.text.headlineSmall),
                      const SizedBox(height: 6),
                      Text('I know what is in your kitchen, your diet and your family preferences.',
                          textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                      const SizedBox(height: 24),
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            onTap: () => _send(s),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            radius: 18,
                            child: Row(children: [
                              const Icon(Icons.auto_awesome_rounded, color: AppColors.berry, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(s, style: context.text.bodyLarge)),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(AppConstants.allergyWarning, textAlign: TextAlign.center, style: context.text.bodySmall),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: chat.messages.length,
                    itemBuilder: (_, i) => _Bubble(chat.messages[i]),
                  ),
          ),
          if (chat.messages.isNotEmpty && !chat.sending)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final s in suggestions)
                    Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(s), onPressed: () => _send(s))),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                ValueListenableBuilder<bool>(
                  valueListenable: _voice.listening,
                  builder: (_, on, _) => SizedBox(
                    width: 52,
                    height: 52,
                    child: IconButton.filledTonal(
                      tooltip: on ? 'Sunna band karo' : 'Bolkar poocho',
                      style: IconButton.styleFrom(backgroundColor: on ? AppColors.tomato : AppColors.berry.withValues(alpha: 0.22)),
                      onPressed: chat.sending ? null : _listen,
                      icon: Icon(on ? Icons.stop_rounded : Icons.mic_rounded, color: on ? Colors.white : null, size: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(fontSize: 17),
                    decoration: InputDecoration(
                      hintText: _voice.listening.value ? '🎤 Sun raha hoon… boliye' : 'Likho ya 🎤 dabakar bolo',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 58,
                  height: 58,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(gradient: AppColors.aiGradient, shape: BoxShape.circle),
                    child: IconButton(
                      tooltip: 'Send',
                      onPressed: chat.sending ? null : _send,
                      icon: chat.sending
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _KnowChip extends StatelessWidget {
  const _KnowChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.berry.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final ChatMessage m;

  @override
  Widget build(BuildContext context) {
    final user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: user ? AppColors.primaryGradient : null,
            color: user ? null : context.palette.card,
            border: user ? null : Border.all(color: context.palette.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(user ? 20 : 6),
              bottomRight: Radius.circular(user ? 6 : 20),
            ),
          ),
          child: m.pending && m.content.isEmpty
              ? const _TypingDots()
              : user
                  ? Text(m.content, style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.4))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      RichMessage(m.content),
                      if (!m.pending)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: () => VoiceService.instance.speak(m.content),
                            icon: const Icon(Icons.volume_up_rounded, size: 18),
                            label: const Text('Suno'),
                          ),
                        ),
                    ]),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 20,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < 3; i++)
                Opacity(
                  opacity: 0.3 + 0.7 * (((_c.value * 3 - i) % 3) < 1 ? 1 : 0),
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.saffron, shape: BoxShape.circle)),
                ),
            ],
          ),
        ),
      );
}
