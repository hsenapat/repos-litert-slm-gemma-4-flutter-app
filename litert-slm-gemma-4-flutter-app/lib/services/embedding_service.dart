import 'package:flutter_gemma/flutter_gemma.dart';

class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService instance = EmbeddingService._();

  // Embedding model is initialized by flutter_gemma via LiteRtEmbeddingBackend()
  // in main.dart. This service is a thin accessor.
  EmbeddingModel? get model =>
      FlutterGemmaPlugin.instance.initializedEmbeddingModel;

  bool get isReady => model != null;

  Future<void> initialize() async {
    // No-op: model lifecycle is managed by FlutterGemma.initialize().
  }

  void dispose() {}
}
