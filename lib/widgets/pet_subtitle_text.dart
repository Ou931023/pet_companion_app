import 'dart:async';

import 'package:flutter/material.dart';

/// CR-0080：寵物字幕分頁器。
///
/// 問題：較長的寵物回覆若一次塞滿字幕、或用過快的計時器翻頁，會讓字幕跟語音
/// 對不上——常常寵物第一段話還沒念完，字幕就跳到下一頁。
///
/// 設計（與語音同步、且「絕不提前翻頁」）：
/// - 把回覆依中文／台語標點切成自然短句，再合併成「最多兩、三行、長者好讀」的短頁
///   （每頁約 [_maxCharsPerPage] 字）。
/// - 每頁停留時間用「保守估算」：以略慢於語音念稿的速度（約每秒 [_charsPerSecond] 字、
///   且至少 [_minPageDuration]）來估，確保字幕只會「跟在語音後面」，不會搶在寵物
///   還沒念完就翻頁。
/// - 只有「需要分頁的長回覆」才會啟動計時器；短回覆只有一頁、行為與過去相同、
///   不會留下待處理的計時器。
/// - 新的一輪回覆（text 改變）會從第一頁重新開始。
class PetSubtitleText extends StatefulWidget {
  const PetSubtitleText({
    super.key,
    required this.text,
    required this.textStyle,
    this.streaming = false,
  });

  final String text;
  final TextStyle textStyle;

  /// CR-0084：是否為「即時逐字串流中」。
  /// - true（寵物正在說、字幕跟著語音逐字長出來）：分頁後**永遠顯示最新一頁**，
  ///   不用計時器自動翻頁——翻頁完全由文字成長驅動，所以絕不會超前語音。
  /// - false（一般 / TTS / 最終靜態文字）：維持 CR-0080 的保守計時器分頁。
  final bool streaming;

  @override
  State<PetSubtitleText> createState() => _PetSubtitleTextState();

  /// 對外暴露分頁邏輯，方便測試（不牽涉 UI / 計時器）。
  @visibleForTesting
  static List<String> paginateForTest(String raw) =>
      _PetSubtitleTextState._paginate(raw);
}

