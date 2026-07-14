import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_kit/download_model.dart';
import 'package:whisper_kit/whisper_kit.dart';

enum SttServiceState { idle, downloading, loading, ready, error }

/// Wraps whisper_kit (on-device whisper.cpp) for speech-to-text. Downloads
/// the ggml model with progress tracking on first run, then records mic
/// audio to a WAV file via the `record` package and transcribes it in one
/// shot once the user stops talking — whisper_kit only exposes file-based
/// transcription, not a live/streaming session, so there are no partial
/// transcripts while the user is still speaking. TTS is handled separately
/// by [VoiceService].
class WhisperSttService {
  WhisperSttService._();
  static final WhisperSttService instance = WhisperSttService._();

  static const model = WhisperModel.base;

  SttServiceState _state = SttServiceState.idle;
  SttServiceState get state => _state;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void Function(SttServiceState)? onStateChanged;

  /// Fired when [isTranscribing] flips — lets the UI distinguish "still
  /// recording your voice" from "recording stopped, now running the
  /// (silent, can take a few seconds) transcription pass over it", since
  /// whisper_kit has no incremental output to show progress otherwise.
  void Function()? onTranscribingChanged;
  bool _isTranscribing = false;
  bool get isTranscribing => _isTranscribing;

  void _setTranscribing(bool value) {
    _isTranscribing = value;
    onTranscribingChanged?.call();
  }

  final _recorder = AudioRecorder();
  Whisper? _whisper;
  String? _modelDir;

  /// Directory the model was downloaded into, so tests/tools can transcribe
  /// a file directly against the already-downloaded model without paying
  /// for a second download.
  String? get modelDir => _modelDir;

  bool _isListening = false;
  bool get isListening => _isListening;

  String? _recordingPath;
  DateTime? _recordingStartedAt;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _silenceTimer;
  DateTime? _lastSpeechAt;
  bool _hasSpeech = false;

  /// Mic input louder than this (dBFS) counts as speech for silence
  /// detection. Values below this are treated as background noise/silence.
  /// Typical room noise floor sits well below -40dB; normal speech is well
  /// above it, so this has margin in both directions without needing
  /// per-device calibration.
  static const _speechDbThreshold = -35.0;

  /// How much audio to keep after the last detected speech, when trimming
  /// the recording before transcription. whisper_kit doesn't expose
  /// whisper.cpp's `suppress_non_speech_tokens` flag (it's hardcoded off in
  /// the bundled native lib), so a long silent tail — e.g. the ~1.4s of
  /// dead air [startListening] waits through before auto-stopping — gets
  /// handed to the model as if it were speech, and it's a well-known
  /// whisper.cpp behavior to decode pure silence as a literal hallucinated
  /// token like "[BLANK_AUDIO]". Trimming the tail down to just past the
  /// last speech (with a little padding so words aren't clipped) avoids
  /// feeding it that silence at all. Matches the sample format written by
  /// [startListening]'s RecordConfig (16kHz, mono, 16-bit PCM).
  static const _trailingSilencePaddingMs = 500;
  static const _sampleRate = 16000;
  static const _bytesPerFrame = 2;

  /// Wall-clock timer for the current listening session, purely for
  /// diagnosing perceived latency in logs (elapsed ms from mic-tap).
  final Stopwatch _sessionClock = Stopwatch();

  void _setState(SttServiceState s) {
    _state = s;
    onStateChanged?.call(s);
  }

  Future<void> initialize() async {
    if (_state == SttServiceState.ready) return;

    try {
      _setState(SttServiceState.downloading);
      await _downloadModelWithProgress();

      _setState(SttServiceState.loading);
      _whisper = Whisper(model: model, modelDir: _modelDir);
      // whisper_kit reopens the native library and reloads the model from
      // disk on every request (no persistent in-memory session), so a
      // version check is the cheapest way to confirm the native library
      // actually links and runs on this device before the user's first
      // recording depends on it.
      await _whisper!.getVersion();
      _setState(SttServiceState.ready);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(SttServiceState.error);
      rethrow;
    }
  }

  Future<void> _downloadModelWithProgress() async {
    final dir = await getApplicationSupportDirectory();
    _modelDir = dir.path;
    final path = model.getPath(_modelDir!);
    final file = File(path);
    if (file.existsSync() && file.lengthSync() > 0) {
      _downloadProgress = 1.0;
      onStateChanged?.call(_state);
      return;
    }

    debugPrint('[STT] Downloading whisper model ${model.modelName}...');
    await downloadModel(
      model: model,
      destinationPath: _modelDir!,
      onDownloadProgress: (received, total) {
        _downloadProgress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        onStateChanged?.call(_state);
      },
    );
  }

  // ── Listening ────────────────────────────────────────────────────────

  /// Starts recording from the mic to a temporary WAV file. There are no
  /// live partial transcripts (whisper_kit doesn't support streaming) — the
  /// caller sees a "Listening…" state until speech has started and then
  /// gone quiet for [silenceTimeout], at which point listening stops
  /// automatically, the recording is transcribed, and [onAutoStop] is
  /// called with the result. The caller doesn't need to tap the mic again
  /// to stop.
  Future<void> startListening({
    void Function(String finalText)? onAutoStop,
    Duration silenceTimeout = const Duration(milliseconds: 1400),
  }) async {
    if (_state != SttServiceState.ready || _isListening) return;

    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied.');
    }

    _isListening = true;
    _hasSpeech = false;
    _lastSpeechAt = null;
    _sessionClock
      ..reset()
      ..start();
    debugPrint('[STT] +0ms mic tapped, starting recording');

    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/stt_${DateTime.now().microsecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _recordingPath!,
    );
    _recordingStartedAt = DateTime.now();
    debugPrint('[STT] +${_sessionClock.elapsedMilliseconds}ms recording started');

