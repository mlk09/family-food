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
}
