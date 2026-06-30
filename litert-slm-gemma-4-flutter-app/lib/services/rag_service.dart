import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rag_chunk.dart';

const _geckoModelUrl =
    'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_512_quant.tflite';
const _geckoTokenizerUrl =
    'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model';

const _kDbChecksumKey = 'rag_vector_db_checksum';

class RagService {
  RagService._();
  static final RagService instance = RagService._();

  bool _initialized = false;
  bool get isReady => _initialized;
  Future<void>? _initFuture;

  // Progress is null when not copying, 0.0–1.0 during the brief asset copy.
  double? _populationProgress;
  double? get populationProgress => _populationProgress;
  bool get isPopulating => _populationProgress != null && !_initialized;

  void Function()? onProgressChanged;

  Future<void> initialize() => _initFuture ??= _doInitialize();

  Future<void> _doInitialize() async {
    // Gecko is still needed at query time (to embed the user's question).
    await _ensureEmbedderInstalled();

    try {
      await FlutterGemma.getActiveEmbedder();
    } catch (e) {
      debugPrint('[RAG] No embedding model available — RAG disabled: $e');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final vectorPath = p.join(dir.path, 'rag_vector.db');

    // Checksum of the bundled rag_vector.db asset to detect content updates.
    final assetBytes = await rootBundle.load('assets/manuals/rag_vector.db');
    final currentChecksum =
        md5.convert(assetBytes.buffer.asUint8List()).toString();

    final prefs = await SharedPreferences.getInstance();
    final storedChecksum = prefs.getString(_kDbChecksumKey);
    final dbChanged = storedChecksum != currentChecksum;

    if (dbChanged || !File(vectorPath).existsSync()) {
      debugPrint('[RAG] Copying pre-built vector store from assets (~22 MB)…');
      _populationProgress = 0.0;
      onProgressChanged?.call();

      await File(vectorPath)
          .writeAsBytes(assetBytes.buffer.asUint8List(), flush: true);
      await prefs.setString(_kDbChecksumKey, currentChecksum);

      _populationProgress = 1.0;
      onProgressChanged?.call();
      debugPrint('[RAG] Vector store copied.');
    }

    await FlutterGemmaPlugin.instance.initializeVectorStore(vectorPath);
    final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
    debugPrint('[RAG] Vector store ready: '
        '${stats.documentCount} chunks, dim=${stats.vectorDimension}');

    _initialized = true;
    debugPrint('[RAG] ✅ READY — ask a question now');
  }

  Future<void> _ensureEmbedderInstalled() async {
    try {
      await FlutterGemma.getActiveEmbedder();
      debugPrint('[RAG] Embedding model already active.');
      return;
    } catch (_) {}

    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File(p.join(dir.path, 'Gecko_512_quant.tflite'));
    final tokenizerFile = File(p.join(dir.path, 'sentencepiece.model'));

    if (modelFile.existsSync() && tokenizerFile.existsSync()) {
      debugPrint('[RAG] Gecko files on disk — registering from file…');
      await FlutterGemma.installEmbedder()
          .modelFromFile(modelFile.path)
          .tokenizerFromFile(tokenizerFile.path)
          .install();
    } else {
      debugPrint('[RAG] Downloading Gecko_512_quant…');
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(_geckoModelUrl)
          .tokenizerFromNetwork(_geckoTokenizerUrl)
          .install();
    }
    debugPrint('[RAG] Gecko ready.');
  }

  Future<List<RagChunk>> retrieve(String query, {int topK = 5}) async {
    if (!_initialized) return [];

    try {
      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: query,
        topK: topK * 4,
        threshold: 0.0,
      );

      debugPrint('==== [RAG] raw scores (${results.length} hits): '
          '${results.map((r) => r.similarity.toStringAsFixed(3)).join(', ')} ====');

      // Deduplicate by source document — keep first (highest-score) chunk per source.
      final seen = <String>{};
      final deduped = <dynamic>[];
      for (final r in results) {
        String source = r.id;
        if (r.metadata != null) {
          try {
            final meta = jsonDecode(r.metadata!) as Map<String, dynamic>;
            source = (meta['source'] as String?) ?? source;
          } catch (_) {}
        }
        if (seen.add(source)) deduped.add(r);
        if (deduped.length == topK) break;
      }

      debugPrint('[RAG] deduped scores: '
          '${deduped.map((r) => r.similarity.toStringAsFixed(3)).join(', ')}');

      // Out-of-scope gate — Gecko scores are much lower than MiniLM.
      // Tune this constant from [RAG] log output if results diverge.
      const outOfScopeThreshold = 0.1;
      if (deduped.isEmpty || deduped.first.similarity < outOfScopeThreshold) {
        debugPrint('[RAG] Top score '
            '${deduped.isEmpty ? 0 : deduped.first.similarity.toStringAsFixed(3)}'
            ' < $outOfScopeThreshold — out of scope');
        return [];
      }

      return deduped.map((r) {
        String source = r.id;
        int page = 0;
        if (r.metadata != null) {
          try {
            final meta = jsonDecode(r.metadata!) as Map<String, dynamic>;
            source = (meta['source'] as String?) ?? source;
            page = (meta['page'] as int?) ?? 0;
          } catch (_) {}
        }
        return RagChunk(
          text: r.content,
          source: source,
          page: page,
          score: r.similarity,
        );
      }).toList();
    } catch (e) {
      debugPrint('[RAG] searchSimilar failed: $e');
      return [];
    }
  }

  Future<void> dispose() async {
    _initialized = false;
  }
}
