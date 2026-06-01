import 'dart:async';

import 'package:flutter/material.dart';

/// 逐字列印文字。
///
/// - 一個字一個字顯示，列印完成後呼叫 [onCompleted]。
/// - [revealSignal] 被觸發時（例如使用者點了畫面任意處），立刻顯示完整句子
///   （對長者較友善，不強迫等待）。本元件自己不攔截點擊，交由外層統一處理
///   「點一下：先補完文字 → 再點：下一步」，避免巢狀手勢吃掉點擊。
/// - [text] 變更時會自動從頭重新列印。
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.onCompleted,
    this.charDuration = const Duration(milliseconds: 38),
    this.style,
    this.textAlign = TextAlign.start,
    this.revealSignal,
  });

  final String text;
  final VoidCallback? onCompleted;
  final Duration charDuration;
  final TextStyle? style;
  final TextAlign textAlign;

  /// 外部觸發「立刻顯示完整文字」的訊號（每次 notify 都會快轉到底）。
  final Listenable? revealSignal;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  Timer? _timer;
  int _visible = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    widget.revealSignal?.addListener(_completeNow);
    _restart();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealSignal != widget.revealSignal) {
      oldWidget.revealSignal?.removeListener(_completeNow);
      widget.revealSignal?.addListener(_completeNow);
    }
    if (oldWidget.text != widget.text) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    _visible = 0;
    _completed = false;
    if (widget.text.isEmpty) {
      _finish();
      return;
    }
    _timer = Timer.periodic(widget.charDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_visible >= widget.text.length) {
        _finish();
        return;
      }
      setState(() => _visible++);
      if (_visible >= widget.text.length) {
        _finish();
      }
    });
  }

  /// 立刻顯示完整文字並通知完成（外部快轉訊號用）。
  void _completeNow() {
    if (!mounted || _completed) return;
    _timer?.cancel();
    setState(() => _visible = widget.text.length);
    _finish();
  }

  void _finish() {
    _timer?.cancel();
    if (_completed) return;
    _completed = true;
    // 在 frame 之後再通知，避免在 build 過程中觸發父層 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCompleted?.call();
    });
  }

  @override
  void dispose() {
    widget.revealSignal?.removeListener(_completeNow);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _visible.clamp(0, widget.text.length));
    // 不自己攔截點擊：由外層導覽 overlay 統一處理「點一下補完 / 再點下一步」，
    // 避免巢狀手勢吃掉點擊，導致點到文字時無法前進。
    return Text(
      shown,
      textAlign: widget.textAlign,
      style: widget.style,
    );
  }
}
