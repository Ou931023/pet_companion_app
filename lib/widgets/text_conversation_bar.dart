import 'package:flutter/material.dart';

class TextConversationBar extends StatelessWidget {
  const TextConversationBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isBusy,
    required this.onChanged,
    required this.onSend,
    this.focusNode,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isBusy;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSend;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: '跟寵物說一句話',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: onChanged,
              onSubmitted: enabled ? onSend : null,
            ),
          ),
          IconButton.filled(
            tooltip: '送出',
            onPressed: enabled ? () => onSend(controller.text) : null,
            icon: isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
