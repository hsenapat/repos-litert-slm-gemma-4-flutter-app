import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/gemma_service.dart';
import '../services/rag_service.dart';
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

  @override
  void initState() {
    super.initState();
    _service.onStateChanged = (_) => setState(() {});
    RagService.instance.onProgressChanged = () => setState(() {});
    if (_service.state == GemmaServiceState.idle) {
      _service.initialize();
    }
    // Delay RAG init until after the first frame so the UI renders first,
    // preventing a black screen when the embedding loop blocks the render thread.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RagService.instance.initialize();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _service.onStateChanged = null;
    RagService.instance.onProgressChanged = null;
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

    // If the vector store is still being built (first launch), reply immediately.
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

    final buffer = StringBuffer();
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
    await _service.resetChat();
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma 4 — On Device'),
        actions: [
          if (_service.state == GemmaServiceState.ready)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New conversation',
              onPressed: _isGenerating ? null : _resetChat,
            ),
        ],
      ),
      body: switch (_service.state) {
        GemmaServiceState.downloading => _DownloadProgress(
            progress: _service.downloadProgress,
          ),
        GemmaServiceState.loading => const _LoadingModelScreen(),
        GemmaServiceState.error => _ErrorView(
            message: _service.errorMessage ?? 'Unknown error',
            onRetry: _service.initialize,
          ),
        GemmaServiceState.ready => Stack(
            children: [
              _ChatBody(
                messages: _messages,
                scrollController: _scrollController,
                inputController: _inputController,
                isGenerating: _isGenerating,
                onSend: _sendMessage,
              ),
              if (RagService.instance.isPopulating)
                _RagProgressBanner(
                  progress: RagService.instance.populationProgress ?? 0.0,
                ),
            ],
          ),
        _ => const _StatusMessage(
            icon: Icons.hourglass_empty,
            message: 'Initializing...',
          ),
      },
    );
  }
}

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
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
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

class _ChatBody extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final TextEditingController inputController;
  final bool isGenerating;
  final VoidCallback onSend;

  const _ChatBody({
    required this.messages,
    required this.scrollController,
    required this.inputController,
    required this.isGenerating,
    required this.onSend,
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
                separatorBuilder: (context, i) => const Divider(height: 1, indent: 16),
                itemBuilder: (ctx, i) => ListTile(
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
        inputController.selection = TextSelection.collapsed(offset: selected.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'Ask Gemma 4 anything',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => MessageBubble(message: messages[i]),
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
              IconButton(
                onPressed: isGenerating ? null : () => _pickSampleQuestion(context),
                tooltip: 'Sample questions',
                icon: const Icon(Icons.lightbulb_outline),
              ),
              Expanded(
                child: TextField(
                  controller: inputController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Message Gemma...',
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

class _RagProgressBanner extends StatelessWidget {
  final double progress;
  const _RagProgressBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toStringAsFixed(0);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
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
      ),
    );
  }
}