    var loggedAboveThreshold = false;
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
          final above = amp.current > _speechDbThreshold;
          if (above != loggedAboveThreshold) {
            loggedAboveThreshold = above;
            debugPrint(
              '[STT] +${_sessionClock.elapsedMilliseconds}ms amplitude '
              '${amp.current.toStringAsFixed(1)}dB crossed threshold '
              '(${above ? "speech" : "quiet"})',
            );
          }
          if (above) {
            _hasSpeech = true;
            _lastSpeechAt = DateTime.now();
          }
        });

    if (onAutoStop != null) {
      // Poll rather than debounce off individual amplitude events, so a
      // stretch of silence is detected on a steady cadence.
      _silenceTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) async {
        final lastSpeechAt = _lastSpeechAt;
        if (!_isListening || !_hasSpeech || lastSpeechAt == null) return;
        if (DateTime.now().difference(lastSpeechAt) >= silenceTimeout) {
          debugPrint(
            '[STT] +${_sessionClock.elapsedMilliseconds}ms silence timeout hit, auto-stopping',
          );
          final text = await stopListening();
          onAutoStop(text);
        }
      });
    }
  }

  /// Stops recording and transcribes whatever was captured. Returns an
  /// empty string if no speech was detected, without running the (relatively
  /// expensive) native transcription pass at all.
  Future<String> stopListening() async {
    if (!_isListening) return '';
    _isListening = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    unawaited(_amplitudeSub?.cancel() ?? Future.value());
    _amplitudeSub = null;

    await _recorder.stop();
    final path = _recordingPath;
    final recordingStartedAt = _recordingStartedAt;
    final lastSpeechAt = _lastSpeechAt;
    _recordingPath = null;
    _recordingStartedAt = null;

    if (path == null || !_hasSpeech) {
      _sessionClock.stop();
      if (path != null) unawaited(File(path).delete().catchError((_) => File(path)));
      return '';
    }

    if (recordingStartedAt != null && lastSpeechAt != null) {
      final keepMs = lastSpeechAt.difference(recordingStartedAt).inMilliseconds +
          _trailingSilencePaddingMs;
      try {
        await _trimTrailingSilence(path, keepMs: keepMs);
      } catch (e) {
        // Non-fatal — transcribing the untrimmed file just risks a
        // "[BLANK_AUDIO]"-style artifact, not a hard failure.
        debugPrint('[STT] trailing-silence trim failed, using full recording: $e');
      }
    }

    _setTranscribing(true);
    try {
      final result = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: 'en',
          isNoTimestamps: true,
        ),
      );
      final text = _stripNonSpeechArtifacts(result.text);
      debugPrint(
        '[STT] +${_sessionClock.elapsedMilliseconds}ms transcribed: "$text"',
      );
      return text;
    } catch (e) {
      debugPrint('[STT] transcribe failed: $e');
      return '';
    } finally {
      _setTranscribing(false);
      _sessionClock.stop();
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
  }

  /// Whisper (all sizes, not just base) hallucinates literal tokens like
  /// "[BLANK_AUDIO]", "[SILENCE]", or "(wind blowing)" for stretches of
  /// non-speech audio it still tries to caption. Genuine spoken words never
  /// come back wrapped in brackets/parens, so stripping any bracketed
  /// content is a safe, format-agnostic net regardless of which exact
  /// placeholder string a given model version emits.
  static final _nonSpeechArtifact = RegExp(r'\[[^\]]*\]|\([^)]*\)');

  String _stripNonSpeechArtifacts(String text) {
    return text
        .replaceAll(_nonSpeechArtifact, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Truncates the WAV at [path] to [keepMs] milliseconds of audio data,
  /// then fixes up the RIFF/data chunk sizes so the trimmed file is still a
  /// valid WAV. Locates the `data` chunk by scanning rather than assuming a
  /// fixed 44-byte header, since chunk layout can vary slightly by platform
  /// encoder.
  Future<void> _trimTrailingSilence(String path, {required int keepMs}) async {
    if (keepMs <= 0) return;
    final file = File(path);
    final bytes = await file.readAsBytes();

    var offset = 12; // past 'RIFF' + size(4) + 'WAVE'
    int? dataChunkOffset;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = ByteData.sublistView(bytes, offset + 4, offset + 8)
          .getUint32(0, Endian.little);
      if (id == 'data') {
        dataChunkOffset = offset;
        break;
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    if (dataChunkOffset == null) return;

    final audioStart = dataChunkOffset + 8;
    if (audioStart >= bytes.length) return;

    final keepBytes =
        audioStart + ((keepMs / 1000) * _sampleRate * _bytesPerFrame).round();
    final cutoff = keepBytes.clamp(audioStart, bytes.length);
    if (cutoff >= bytes.length) return; // nothing to trim

    final trimmed = Uint8List.fromList(bytes.sublist(0, cutoff));
    final view = ByteData.sublistView(trimmed);
    view.setUint32(4, trimmed.length - 8, Endian.little); // RIFF chunk size
    view.setUint32(
      dataChunkOffset + 4,
      trimmed.length - audioStart,
      Endian.little,
    ); // data chunk size
    await file.writeAsBytes(trimmed);
  }

  Future<void> cancelListening() async {
    if (!_isListening) return;
    _isListening = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    unawaited(_amplitudeSub?.cancel() ?? Future.value());
    _amplitudeSub = null;

    await _recorder.stop();
    final path = _recordingPath;
    _recordingPath = null;
    _recordingStartedAt = null;
    if (path != null) unawaited(File(path).delete().catchError((_) => File(path)));
  }

  Future<void> dispose() async {
    await cancelListening();
    await _recorder.dispose();
    _state = SttServiceState.idle;
  }
}
