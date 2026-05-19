import 'package:flutter/material.dart';

import 'speech_bubble.dart';

class ConversationBubbleStack extends StatelessWidget {
  const ConversationBubbleStack({
    super.key,
    required this.userText,
    required this.temporaryUserText,
    required this.temporaryUserStatus,
    required this.petText,
    required this.petName,
    required this.isWaiting,
    required this.compact,
  });

  final String userText;
  final String temporaryUserText;
  final String temporaryUserStatus;
  final String petText;
  final String petName;
  final bool isWaiting;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalizedUserText = userText.trim();
    final normalizedTemporaryText = temporaryUserText.trim();
    final normalizedTemporaryStatus = temporaryUserStatus.trim();
    return Column(
      key: const ValueKey('conversation-bubble-stack'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (normalizedUserText.isNotEmpty) ...[
          UserMessageBubble(
            key: const ValueKey('latest-user-message-bubble'),
            text: normalizedUserText,
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        if (normalizedTemporaryText.isNotEmpty) ...[
          UserMessageBubble(
            key: const ValueKey('temporary-user-message-bubble'),
            text: normalizedTemporaryText,
            status: normalizedTemporaryStatus,
            isTemporary: true,
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        SpeechBubble(
          key: const ValueKey('latest-pet-message-bubble'),
          text: petText,
          speaker: petName,
          isWaiting: isWaiting,
          compact: compact,
        ),
      ],
    );
  }
}

class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({
    super.key,
    required this.text,
    this.status = '',
    this.isTemporary = false,
  });

  final String text;
  final String status;
  final bool isTemporary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isTemporary
                ? Colors.indigo.withValues(alpha: 0.58)
                : Colors.indigo,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 7,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_outline,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            isTemporary && status.trim().isNotEmpty
                                ? '你說・${status.trim()}'
                                : '你說',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text.trim(),
                      maxLines: isTemporary ? 3 : 6,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTemporary ? 15 : 16,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
