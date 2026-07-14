import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum VoiceServiceState { idle, ready, error }

/// Wraps the platform's on-device TTS engine (AVSpeechSynthesizer on
/// iOS/macOS, Android TextToSpeech). No model download is required — the
/// synthesis voice ships with the OS. STT is handled separately by
/// [WhisperSttService].
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  VoiceServiceState _state = VoiceServiceState.idle;
  VoiceServiceState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void Function(VoiceServiceState)? onStateChanged;

  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  // Sentence queue — lets callers feed a response in as it streams in and
  // have it spoken sentence-by-sentence instead of waiting for it to finish.
  final List<String> _queue = [];
  bool _draining = false;

  void _setState(VoiceServiceState s) {
    _state = s;
    onStateChanged?.call(s);
  }

  Future<void> initialize() async {
    if (_state == VoiceServiceState.ready) return;

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() => _isSpeaking = true);
      _tts.setCompletionHandler(() => _isSpeaking = false);
      _tts.setCancelHandler(() => _isSpeaking = false);
      _tts.setErrorHandler((msg) {
        debugPrint('[Voice] TTS error: $msg');
        _isSpeaking = false;
      });

      _setState(VoiceServiceState.ready);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(VoiceServiceState.error);
      rethrow;
    }
  }

  /// Synthesizes [text] to speech and plays it back through the device
  /// speaker, replacing anything queued or currently playing.
  Future<void> speak(String text) async {
    if (_state != VoiceServiceState.ready || text.trim().isEmpty) return;

    _queue
      ..clear()
      ..add(text);
    await _stopCurrentUtterance();
    unawaited(_drainQueue());
  }

  /// Appends [text] to the speech queue without interrupting playback
  /// already in progress — used to speak a streaming response
  /// sentence-by-sentence as each sentence finishes, instead of waiting for
  /// the whole response before speaking any of it.
  void enqueue(String text) {
    if (_state != VoiceServiceState.ready || text.trim().isEmpty) return;

    _queue.add(text);
    debugPrint('[Voice] enqueued (${text.length} chars), queue depth ${_queue.length}');
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      debugPrint('[Voice] speaking now (${next.length} chars)');
      try {
        await _tts.speak(next);
      } catch (e) {
        debugPrint('[Voice] TTS error: $e');
      }
    }
    _draining = false;
  }

  Future<void> _stopCurrentUtterance() async {
    if (!_isSpeaking) return;
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Clears any queued sentences and stops playback immediately.
  Future<void> stopSpeaking() async {
    _queue.clear();
    await _stopCurrentUtterance();
  }

  Future<void> dispose() async {
    await stopSpeaking();
    _state = VoiceServiceState.idle;
  }
}
