import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speak answers aloud (text-to-speech) and take spoken questions
/// (speech-to-text) in Hindi or English. Works on Android, iOS and Chrome.
class VoiceService {
  VoiceService._();
  static final instance = VoiceService._();

  final _tts = FlutterTts();
  final _stt = SpeechToText();
  bool _ttsReady = false;
  bool _sttReady = false;
  bool _sttTried = false;

  final speaking = ValueNotifier<bool>(false);
  final listening = ValueNotifier<bool>(false);

  /// Devanagari text → Hindi voice; everything else (incl. Hinglish) → Indian English voice.
  static String languageFor(String text) => RegExp(r'[ऀ-ॿ]').hasMatch(text) ? 'hi-IN' : 'en-IN';

  /// Cleans speech results: some engines (notably Chrome on Android) repeat
  /// words or the whole phrase — "pyaz pyaz nahi nahi hai" → "pyaz nahi hai".
  static String dedupe(String text) {
    var words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    String norm(String w) => w.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    // Whole phrase said twice: "A B C A B C" or growing repeats "A A B A B C".
    for (var n = words.length ~/ 2; n >= 2; n--) {
      for (var start = 0; start + 2 * n <= words.length; start++) {
        final a = words.sublist(start, start + n).map(norm).join(' ');
        final b = words.sublist(start + n, start + 2 * n).map(norm).join(' ');
        if (a == b) {
          words = [...words.sublist(0, start + n), ...words.sublist(start + 2 * n)];
          return dedupe(words.join(' '));
        }
      }
    }
    // Same word twice in a row.
    final out = <String>[];
    for (final w in words) {
      if (out.isEmpty || norm(out.last) != norm(w)) out.add(w);
    }
    return out.join(' ');
  }

  /// Removes markdown, bullets and emoji so the voice doesn't read symbols.
  static String speakable(String text) => text
      .replaceAll(RegExp(r'\*\*|__|`|#+\s|_\(|\)_'), '')
      .replaceAll(RegExp(r'^\s*[•\-*]\s*', multiLine: true), '')
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
      .replaceAll('₹', ' rupees ')
      .replaceAll(RegExp(r'\s*—\s*'), ', ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  Future<void> _initTts() async {
    if (_ttsReady) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(kIsWeb ? 0.95 : 0.45); // slower is easier for kids & elders
      await _tts.setPitch(1.0);
      _tts.setStartHandler(() => speaking.value = true);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
    } catch (e) {
      debugPrint('TTS init failed: $e');
    }
    _ttsReady = true;
  }

  Future<void> speak(String text) async {
    final clean = speakable(text);
    if (clean.isEmpty) return;
    await _initTts();
    try {
      await _tts.stop();
      await _tts.setLanguage(languageFor(clean));
      speaking.value = true;
      await _tts.speak(clean);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    } finally {
      speaking.value = false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
  }

  /// Returns false if the device/browser has no speech recognition or the
  /// microphone permission was denied.
  Future<bool> get canListen async {
    if (_sttTried) return _sttReady;
    _sttTried = true;
    try {
      _sttReady = await _stt.initialize(
        onStatus: (s) => listening.value = s == 'listening',
        onError: (_) => listening.value = false,
      );
    } catch (e) {
      debugPrint('Speech init failed: $e');
      _sttReady = false;
    }
    return _sttReady;
  }

  /// Listens once. [onText] receives live partial text; [onDone] the final text.
  Future<bool> listen({required void Function(String) onText, required void Function(String) onDone, String localeId = 'hi-IN'}) async {
    if (!await canListen) return false;
    await stopSpeaking();
    var finished = false;
    void finish(String t) {
      if (finished) return;
      finished = true;
      listening.value = false;
      onDone(t);
    }

    await _stt.listen(
      onResult: (r) {
        final text = dedupe(r.recognizedWords);
        onText(text);
        if (r.finalResult) finish(text);
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        // Chrome's continuous/interim mode duplicates words on Android, so the
        // web build listens for one sentence and uses only the final text.
        partialResults: !kIsWeb,
        cancelOnError: true,
        listenMode: kIsWeb ? ListenMode.confirmation : ListenMode.dictation,
      ),
    );
    listening.value = true;
    return true;
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
    listening.value = false;
  }
}
