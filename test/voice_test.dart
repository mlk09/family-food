import 'package:family_food_assistant/core/services/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picks a Hindi voice for Devanagari and Indian English otherwise', () {
    expect(VoiceService.languageFor('प्याज़ की जगह हींग डालें'), 'hi-IN');
    expect(VoiceService.languageFor('Pyaz nahi hai to hing daalo'), 'en-IN');
  });

  test('strips markdown, bullets and emoji before speaking', () {
    const reply = 'No onion? 🙌 Try:\n• **Spring onion** — same crunch\n• _(offline answer)_ ₹50';
    final s = VoiceService.speakable(reply);
    expect(s, isNot(contains('**')));
    expect(s, isNot(contains('•')));
    expect(s, isNot(contains('🙌')));
    expect(s, contains('Spring onion, same crunch'));
    expect(s, contains('rupees'));
  });

  test('reads number ranges as "2 se 3", not "2 minus 3"', () {
    expect(VoiceService.speakable('2-3 मिनट और पकाएं'), '2 से 3 मिनट और पकाएं');
    expect(VoiceService.speakable('Cook for 10 – 12 min'), 'Cook for 10 to 12 min');
    expect(VoiceService.speakable('Use -2 spoons? No, 1.5-2 spoons'), 'Use -2 spoons? No, 1.5 to 2 spoons');
  });

  test('removes words and phrases repeated by the speech engine', () {
    expect(VoiceService.dedupe('pyaz pyaz nahi nahi hai hai'), 'pyaz nahi hai');
    expect(VoiceService.dedupe('pyaz nahi hai pyaz nahi hai'), 'pyaz nahi hai');
    expect(VoiceService.dedupe('mere paas mere paas jo hai usse kya banau'), 'mere paas jo hai usse kya banau');
    expect(VoiceService.dedupe('प्याज़ नहीं है प्याज़ नहीं है'), 'प्याज़ नहीं है');
    expect(VoiceService.dedupe('aloo aur tamatar se kya banau'), 'aloo aur tamatar se kya banau');
    expect(VoiceService.dedupe('Aloo, aloo'), 'Aloo,');
  });
}
