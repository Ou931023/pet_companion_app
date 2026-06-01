import 'package:flutter/widgets.dart';

/// 一個導覽步驟：要高亮哪個 UI、以及上方要逐字列印的說明文字。
///
/// - [targetKey]：指向要高亮的 widget；overlay 會用它算出高亮框位置。
/// - [rectTransform]：可選，對算出來的框做轉換（例如只取底部導覽列最右邊的「設定」）。
/// - 找不到 target（例如該區塊是原生元件或還沒繪製）時，overlay 會改成
///   「整個畫面變暗 + 文字置中」的降級顯示，仍然看得到說明。
class CoachMarkStep {
  const CoachMarkStep({
    required this.text,
    this.targetKey,
    this.rectTransform,
    this.radius = 18,
    this.padding = 10,
    this.shellTabIndex,
  });

  final String text;
  final GlobalKey? targetKey;
  final Rect Function(Rect raw)? rectTransform;
  final double radius;
  final double padding;

  /// 這一步需要切換到哪個底部分頁（0 首頁 / 1 商城 / 2 紀錄 / 3 設定）才看得到 target。
  ///
  /// 預設 null＝不切頁，留在目前分頁。用於跨頁導覽（例如最後一步切到設定頁、
  /// 高亮「家人聯絡人」入口）。實際切頁由 CoachMarkHost 負責，找不到 target 時
  /// overlay 仍會安全降級成置中說明卡，不會 crash。
  final int? shellTabIndex;
}

/// 新手導覽（Coach Mark / Spotlight）的狀態控制。
///
/// 只負責「現在在第幾步、文字列印完了沒、能不能進下一步」這類流程狀態；
/// 不碰持久化與畫面繪製（由 CoachMarkHost / overlay 處理），方便測試與維護。
class CoachMarkController extends ChangeNotifier {
  bool _active = false;
  int _index = 0;
  bool _isTyping = true;
  List<CoachMarkStep> _steps = const [];
  bool _replayRequested = false;

  bool get isActive => _active;
  int get currentIndex => _index;
  int get stepCount => _steps.length;
  bool get isTyping => _isTyping;
  bool get isLastStep => _steps.isNotEmpty && _index >= _steps.length - 1;
  bool get replayRequested => _replayRequested;

  CoachMarkStep? get currentStep =>
      (_active && _index >= 0 && _index < _steps.length)
          ? _steps[_index]
          : null;

  /// 開始導覽。空步驟不啟動。
  void start(List<CoachMarkStep> steps) {
    if (steps.isEmpty) return;
    _steps = List.unmodifiable(steps);
    _index = 0;
    _isTyping = true;
    _active = true;
    _replayRequested = false;
    notifyListeners();
  }

  /// 逐字列印完成 → 解鎖「下一個」。
  void markTypingDone() {
    if (!_isTyping) return;
    _isTyping = false;
    notifyListeners();
  }

  /// 進入下一步；最後一步則結束。列印未完成時不該被呼叫（UI 會鎖住按鈕）。
  void next() {
    if (!_active) return;
    if (isLastStep) {
      finish();
      return;
    }
    _index += 1;
    _isTyping = true;
    notifyListeners();
  }

  /// 結束導覽。
  void finish() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  /// 從設定頁要求「再看一次」；實際開始由 CoachMarkHost 在回到首頁、
  /// 目標 widget 就緒後觸發。
  void requestReplay() {
    _replayRequested = true;
    notifyListeners();
  }

  void consumeReplayRequest() {
    if (!_replayRequested) return;
    _replayRequested = false;
  }
}
