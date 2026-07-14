import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:litert_slm_gemma4/services/stt_service.dart';
import 'package:litert_slm_gemma4/services/voice_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_kit/whisper_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Whisper STT transcribes a known phrase end-to-end',
    (tester) async {
      // Fixture synthesized via macOS `say -o hello_test.aiff "The quick
      // brown fox jumps over the lazy dog"`, then converted to WAV via
      // `afconvert -d LEI16@16000 -c 1 -f WAVE` — whisper_kit's native core
      // only accepts 16kHz/16-bit/mono WAV, unlike whisper_ggml it doesn't
      // auto-convert other formats.
      final bytes = await rootBundle.load('assets/test/hello_test.wav');
      final tempDir = await getTemporaryDirectory();
      final audioFile = File('${tempDir.path}/hello_test.wav');
      await audioFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );

      final stt = WhisperSttService.instance;
      await stt.initialize();
      expect(stt.state, SttServiceState.ready);

      final whisper = Whisper(
        model: WhisperSttService.model,
        modelDir: stt.modelDir,
      );
      final result = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioFile.path,
          language: 'en',
        ),
      );

      final text = result.text.toLowerCase();
      // Whisper decoding isn't byte-exact, so assert on the distinctive
      // words rather than an exact string match.
      expect(text, contains('fox'));
      expect(text, contains('dog'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'Flutter TTS synthesizes speech without error',
    (tester) async {
      final voice = VoiceService.instance;
      await voice.initialize();
      expect(voice.state, VoiceServiceState.ready);

      // awaitSpeakCompletion(true) means speak() only resolves once
      // playback finishes, so returning here without throwing/hanging is
      // the pass condition.
      await voice.speak('Marine engineering assistant ready.');
      expect(voice.isSpeaking, isFalse);

      await voice.dispose();
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
