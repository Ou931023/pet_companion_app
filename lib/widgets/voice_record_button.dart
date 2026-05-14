import 'package:flutter/material.dart';

class VoiceRecordButton extends StatelessWidget {
  const VoiceRecordButton({
    super.key,
    required this.isRecording,
    required this.onStart,
    required this.onEnd,
  });

  final bool isRecording;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onStart(),
      onLongPressEnd: (_) => onEnd(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: isRecording ? Colors.redAccent : Colors.indigo,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            isRecording ? '放開送出語音' : '按住說話',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
