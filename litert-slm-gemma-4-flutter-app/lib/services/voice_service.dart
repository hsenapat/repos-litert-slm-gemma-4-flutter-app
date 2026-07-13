import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

// ── Model config ────────────────────────────────────────────────────────────
// Piper VITS, English (US), "amy-low" — single speaker, ~67MB, fast CPU synthesis.
const _ttsModelDir = 'vits-piper-en_US-amy-low';
const _ttsUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$_ttsModelDir.tar.bz2';
const _ttsSizeBytes = 67000000;

enum VoiceServiceState { idle, downloading, loading, ready, error }

/// Wraps sherpa-onnx offline VITS synthesis (TTS). Downloads and extracts the
/// model on first run, then keeps a persistent synthesizer for the lifetime
/// of the app. STT is handled separately via the `speech_to_text` package.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  VoiceServiceState _state = VoiceServiceState.idle;
  VoiceServiceState get state => _state;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void Function(VoiceServiceState)? onStateChanged;

  sherpa_onnx.OfflineTts? _tts;

  final _player = AudioPlayer();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  void _setState(VoiceServiceState s) {
    _state = s;
    onStateChanged?.call(s);
  }

  Future<void> initialize() async {
    if (_state == VoiceServiceState.ready) return;

    try {
      sherpa_onnx.initBindings();

      final supportDir = await getApplicationSupportDirectory();
      _setState(VoiceServiceState.downloading);

      final ttsDir = await _ensureModel(
        url: _ttsUrl,
        modelDirName: _ttsModelDir,
        destRoot: supportDir.path,
        approxSize: _ttsSizeBytes,
        baseProgress: 0.0,
        weight: 1.0,
      );

      _setState(VoiceServiceState.loading);
      _tts = _createTts(ttsDir);

      _setState(VoiceServiceState.ready);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(VoiceServiceState.error);
      rethrow;
    }
  }

  // ── Model download + extraction ─────────────────────────────────────────

  Future<String> _ensureModel({
    required String url,
    required String modelDirName,
    required String destRoot,
    required int approxSize,
    required double baseProgress,
    required double weight,
  }) async {
    final modelDir = Directory(p.join(destRoot, modelDirName));
    final doneMarker = File(p.join(modelDir.path, '.extracted'));

    if (doneMarker.existsSync()) {
      _downloadProgress = baseProgress + weight;
      onStateChanged?.call(_state);
      return modelDir.path;
    }

    final archiveFile = File(p.join(destRoot, '$modelDirName.tar.bz2'));
    await _downloadWithProgress(
      url: url,
      dest: archiveFile,
      approxSize: approxSize,
      onProgress: (fraction) {
        _downloadProgress = baseProgress + weight * fraction * 0.7;
        onStateChanged?.call(_state);
      },
    );

    debugPrint('[Voice] Extracting $modelDirName...');
    await _extractTarBz2(archiveFile, destRoot);
    _downloadProgress = baseProgress + weight * 0.95;
    onStateChanged?.call(_state);

    await archiveFile.delete();
    await doneMarker.create(recursive: true);

    _downloadProgress = baseProgress + weight;
    onStateChanged?.call(_state);
    return modelDir.path;
  }

  Future<void> _downloadWithProgress({
    required String url,
    required File dest,
    required int approxSize,
    required void Function(double fraction) onProgress,
  }) async {
    debugPrint('[Voice] Downloading $url');
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    final total = response.contentLength ?? approxSize;

    final sink = dest.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress((received / total).clamp(0.0, 1.0));
    }
    await sink.close();
  }

  Future<void> _extractTarBz2(File archiveFile, String destRoot) async {
    final bytes = await archiveFile.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final entry in archive) {
      // Skip sample wavs / docs bundled with the release — not needed at runtime.
      if (entry.name.contains('test_wavs/') ||
          entry.name.endsWith('README.md') ||
          entry.name.endsWith('notes.md') ||
          entry.name.endsWith('MODEL_CARD')) {
        continue;
      }
      final outPath = p.join(destRoot, entry.name);
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  // ── TTS (text-to-speech) ────────────────────────────────────────────────

  sherpa_onnx.OfflineTts _createTts(String modelDir) {
    final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
      model: p.join(modelDir, 'en_US-amy-low.onnx'),
      tokens: p.join(modelDir, 'tokens.txt'),
      dataDir: p.join(modelDir, 'espeak-ng-data'),
    );
    final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
      vits: vits,
      numThreads: 2,
      provider: 'cpu',
    );
    final config = sherpa_onnx.OfflineTtsConfig(model: modelConfig);
    return sherpa_onnx.OfflineTts(config);
  }

  /// Synthesizes [text] to speech and plays it back through the device
  /// speaker. Cancels any in-flight playback first.
  Future<void> speak(String text) async {
    if (_state != VoiceServiceState.ready || text.trim().isEmpty) return;

    await stopSpeaking();
    _isSpeaking = true;
    try {
      final audio = _tts!.generate(text: text);
      final tempDir = await getTemporaryDirectory();
      final filename = p.join(
        tempDir.path,
        'tts-${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      sherpa_onnx.writeWave(
        filename: filename,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      await _player.play(DeviceFileSource(filename));
      await _player.onPlayerComplete.first;
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    if (!_isSpeaking) return;
    await _player.stop();
    _isSpeaking = false;
  }

  Future<void> dispose() async {
    await stopSpeaking();
    _tts?.free();
    await _player.dispose();
    _state = VoiceServiceState.idle;
  }
}
