import 'package:flutter/material.dart';

import 'pet_subtitle_text.dart';

class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.text,
    this.speaker = '寵物',
    this.isWaiting = false,
    this.compact = false,
    this.enablePaging = false,
    this.streaming = false,
  });

  final String text;
  final String speaker;
  final bool isWaiting;
  final bool compact;

  /// CR-0080：是否把較長內容分頁顯示（與語音同步、不提前翻頁）。
  /// 只在「寵物字幕」開啟；使用者泡泡 / 等待狀態維持原本單塊顯示。
  final bool enablePaging;

  /// CR-0084：是否為「即時逐字串流中」——分頁器顯示最新一頁、不用計時器翻頁。
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWaiting ? Icons.more_horiz : Icons.chat_bubble_outline,
            color: Colors.indigo.shade400,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speaker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.indigo.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                _buildBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final textStyle = TextStyle(
      fontSize: compact ? 17 : 18,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: isWaiting ? Colors.black54 : Colors.black87,
      fontStyle: isWaiting ? FontStyle.italic : FontStyle.normal,
    );
    if (isWaiting) {
      return Text(
        '我聽到了，正在想怎麼陪你說。',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }
    if (enablePaging) {
      return PetSubtitleText(
        text: text,
        textStyle: textStyle,
        streaming: streaming,
      );
    }
    return Text(
      text,
      maxLines: compact ? 4 : 6,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );
  }
}
