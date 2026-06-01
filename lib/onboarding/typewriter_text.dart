import 'dart:async';

import 'package:flutter/material.dart';

/// 逐字列印文字。
///
/// - 一個字一個字顯示，列印完成後呼叫 [onCompleted]。
/// - 還在列印時點一下，會立刻顯示完整句子（對長者較友善，不強迫等待）。
/// - [text] 變更時會自動從頭重新列印。
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.onCompleted,
    this.charDuration = const Duration(milliseconds: 38),
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final VoidCallback? onCompleted;
  final Duration charDuration;
  final TextStyle? style;
  final TextAlign textAlign;

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
    _restart();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  /// 立刻顯示完整文字並通知完成（點擊快轉用）。
  void _completeNow() {
    if (_completed) return;
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
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _visible.clamp(0, widget.text.length));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _completeNow,
      child: Text(
        shown,
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
  }
}
