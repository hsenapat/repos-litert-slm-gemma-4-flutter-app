import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/gemma_service.dart';
import '../services/rag_service.dart';
import '../services/stt_service.dart';
import '../services/voice_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _service = GemmaService.instance;
  final _messages = <ChatMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isGenerating = false;

  // STT (Whisper, on-device via whisper_kit)
  final _stt = WhisperSttService.instance;
  bool _isListening = false;

  // TTS (platform on-device engine via flutter_tts)
  final _voice = VoiceService.instance;
  bool _autoSpeak = true;

  @override
  void initState() {
    super.initState();
    _service.onStateChanged = (_) => setState(() {});
    RagService.instance.onProgressChanged = () => setState(() {});
    _stt.onStateChanged = (_) => setState(() {});
    _stt.onTranscribingChanged = () => setState(() {});
    if (_service.state == GemmaServiceState.idle) {
      _service.initialize();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RagService.instance.initialize();
      _stt.initialize().catchError((e) {
        debugPrint('[STT] init failed: $e');
      });
      _voice.initialize().catchError((e) {
        debugPrint('[Voice] init failed: $e');
      });
    });
  }

  /// Shared by manual stop (mic tapped again) and silence-triggered
  /// auto-stop: turns the mic indicator off and sends whatever was
  /// transcribed.
  Future<void> _finishListening(String text) async {
    debugPrint('[STT] _finishListening: "$text"');
    if (!mounted) return;
    setState(() => _isListening = false);

    final words = text.trim();
    if (words.isEmpty) {
      _showSnackBar('No speech detected. Please try again.');
      return;
    }

    _inputController.text = words;
    _inputController.selection = TextSelection.collapsed(
      offset: words.length,
    );
    _sendMessage();
  }

  Future<void> _toggleListening() async {
    debugPrint('[STT] mic tapped, _isListening=$_isListening');
    if (_isListening) {
      final text = await _stt.stopListening();
      await _finishListening(text);
      return;
    }

    if (_stt.state != SttServiceState.ready) {
      _showSnackBar('Speech recognition is still getting ready.');
      return;
    }

    // Don't let the assistant's own voice bleed into the mic.
    await _voice.stopSpeaking();

    setState(() => _isListening = true);
    _inputController.clear();

    try {
      await _stt.startListening(onAutoStop: _finishListening);
    } catch (e) {
      debugPrint('[STT] listen failed: $e');
      setState(() => _isListening = false);
      _showSnackBar('Could not access the microphone.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _service.onStateChanged = null;
    RagService.instance.onProgressChanged = null;
    _stt.onStateChanged = null;
    _stt.onTranscribingChanged = null;
    _stt.cancelListening();
    _voice.stopSpeaking();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, role: MessageRole.user));
      _messages.add(
        ChatMessage(text: '', role: MessageRole.model, isThinking: true),
      );
      _isGenerating = true;
    });
    _scrollToBottom();

    if (!RagService.instance.isReady) {
      setState(() {
        _messages[_messages.length - 1] = const ChatMessage(
          text: 'The ship manual index is still being built. '
              'This only happens once — please try again in a moment.',
          role: MessageRole.model,
        );
        _isGenerating = false;
      });
      return;
    }

    final relevant = await RagService.instance.retrieve(text);
    dev.log(
      'retrieve → ${relevant.length} chunks | '
      'scores: ${relevant.map((c) => c.score.toStringAsFixed(3)).join(', ')}',
      name: 'Chat',
    );

    if (relevant.isEmpty) {
      setState(() {
        _messages[_messages.length - 1] = const ChatMessage(
          text: 'This question is out of scope of the RAG database. '
              'I can only answer questions related to the ship manuals '
              '(main engines, ballast water, heat exchangers, fuel systems, '
              'lubrication, emissions, and marine regulations).',
          role: MessageRole.model,
        );
        _isGenerating = false;
      });
      return;
    }

    if (_autoSpeak) await _voice.stopSpeaking();

    final buffer = StringBuffer();
    var spokenUpTo = 0;
    try {
      await for (final token in _service.sendMessage(text, context: relevant)) {
        buffer.write(token);
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: buffer.toString(),
            role: MessageRole.model,
            sources: relevant,
          );
        });
        _scrollToBottom();

        if (_autoSpeak) {
          spokenUpTo = _speakReadySentences(buffer.toString(), spokenUpTo);
        }
      }
      if (_autoSpeak) {
        final remainder = buffer.toString().substring(spokenUpTo).trim();
        if (remainder.isNotEmpty) {
          debugPrint(
            '[Voice] queuing remainder at stream end (${remainder.length} chars)',
          );
          _voice.enqueue(remainder);
        }
      }
    } catch (e) {
      setState(() {
        _messages[_messages.length - 1] = ChatMessage(
          text: 'Error: $e',
          role: MessageRole.model,
        );
      });
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  /// Enqueues complete sentences found in [text] (after [from]) to TTS as
  /// soon as they're finished, so speech starts while the model is still
  /// generating rather than waiting for the full response. A `.`/`!`/`?` is
  /// only treated as a sentence end once the character after it is known
  /// and is whitespace — this avoids splitting on things like "10.5" before
  /// the rest of the token has arrived. Returns the new spoken-up-to index.
  int _speakReadySentences(String text, int from) {
    var start = from;
    for (var i = from; i < text.length - 1; i++) {
      final isSentenceEnd =
          '.!?'.contains(text[i]) && (text[i + 1] == ' ' || text[i + 1] == '\n');
      if (isSentenceEnd || text[i] == '\n') {
        final chunk = text.substring(start, i + 1).trim();
        if (chunk.isNotEmpty) {
          debugPrint(
            '[Voice] queuing mid-stream sentence (${chunk.length} chars) '
            'at token-buffer length ${text.length}',
          );
          _voice.enqueue(chunk);
        }
        start = i + 1;
      }
    }
    return start;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _resetChat() async {
    await _voice.stopSpeaking();
    await _service.resetChat();
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.tertiary,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.anchor, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  'Synergy RAG Offline SLM for Marine Engineering',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_service.state == GemmaServiceState.ready) ...[
            IconButton(
              icon: Icon(_autoSpeak ? Icons.volume_up : Icons.volume_off),
              tooltip: _autoSpeak ? 'Mute spoken replies' : 'Speak replies aloud',
              onPressed: () => setState(() => _autoSpeak = !_autoSpeak),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New conversation',
              onPressed: _isGenerating ? null : _resetChat,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          switch (_service.state) {
            GemmaServiceState.downloading => _DownloadProgress(
                progress: _service.downloadProgress,
              ),
            GemmaServiceState.loading => const _LoadingModelScreen(),
            GemmaServiceState.error => _ErrorView(
                message: _service.errorMessage ?? 'Unknown error',
                onRetry: _service.initialize,
              ),
            GemmaServiceState.ready => _ChatBody(
                messages: _messages,
                scrollController: _scrollController,
                inputController: _inputController,
                isGenerating: _isGenerating,
                // Recording (mic pulse) and transcribing (silent processing
                // after you stop talking) are distinct phases now that STT
                // has no incremental output — _isListening alone used to
                // cover both, which made the whole thing look like one
                // long, unexplained "Listening…" hang.
                isListening: _isListening && !_stt.isTranscribing,
                isTranscribing: _stt.isTranscribing,
                sttAvailable: _stt.state == SttServiceState.ready,
                onSend: _sendMessage,
                onMicTap: _toggleListening,
                onSpeak: _voice.speak,
              ),
            _ => const _StatusMessage(
                icon: Icons.hourglass_empty,
                message: 'Initializing...',
              ),
          },
          // Voice input (Whisper) and RAG index downloads run in the
          // background from app launch, independent of the main model's
          // state — surfaced here so they're visible even while the chat
          // screen above is still showing a Gemma download/loading/error
          // view, instead of being silently hidden until Gemma is ready.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (RagService.instance.isPopulating)
                  _RagProgressBanner(
                    progress: RagService.instance.populationProgress ?? 0.0,
                  ),
                if (_stt.state == SttServiceState.downloading ||
                    _stt.state == SttServiceState.loading)
                  _VoiceModelBanner(
                    loading: _stt.state == SttServiceState.loading,
                    progress: _stt.downloadProgress,
                  ),
                if (_stt.state == SttServiceState.error)
                  _SttErrorBanner(
                    message: _stt.errorMessage ?? 'Unknown error',
                    onRetry: () => _stt.initialize().catchError((e) {
                      debugPrint('[STT] retry init failed: $e');
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Download progress ─────────────────────────────────────────────────────────

class _DownloadProgress extends StatelessWidget {
  final double progress;
  const _DownloadProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Downloading Gemma 4 E2B',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '~1.5 GB — one-time download',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('${(progress * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }
}

// ── Generic status / error widgets ───────────────────────────────────────────

class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  const _StatusMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading model screen with elapsed timer ───────────────────────────────────

class _LoadingModelScreen extends StatefulWidget {
  const _LoadingModelScreen();

  @override
  State<_LoadingModelScreen> createState() => _LoadingModelScreenState();
}

class _LoadingModelScreenState extends State<_LoadingModelScreen> {
  late final Timer _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _elapsed {
    if (_seconds < 60) return '${_seconds}s';
    return '${_seconds ~/ 60}m ${_seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Loading model into memory… $_elapsed',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Takes 1–3 min on first launch',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sample questions ──────────────────────────────────────────────────────────

const _kSampleQuestions = [
  'What is the fuel injection control process for the MAN G95ME-C10.5-GI engine?',
  'What are the turbocharger options for the WinGD X92-B engine?',
  'What NOx emission limits apply to MAN marine engines under Tier III regulations?',
  'What safety precautions are required during ammonia bunkering on a vessel?',
  'How does the WinGD X62DF ammonia fuel system work?',
  'What are the IMO D-2 discharge standards for ballast water treatment?',
  'How does UV-based ballast water treatment compare to electrochlorination?',
  'What is the procedure for replacing gaskets on an Alfa Laval plate heat exchanger?',
  'What refrigerants are supported in Alfa Laval marine refrigeration systems?',
  'How should cylinder lubrication be adjusted for low-sulphur fuel operation after 2020?',
];

// ── Chat body ─────────────────────────────────────────────────────────────────

class _ChatBody extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final TextEditingController inputController;
  final bool isGenerating;
  final bool isListening;
  final bool isTranscribing;
  final bool sttAvailable;
  final VoidCallback onSend;
  final VoidCallback onMicTap;
  final void Function(String text) onSpeak;

  const _ChatBody({
    required this.messages,
    required this.scrollController,
    required this.inputController,
    required this.isGenerating,
    required this.isListening,
    required this.isTranscribing,
    required this.sttAvailable,
    required this.onSend,
    required this.onMicTap,
    required this.onSpeak,
  });

  void _pickSampleQuestion(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Sample questions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _kSampleQuestions.length,
                separatorBuilder: (_, i) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (ctx, i) => ListTile(
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    _kSampleQuestions[i],
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () => Navigator.pop(ctx, _kSampleQuestions[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((selected) {
      if (selected != null) {
        inputController.text = selected;
        inputController.selection =
            TextSelection.collapsed(offset: selected.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'Ask a marine engineering question…',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => MessageBubble(
                    message: messages[i],
                    onSpeak: messages[i].role == MessageRole.model &&
                            !messages[i].isThinking &&
                            messages[i].text.trim().isNotEmpty
                        ? () => onSpeak(messages[i].text)
                        : null,
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Row(
            children: [
              // Sample questions button
              IconButton(
                onPressed:
                    isGenerating ? null : () => _pickSampleQuestion(context),
                tooltip: 'Sample questions',
                icon: const Icon(Icons.lightbulb_outline),
              ),
              // Mic button
              _MicButton(
                isListening: isListening,
                isTranscribing: isTranscribing,
                enabled: sttAvailable && !isGenerating && !isTranscribing,
                onTap: onMicTap,
              ),
              const SizedBox(width: 4),
              // Text input
              Expanded(
                child: TextField(
                  controller: inputController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: isListening
                        ? 'Listening…'
                        : isTranscribing
                            ? 'Transcribing…'
                            : 'Message Gemma...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              FilledButton(
                onPressed: isGenerating ? null : onSend,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Mic button with animated pulse when listening ─────────────────────────────

class _MicButton extends StatefulWidget {
  final bool isListening;
  final bool isTranscribing;
  final bool enabled;
  final VoidCallback onTap;

  const _MicButton({
    required this.isListening,
    required this.isTranscribing,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final scale = widget.isListening ? 1.0 + _pulse.value * 0.15 : 1.0;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: IconButton(
        onPressed: widget.enabled ? widget.onTap : null,
        tooltip: widget.isTranscribing
            ? 'Transcribing…'
            : widget.isListening
                ? 'Stop listening'
                : 'Speak',
        style: IconButton.styleFrom(
          backgroundColor: widget.isListening
              ? colorScheme.error.withValues(alpha: 0.15)
              : null,
        ),
        icon: widget.isTranscribing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(
                widget.isListening ? Icons.mic : Icons.mic_none,
                color: widget.isListening ? colorScheme.error : null,
              ),
      ),
    );
  }
}

// ── RAG progress banner ───────────────────────────────────────────────────────

class _RagProgressBanner extends StatelessWidget {
  final double progress;
  const _RagProgressBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toStringAsFixed(0);
    return Material(
      elevation: 2,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Building ship manual index… $pct%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress),
          ],
        ),
      ),
    );
  }
}

// ── Voice model download banner ─────────────────────────────────────────────

class _VoiceModelBanner extends StatelessWidget {
  final bool loading;
  final double progress;
  const _VoiceModelBanner({required this.loading, required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toStringAsFixed(0);
    return Material(
      elevation: 2,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loading
                        ? 'Preparing speech recognition model…'
                        : 'Downloading speech recognition model (Whisper)… $pct%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: loading ? null : progress),
          ],
        ),
      ),
    );
  }
}

// ── Voice model error banner ─────────────────────────────────────────────

class _SttErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SttErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      child: Container(
        color: colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.mic_off, size: 16, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Voice input unavailable: $message',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
