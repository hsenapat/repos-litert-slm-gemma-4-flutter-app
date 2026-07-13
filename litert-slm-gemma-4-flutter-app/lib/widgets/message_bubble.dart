import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/rag_chunk.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSpeak;

  const MessageBubble({super.key, required this.message, this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final sources = message.sources;
    final canSpeak =
        !isUser && !message.isThinking && message.text.trim().isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: message.isThinking
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Thinking...',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  : SelectableText(
                      message.text,
                      style: TextStyle(
                        color: isUser
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
            ),
            if (canSpeak && onSpeak != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  onTap: onSpeak,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.volume_up_outlined,
                      size: 16,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
              ),
            if (!isUser && sources != null && sources.isNotEmpty)
              _SourceCitations(sources: sources),
          ],
        ),
      ),
    );
  }
}

class _SourceCitations extends StatelessWidget {
  final List<RagChunk> sources;
  const _SourceCitations({required this.sources});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(
            'Sources (${sources.length})',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.outline,
            ),
          ),
          iconColor: colorScheme.outline,
          collapsedIconColor: colorScheme.outline,
          children: sources
              .map(
                (c) => Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${c.source}  p.${c.page}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                      Text(
                        '${(c.score * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