class _PetSubtitleTextState extends State<PetSubtitleText> {
  List<String> _pages = const [];
  int _pageIndex = 0;
  Timer? _timer;
  String _renderedText = '';
  bool _wasStreaming = false;

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(covariant PetSubtitleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.streaming != widget.streaming) {
      _apply();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _apply() {
    _timer?.cancel();
    final newText = widget.text.trim();
    _pages = _paginate(newText);
    final lastIndex = _pages.isEmpty ? 0 : _pages.length - 1;

    if (widget.streaming) {
      // 串流中：永遠停在最新一頁；翻頁由文字成長驅動，不排計時器（絕不超前語音）。
      _pageIndex = lastIndex;
    } else {
      // 「延續」：剛從串流結束、或文字是前一段的延伸（同一句最終落地）→ 停在最後一頁，
      // 不要倒回第一頁重新用計時器跑（語音已念到那裡了）。
      final continues = newText.isNotEmpty &&
          _renderedText.isNotEmpty &&
          newText.startsWith(_renderedText);
      if (_wasStreaming || continues) {
        _pageIndex = lastIndex;
      } else {
        // 全新的一段（例如打字 TTS 回覆）→ 從第一頁開始、保守計時器分頁。
        _pageIndex = 0;
        if (_pages.length > 1) {
          _scheduleNext();
        }
      }
    }

    _renderedText = newText;
    _wasStreaming = widget.streaming;
  }

  void _scheduleNext() {
    if (_pageIndex >= _pages.length - 1) return;
    _timer = Timer(_durationFor(_pages[_pageIndex]), () {
      if (!mounted) return;
      setState(() => _pageIndex++);
      _scheduleNext();
    });
  }

  static Duration _durationFor(String page) {
    final estimateMs = (page.runes.length / _charsPerSecond * 1000).round();
    return estimateMs < _minPageDuration.inMilliseconds
        ? _minPageDuration
        : Duration(milliseconds: estimateMs);
  }

  @override
  Widget build(BuildContext context) {
    final pageText = _pages.isEmpty
        ? widget.text.trim()
        : _pages[_pageIndex.clamp(0, _pages.length - 1)];
    final showIndicator = _pages.length > 1;
    final pageWidget = Text(
      pageText,
      key: ValueKey('pet-subtitle-page-$_pageIndex'),
      // 保留一行安全餘裕（目標兩行），避免窄螢幕把該頁尾字裁掉而漏字。
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: widget.textStyle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 串流中：文字會高頻成長，用 AnimatedSwitcher 的淡入淡出會一直閃；
        // 改成直接就地更新（不動畫），畫面穩定。非串流（TTS / 靜態）才用淡入淡出讓翻頁柔和。
        if (widget.streaming)
          pageWidget
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: pageWidget,
          ),
        if (showIndicator) ...[
          const SizedBox(height: 6),
          _PageDots(count: _pages.length, active: _pageIndex),
        ],
      ],
    );
  }

  // ---- 分頁設定 ----

  /// 每頁字數上限（長者友善：約兩行）。
  static const int _maxCharsPerPage = 28;

  /// 念稿速度保守估每秒約 3.2 字——刻意比實際語音（約每秒 4 字）慢，
  /// 讓字幕只會落在語音後面，不會提前翻頁。
  static const double _charsPerSecond = 3.2;

  /// 每頁最短停留時間，避免極短句一閃而過。
  static const Duration _minPageDuration = Duration(milliseconds: 2800);

  /// 斷句標點（中文 / 台語常用），標點留在前一段尾端。
  static const String _breakers = '。！？，、；：';

  static List<String> _paginate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    if (text.runes.length <= _maxCharsPerPage) return [text];

    final segments = _splitIntoSegments(text);
    final pages = <String>[];
    final buffer = StringBuffer();
    for (final segment in segments) {
      if (buffer.isEmpty) {
        buffer.write(segment);
        continue;
      }
      if (buffer.length + segment.length <= _maxCharsPerPage) {
        buffer.write(segment);
      } else {
        pages.add(buffer.toString());
        buffer
          ..clear()
          ..write(segment);
      }
    }
    if (buffer.isNotEmpty) pages.add(buffer.toString());
    return pages.isEmpty ? [text] : pages;
  }

  static List<String> _splitIntoSegments(String text) {
    final segments = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '\n') {
        if (buffer.isNotEmpty) {
          segments.add(buffer.toString().trim());
          buffer.clear();
        }
        continue;
      }
      buffer.write(ch);
      if (_breakers.contains(ch)) {
        segments.add(buffer.toString());
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) segments.add(buffer.toString());

    // 無標點的超長句硬切，避免單頁爆行。
    final normalized = <String>[];
    for (final seg in segments) {
      final trimmed = seg.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.runes.length <= _maxCharsPerPage) {
        normalized.add(trimmed);
      } else {
        normalized.addAll(_hardWrap(trimmed));
      }
    }
    return normalized;
  }

  static List<String> _hardWrap(String seg) {
    final out = <String>[];
    final runes = seg.runes.toList();
    for (var i = 0; i < runes.length; i += _maxCharsPerPage) {
      final end =
          (i + _maxCharsPerPage) > runes.length ? runes.length : i + _maxCharsPerPage;
      out.add(String.fromCharCodes(runes.sublist(i, end)));
    }
    return out;
  }
}

/// 分頁指示點：讓長者一眼看出字幕還有後續、目前在第幾頁。
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final color = Colors.indigo.shade300;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (index) {
        final isActive = index == active;
        return Container(
          margin: const EdgeInsets.only(right: 5),
          width: isActive ? 9 : 7,
          height: isActive ? 9 : 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color : color.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }
}
