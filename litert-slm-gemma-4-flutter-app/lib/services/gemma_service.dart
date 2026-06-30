import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/rag_chunk.dart';

// ── Model config ────────────────────────────────────────────────────────────
// Gemma 4 E2B: 2.4 GB — great quality, no ANR on iOS/macOS.
const _gemmaUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _gemmaFilename = 'gemma-4-E2B-it.litertlm';

// Qwen3 0.6B: 586 MB — litertlm format (LiteRT-LM engine), loads fast on Android.
const _qwenUrl =
    'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm';
const _qwenFilename = 'Qwen3-0.6B.litertlm';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

String get _modelUrl => _isAndroid ? _qwenUrl : _gemmaUrl;
String get _modelFilename => _isAndroid ? _qwenFilename : _gemmaFilename;
ModelType get _modelType => _isAndroid ? ModelType.qwen3 : ModelType.gemma4;
ModelFileType get _modelFileType => ModelFileType.litertlm;
// Qwen3 0.6B produces invalid tokens on Android GPU (Adreno) — use CPU.
PreferredBackend get _preferredBackend =>
    _isAndroid ? PreferredBackend.cpu : PreferredBackend.gpu;

// ── System instruction ───────────────────────────────────────────────────────
const _baseSystemInstruction =
    'You are a marine technical assistant. '
    'You will be given excerpts from ship manuals. '
    'Answer using the information in those excerpts. '
    'If the excerpts contain partial information, share what is available and note what is missing. '
    'If the manual refers to an external document (e.g. MIDS, drawing set, web link), mention that. '
    'If the question is completely unrelated to ship manuals or marine engineering, say: '
    '"This question is out of scope of the ship manuals database." '
    'Do not add information not present in the excerpts.';

// Qwen3 thinking mode is on by default — /no_think disables it on Android.
String get _systemInstruction =>
    _isAndroid ? '$_baseSystemInstruction\n/no_think' : _baseSystemInstruction;

// ── Service ──────────────────────────────────────────────────────────────────
enum GemmaServiceState { idle, downloading, loading, ready, error }

class GemmaService {
  GemmaService._();
  static final GemmaService instance = GemmaService._();

  GemmaServiceState _state = GemmaServiceState.idle;
  GemmaServiceState get state => _state;

  InferenceModel? _model;
  InferenceChat? _chat;
  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void Function(GemmaServiceState)? onStateChanged;

  void _setState(GemmaServiceState s) {
    _state = s;
    onStateChanged?.call(s);
  }

  Future<void> initialize() async {
    if (_state == GemmaServiceState.ready) return;

    try {
      _setState(GemmaServiceState.downloading);
      await _installModel();

      _setState(GemmaServiceState.loading);
      InferenceModel? model;
      try {
        model = await FlutterGemma.getActiveModel(
          maxTokens: 2048,
          preferredBackend: _preferredBackend,
        );
      } catch (e) {
        if (e.toString().contains('no longer installed')) {
          await FlutterGemma.uninstallModel(_modelFilename);
          _setState(GemmaServiceState.downloading);
          await _installModel();
          _setState(GemmaServiceState.loading);
        }
        model = await FlutterGemma.getActiveModel(
          maxTokens: 2048,
          preferredBackend: _preferredBackend,
        );
      }

      _model = model;
      _chat = await _model!.createChat(
        modelType: _modelType,
        systemInstruction: _systemInstruction,
      );
      _setState(GemmaServiceState.ready);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(GemmaServiceState.error);
      rethrow;
    }
  }

  Future<void> _installModel() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File(p.join(dir.path, _modelFilename));

    if (modelFile.existsSync()) {
      debugPrint('[Gemma] Installing from file: $_modelFilename');
      await FlutterGemma.installModel(
        modelType: _modelType,
        fileType: _modelFileType,
      ).fromFile(modelFile.path).install();
    } else {
      debugPrint('[Gemma] Downloading: $_modelFilename');
      await FlutterGemma.installModel(
        modelType: _modelType,
        fileType: _modelFileType,
      ).fromNetwork(_modelUrl).withProgress((pp) {
        _downloadProgress = pp / 100.0;
        onStateChanged?.call(GemmaServiceState.downloading);
      }).install();
    }
  }

  Stream<String> sendMessage(
    String text, {
    List<RagChunk> context = const [],
  }) async* {
    if (_chat == null) throw StateError('Model not loaded');

    await resetChat();

    final contextBlock = context.isEmpty
        ? ''
        : '\n\n[Reference context from ship manuals:]\n'
            '${context.map((c) => '- ${_truncate(c.text, 150)}').join('\n')}\n\n';
    final augmentedText = '$contextBlock$text';

    await _chat!.addQueryChunk(Message.text(text: augmentedText, isUser: true));
    await for (final response in _chat!.generateChatResponseAsync()) {
      if (response is TextResponse) yield response.token;
    }
  }

  Future<void> resetChat() async {
    if (_model == null) return;
    _chat = await _model!.createChat(
      modelType: _modelType,
      systemInstruction: _systemInstruction,
    );
  }

  String _truncate(String s, int maxWords) {
    final words = s.split(' ');
    return words.length <= maxWords ? s : '${words.take(maxWords).join(' ')}…';
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _chat = null;
    _setState(GemmaServiceState.idle);
  }
}
