import 'package:flutter_gemma/flutter_gemma.dart';

// Official Gemma 4 E2B int4 model from litert-community (~1.5 GB).
const _modelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

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
      // fileType: ModelFileType.litertlm is required so LiteRtLmEngine.canHandle()
      // matches this install spec (default is ModelFileType.task / MediaPipe).
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(_modelUrl).withProgress((p) {
        _downloadProgress = p / 100.0;
        onStateChanged?.call(GemmaServiceState.downloading);
      }).install();

      _setState(GemmaServiceState.loading);
      // preferredBackend: gpu enables Metal acceleration on iOS/macOS.
      // Falls back to CPU automatically if GPU init fails.
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.gpu,
      );
      _chat = await _model!.createChat(
        modelType: ModelType.gemma4,
        systemInstruction: 'You are a helpful assistant. Be concise and accurate.',
      );
      _setState(GemmaServiceState.ready);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(GemmaServiceState.error);
      rethrow;
    }
  }

  Stream<String> sendMessage(String text) async* {
    if (_chat == null) throw StateError('Model not loaded');

    await _chat!.addQueryChunk(Message.text(text: text, isUser: true));
    await for (final response in _chat!.generateChatResponseAsync()) {
      if (response is TextResponse) yield response.token;
    }
  }

  Future<void> resetChat() async {
    if (_model == null) return;
    _chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      systemInstruction: 'You are a helpful assistant. Be concise and accurate.',
    );
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _chat = null;
    _setState(GemmaServiceState.idle);
  }
}
