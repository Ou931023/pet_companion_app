import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_navigation_controller.dart';
import '../services/local_storage_service.dart';
import 'coach_mark_controller.dart';
import 'coach_mark_keys.dart';
import 'typewriter_text.dart';

/// 包住整個 App shell：負責「首次進首頁自動開始導覽」「再看一次」「完成後記錄」，
/// 跨頁步驟的分頁切換，並在導覽進行時把 spotlight overlay 疊在最上層（蓋住內容
/// 與底部導覽列）。
///
/// 導覽流程邏輯集中在這裡與 [CoachMarkController]，畫面端只需掛上目標 key。
class CoachMarkHost extends StatefulWidget {
  const CoachMarkHost({
    super.key,
    required this.child,
    required this.homeVisible,
  });

  final Widget child;

  /// 目前是否正顯示首頁（只有在首頁、目標 widget 就緒時才會開始導覽）。
  final bool homeVisible;

  @override
  State<CoachMarkHost> createState() => _CoachMarkHostState();
}

class _CoachMarkHostState extends State<CoachMarkHost> {
  late final CoachMarkController _controller;
  bool _wasActive = false;
  int _lastTabSwitchIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = context.read<CoachMarkController>();
    _controller.addListener(_onControllerChanged);
    _scheduleMaybeStart();
  }

  @override
  void didUpdateWidget(CoachMarkHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.homeVisible && !oldWidget.homeVisible) {
      _scheduleMaybeStart();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // 從「進行中」變成「結束」→ 記錄已看過，下次不再自動跳出，並切回首頁分頁
    // （避免最後一步跨頁到設定後把使用者留在設定頁）。
    if (_wasActive && !_controller.isActive) {
      context.read<LocalStorageService>().saveHomeCoachMarkDone(true);
      _lastTabSwitchIndex = -1;
      context.read<AppNavigationController>().selectShellIndex(0);
    }
    _wasActive = _controller.isActive;
    // 跨頁步驟：若目前這一步需要切到某個分頁才看得到 target，先切過去，
    // overlay 會在該頁繪製好後自動高亮（取不到時仍安全降級成置中卡）。
    if (_controller.isActive) {
      final tab = _controller.currentStep?.shellTabIndex;
      if (tab != null && tab != _lastTabSwitchIndex) {
        _lastTabSwitchIndex = tab;
        final nav = context.read<AppNavigationController>();
        if (nav.currentShellIndex != tab) {
          nav.selectShellIndex(tab);
        }
      }
    }
    if (_controller.replayRequested) {
      _scheduleMaybeStart();
    }
  }

  void _scheduleMaybeStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  Future<void> _maybeStart() async {
    if (!mounted || !widget.homeVisible) return;
    if (_controller.isActive) return;

    final keys = context.read<CoachMarkKeys>();
    // 首頁尚未繪製完成（拿不到寵物位置）→ 等下一輪再試。
    if (keys.petKey.currentContext == null) return;

    final replay = _controller.replayRequested;
    if (replay) {
      _controller.consumeReplayRequest();
    } else {
      final done =
          await context.read<LocalStorageService>().loadHomeCoachMarkDone();
      if (done) return;
    }
    if (!mounted || !widget.homeVisible || _controller.isActive) return;
    _lastTabSwitchIndex = -1;
    // 把底部 safe area（home indicator）高度傳進去，底部 tab 高亮框才能排除它、對齊 tab。
    final bottomInset = MediaQuery.of(context).padding.bottom;
    _controller.start(
      buildHomeCoachMarkSteps(keys, bottomNavInset: bottomInset),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CoachMarkController>();
    final keys = context.read<CoachMarkKeys>();
    return Stack(
      children: [
        widget.child,
        if (controller.isActive)
          CoachMarkOverlay(controller: controller, keys: keys),
      ],
    );
  }
}

/// Spotlight overlay（參考 Livly Island 風格）：整個畫面變暗、目前介紹的區塊用
/// 圓角框 + 柔光高亮、**上方**提示卡逐字列印說明，右下角有小三角。
///
/// 互動：點畫面任意處 →（列印未完成）先補完整文字 →（已完成）進下一步；
/// 點擊會被 overlay 吸收，不會穿透到底下功能。target 取不到時自動降級為置中卡片。
class CoachMarkOverlay extends StatefulWidget {
  const CoachMarkOverlay({
    super.key,
    required this.controller,
    required this.keys,
  });

