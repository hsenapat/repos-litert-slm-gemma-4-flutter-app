import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/gemma_service.dart';
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
    if (_service.state == GemmaServiceState.idle) {
      _service.initialize();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _service.onStateChanged = null;
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

    final buffer = StringBuffer();
    try {
      await for (final token in _service.sendMessage(text)) {
        buffer.write(token);
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: buffer.toString(),
            role: MessageRole.model,
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
        GemmaServiceState.loading => const _StatusMessage(
            icon: Icons.memory,
            message: 'Loading model into memory...',
          ),
        GemmaServiceState.error => _ErrorView(
            message: _service.errorMessage ?? 'Unknown error',
            onRetry: _service.initialize,
          ),
        GemmaServiceState.ready => _ChatBody(
            messages: _messages,
            scrollController: _scrollController,
            inputController: _inputController,
            isGenerating: _isGenerating,
            onSend: _sendMessage,
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
