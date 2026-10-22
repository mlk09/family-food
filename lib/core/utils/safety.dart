/// Kitchen-safety reminders for cooking steps (child-friendly design).
class Safety {
  Safety._();

  static const _rules = [
    (r'\b(knife|chop|slice|cut|dice|mince|peel)', '🔪 Sharp knife step — children should only do this with an adult helping.'),
    (r'\b(hot oil|oil|ghee|butter|deep.?fry|fry|tadka|temper|splutter|pop)', '🔥 Hot oil can splash. Keep children and faces away from the pan.'),
    (r'\b(pressure cook|whistle|cooker)', '♨️ Pressure cooker: never open until all steam has released.'),
    (r'\b(boil|boiling|blanch|steam|drain)', '♨️ Boiling water and steam can burn. An adult should handle hot pots.'),
    (r'\b(oven|bake|grill|toast|tawa)', '🧤 Hot surface — use oven gloves and keep little hands away.'),
    (r'\b(gas|flame|stove|heat)', '🔥 Using the stove — an adult should be nearby. Turn off the gas when done.'),
    (r'\b(raw chicken|chicken|meat|fish)', '🧼 Wash hands, boards and knives after touching raw meat.'),
  ];

  /// Returns the most relevant safety tip for a step, or null.
  static String? tipFor(String step) {
    final s = step.toLowerCase();
    for (final (pattern, tip) in _rules) {
      if (RegExp(pattern).hasMatch(s)) return tip;
    }
    return null;
  }

  /// Extracts a timer duration from text like "cook for 10 minutes".
  static Duration? timerFor(String step) {
    final m = RegExp(r'(\d+)(?:\s*[–-]\s*(\d+))?\s*(minute|min|second|sec)', caseSensitive: false).firstMatch(step);
    if (m == null) return null;
    final n = int.parse(m.group(2) ?? m.group(1)!);
    if (n <= 0 || n > 240) return null;
    return m.group(3)!.toLowerCase().startsWith('s') ? Duration(seconds: n) : Duration(minutes: n);
  }
}
