import 'dart:async';

import 'package:flutter/material.dart';

/// CR-0080：寵物字幕分頁器。
///
/// 問題：較長的寵物回覆若一次塞滿字幕、或用過快的計時器翻頁，會讓字幕跟語音
/// 對不上——常常寵物第一段話還沒念完，字幕就跳到下一頁。
///
/// 設計（與語音同步、且可由使用者自行翻頁）：
/// - 把回覆依中文／台語標點切成自然短句，再合併成「最多兩、三行、長者好讀」的短頁
///   （每頁約 [_maxCharsPerPage] 字）。
/// - Realtime 文字增長時保留目前頁與既有計時器，不會因每個 delta 都跳回第一頁。
/// - 每頁停留時間依長者友善語速估算；final 文字接手時延續目前頁，不重播第一頁。
/// - 多頁字幕提供上一頁／下一頁與頁碼。使用者手動翻頁後，本輪停止自動翻頁，
///   避免正在閱讀舊頁時被畫面搶走。
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
  /// - true（寵物正在說、字幕跟著語音逐字長出來）：保留目前頁與自動翻頁進度，
  ///   不因高頻文字更新而閃動或重設。
  /// - false（一般 / TTS / 最終靜態文字）：延續目前頁，並保留手動翻頁能力。
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
  bool _manualNavigation = false;

  @override
  void initState() {
    super.initState();
    _apply(resetProgress: true);
  }

  @override
  void didUpdateWidget(covariant PetSubtitleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.streaming != widget.streaming) {
      final previousText = oldWidget.text.trim();
      final nextText = widget.text.trim();
      final sameResponse = previousText.isNotEmpty &&
          nextText.isNotEmpty &&
          (oldWidget.streaming ||
              nextText.startsWith(previousText) ||
              previousText.startsWith(nextText));
      _apply(resetProgress: !sameResponse);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _apply({required bool resetProgress}) {
    final newText = widget.text.trim();
    final nextPages = _paginate(newText);

    if (resetProgress) {
      _timer?.cancel();
      _timer = null;
      _pageIndex = 0;
      _manualNavigation = false;
    } else if (nextPages.isEmpty) {
      _pageIndex = 0;
    } else {
      _pageIndex = _pageIndex.clamp(0, nextPages.length - 1);
    }

    _pages = nextPages;
    if (!_manualNavigation && _timer == null && _pages.length > 1) {
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    if (_manualNavigation || _pageIndex >= _pages.length - 1) return;
    _timer = Timer(_durationFor(_pages[_pageIndex]), () {
      if (!mounted) return;
      _timer = null;
      if (_manualNavigation || _pageIndex >= _pages.length - 1) return;
      setState(() => _pageIndex++);
      _scheduleNext();
    });
  }

  void _selectPage(int index) {
    if (_pages.isEmpty) return;
    final target = index.clamp(0, _pages.length - 1);
    _timer?.cancel();
    _timer = null;
    setState(() {
      _manualNavigation = true;
      _pageIndex = target;
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
          _PageControls(
            pageIndex: _pageIndex,
            pageCount: _pages.length,
            onPrevious:
                _pageIndex > 0 ? () => _selectPage(_pageIndex - 1) : null,
            onNext: _pageIndex < _pages.length - 1
                ? () => _selectPage(_pageIndex + 1)
                : null,
          ),
        ],
      ],
    );
  }

  // ---- 分頁設定 ----

  /// 每頁字數上限（長者友善：約兩行）。
  static const int _maxCharsPerPage = 28;

  /// Realtime 中文語音約每秒 4 字；略留閱讀緩衝，但不能慢到語音已進下一句、
  /// 字幕仍停在上一頁。
  static const double _charsPerSecond = 4.0;

  /// 每頁最短停留時間，避免極短句一閃而過。
  static const Duration _minPageDuration = Duration(milliseconds: 2200);

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
      final end = (i + _maxCharsPerPage) > runes.length
          ? runes.length
          : i + _maxCharsPerPage;
      out.add(String.fromCharCodes(runes.sublist(i, end)));
    }
    return out;
  }
}

/// 長者友善分頁控制：大按鈕、明確頁碼，並提供語意標籤給 VoiceOver。
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.pageIndex,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final color = Colors.indigo.shade500;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('pet-subtitle-previous-page'),
          tooltip: '上一頁字幕',
          onPressed: onPrevious,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.chevron_left, size: 32),
        ),
        Expanded(
          child: Semantics(
            label: '字幕第 ${pageIndex + 1} 頁，共 $pageCount 頁',
            child: Text(
              '${pageIndex + 1} / $pageCount',
              key: const ValueKey('pet-subtitle-page-label'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('pet-subtitle-next-page'),
          tooltip: '下一頁字幕',
          onPressed: onNext,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.chevron_right, size: 32),
        ),
      ],
    );
  }
}