  final CoachMarkController controller;
  final CoachMarkKeys keys;

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay> {
  /// 每次 ++ 代表「使用者要求立刻顯示完整文字」，由 TypewriterText 監聽。
  final ValueNotifier<int> _reveal = ValueNotifier<int>(0);

  // target 還沒繪製好（首幀 / 跨頁）時，逐幀重試取框，最多 _maxRetries 次，
  // 避免無限重建；超過仍取不到就維持置中卡片（安全降級）。
  int _retryIndex = -1;
  int _retries = 0;
  static const int _maxRetries = 18;

  CoachMarkController get _controller => widget.controller;

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _handleTap() {
    // 列印中：先補完整文字（不前進）；已完成：進下一步。
    if (_controller.isTyping) {
      _reveal.value++;
    } else {
      _controller.next();
    }
  }

  Rect? _rectForStep(CoachMarkStep step) {
    final key = step.targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final object = ctx.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return null;
    final topLeft = object.localToGlobal(Offset.zero);
    var rect = topLeft & object.size;
    final transform = step.rectTransform;
    if (transform != null) rect = transform(rect);
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    // 監聽 controller：列印完成 / 換步驟 / 結束時重建。
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final step = _controller.currentStep;
    if (step == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final screen = media.size;
    final rawRect = _rectForStep(step);
    final hole = rawRect?.inflate(step.padding);

    // target 還沒就緒 → 逐幀重試取框（跨頁切換、首幀未繪製時）。
    if (step.targetKey != null && hole == null) {
      if (_retryIndex != _controller.currentIndex) {
        _retryIndex = _controller.currentIndex;
        _retries = 0;
      }
      if (_retries < _maxRetries) {
        _retries++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }

    // 預設提示卡放上方；若 target 在畫面上半（會被上方卡片遮住）→ 改放下方。
    // 沒有 target（置中說明）→ 維持上方。
    final cardOnTop = hole == null || hole.center.dy > screen.height * 0.45;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        // 單一手勢層：吸收所有點擊（不穿透到底下功能），點任意處推進導覽。
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SpotlightPainter(hole: hole, radius: step.radius),
                ),
              ),
              _buildCard(context, media, cardOnTop),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, MediaQueryData media, bool onTop) {
    final card = _InstructionCard(controller: _controller, reveal: _reveal);
    final safeTop = media.padding.top + 16;
    final safeBottom = media.padding.bottom + 16;
    // 卡片最高不超過可用高度的一半，避免小螢幕 / 放大字體時溢出安全區。
    final maxCardHeight =
        ((media.size.height - safeTop - safeBottom) * 0.5).clamp(150.0, 420.0);
    return Positioned(
      left: 20,
      right: 20,
      top: onTop ? safeTop : null,
      bottom: onTop ? null : safeBottom,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxCardHeight),
        child: card,
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.controller, required this.reveal});

  final CoachMarkController controller;
  final ValueNotifier<int> reveal;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep!;
    final isLast = controller.isLastStep;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
      decoration: BoxDecoration(
        // 奶油色圓角卡片，溫柔、像正式產品（不是工程測試畫面）。
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${controller.currentIndex + 1} 步 / 共 ${controller.stepCount} 步',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB08642),
            ),
          ),
          const SizedBox(height: 10),
          // ValueKey(currentIndex) 讓換步驟時 TypewriterText 重建並重新逐字列印。
          // 包一層可捲動：文字較長 / 字體放大時不會把卡片撐到溢出（小螢幕安全）。
          Flexible(
            child: SingleChildScrollView(
              child: TypewriterText(
                key: ValueKey<int>(controller.currentIndex),
                text: step.text,
                onCompleted: controller.markTypingDone,
                revealSignal: reveal,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3D3226),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 右下角：非最後一步顯示小三角；最後一步顯示「開始使用」。
          // 實際前進由整個 overlay 的「點任意處」處理，這裡只是清楚的視覺指引。
          Align(
            alignment: Alignment.centerRight,
            child: isLast ? const _StartChip() : const _NextTriangle(),
          ),
        ],
      ),
    );
  }
}

/// 右下角小三角「下一步」指引。
class _NextTriangle extends StatelessWidget {
  const _NextTriangle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFF1A94E),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

/// 最後一步的「開始使用」小膠囊。
class _StartChip extends StatelessWidget {
  const _StartChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1A94E),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '開始使用',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole, required this.radius});

  final Rect? hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    // 暖色半透明遮罩（深褐而非純黑），柔和、不冰冷。
    final scrim = Paint()..color = const Color(0xFF2A1E12).withValues(alpha: 0.66);
    final localHole = hole;
    if (localHole == null) {
      canvas.drawRect(full, scrim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(localHole, Radius.circular(radius));
    final path = Path()
      ..addRect(full)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, scrim);
    // 外圈柔光（glow）：讓被介紹的區塊更明顯、更像產品。
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFFFD89B).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // 高亮框白色外框。
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.radius != radius;
}
