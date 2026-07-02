import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'screens/chat_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  // Do NOT await anything here — render the first frame immediately so
  // Android's watchdog timer doesn't fire an ANR (~5 s deadline).
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GemmaApp());
}

class GemmaApp extends StatefulWidget {
  const GemmaApp({super.key});

  @override
  State<GemmaApp> createState() => _GemmaAppState();
}

class _GemmaAppState extends State<GemmaApp> {
  bool _splashDone = false;
  bool _frameworkReady = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    // Initialize framework in background — splash plays concurrently.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFramework());
  }

  Future<void> _initFramework() async {
    try {
      debugPrint('[MAIN] Initializing FlutterGemma framework...');
      await FlutterGemma.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
        embeddingBackends: [LiteRtEmbeddingBackend()],
        vectorStore: SqliteVectorStore(),
        huggingFaceToken: '',
      );
      debugPrint('[MAIN] Framework ready.');
      if (mounted) setState(() => _frameworkReady = true);
    } catch (e) {
      debugPrint('[MAIN] Framework init failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  void _onSplashComplete() => setState(() => _splashDone = true);

  Widget _resolveHome() {
    // Show splash until it finishes animating.
    if (!_splashDone) {
      return SplashScreen(onComplete: _onSplashComplete);
    }
    if (_initError != null) {
      return _ErrorScreen(message: _initError!, onRetry: _initFramework);
    }
    if (_frameworkReady) return const ChatScreen();
    return const _InitializingScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synergy RAG Offline SLM for Marine Engineering',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: KeyedSubtree(
          key: ValueKey(_splashDone),
          child: _resolveHome(),
        ),
      ),
    );
  }
}

class _InitializingScreen extends StatelessWidget {
  const _InitializingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Starting up…'),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorScreen({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
