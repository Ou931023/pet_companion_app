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
    this.streaming = false,
  });

  final String userText;
  final String temporaryUserText;
  final String temporaryUserStatus;
  final String petText;
  final String petName;
  final bool isWaiting;
  final bool compact;

  /// CR-0084：寵物字幕是否為「即時逐字串流中」（跟著語音走、顯示最新一頁、不用計時器翻頁）。
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final normalizedUserText = userText.trim();
    final normalizedTemporaryText = temporaryUserText.trim();
    final normalizedTemporaryStatus = temporaryUserStatus.trim();
    final normalizedPetText = petText.trim();
    final hasPet = normalizedPetText.isNotEmpty;
    final hasFinalUser = normalizedUserText.isNotEmpty;
    final hasTempUser = normalizedTemporaryText.isNotEmpty;

    final String speakerLabel;
    final String bodyText;
    final bool waitingState;
    if (hasPet) {
      speakerLabel = petName;
      bodyText = normalizedPetText;
      waitingState = false;
    } else if (hasFinalUser) {
      speakerLabel = '你說';
      bodyText = normalizedUserText;
      waitingState = false;
    } else if (hasTempUser) {
      speakerLabel = normalizedTemporaryStatus.isNotEmpty
          ? '你說・$normalizedTemporaryStatus'
          : '你說';
      bodyText = normalizedTemporaryText;
      waitingState = false;
    } else if (isWaiting) {
      speakerLabel = petName;
      bodyText = '';
      waitingState = true;
    } else {
      speakerLabel = petName;
      bodyText = '';
      waitingState = false;
    }

    return SpeechBubble(
      key: const ValueKey('latest-pet-message-bubble'),
      text: bodyText,
      speaker: speakerLabel,
      isWaiting: waitingState,
      compact: compact,
      // CR-0080：只有寵物字幕分頁（與語音同步）；使用者那側維持單塊顯示。
      enablePaging: hasPet,
      // CR-0084：寵物即時逐字字幕時，分頁器跟著文字成長顯示最新一頁、不用計時器翻頁。
      streaming: hasPet && streaming,
    );
  }
}
