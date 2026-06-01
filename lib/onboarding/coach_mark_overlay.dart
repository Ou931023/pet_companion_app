import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/local_storage_service.dart';
import 'coach_mark_controller.dart';
import 'coach_mark_keys.dart';
import 'typewriter_text.dart';

/// 包住整個 App shell：負責「首次進首頁自動開始導覽」「再看一次」「完成後記錄」，
/// 並在導覽進行時把 spotlight overlay 疊在最上層（蓋住內容與底部導覽列）。
///
/// 導覽流程邏輯集中在這裡與 [CoachMarkController]，HomeScreen 只需掛上目標 key。
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
    // 從「進行中」變成「結束」→ 記錄已看過，下次不再自動跳出。
    if (_wasActive && !_controller.isActive) {
      context.read<LocalStorageService>().saveHomeCoachMarkDone(true);
    }
    _wasActive = _controller.isActive;
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
    _controller.start(buildHomeCoachMarkSteps(keys));
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

/// Spotlight overlay：整個畫面變暗、目前介紹的區塊用圓角框高亮、上方逐字列印說明，
/// 列印完成後才能按「下一個」/「開始使用」。
class CoachMarkOverlay extends StatelessWidget {
  const CoachMarkOverlay({
    super.key,
    required this.controller,
    required this.keys,
  });

  final CoachMarkController controller;
  final CoachMarkKeys keys;

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
    // 自行監聽 controller，列印完成 / 換步驟 / 結束時都會重建，
    // 不依賴父層是否 watch（也讓單元測試可直接使用本 widget）。
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final step = controller.currentStep;
    if (step == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final screen = media.size;
    final rawRect = _rectForStep(step);
    final hole = rawRect?.inflate(step.padding);

    // 高亮框在畫面下半 → 說明卡放上方；否則放下方。沒有高亮框 → 置中。
    final cardOnTop = hole != null && hole.center.dy > screen.height / 2;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 半透明暗色遮罩 + 高亮挖空；吸收點擊，避免導覽中誤觸底下功能。
            Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: hole,
                  radius: step.radius,
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
              ),
            ),
            _buildCard(context, media, cardOnTop),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, MediaQueryData media, bool onTop) {
    final card = _InstructionCard(controller: controller);
    final safeTop = media.padding.top + 16;
    final safeBottom = media.padding.bottom + 16;
    // 卡片最高不超過可用高度的一半，避免小螢幕 / 放大字體時溢出底部安全區。
    final maxCardHeight =
        ((media.size.height - safeTop - safeBottom) * 0.5).clamp(160.0, 420.0);
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
  const _InstructionCard({required this.controller});

  final CoachMarkController controller;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep!;
    final isLast = controller.isLastStep;
    final canAdvance = !controller.isTyping;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
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
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3D3226),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: canAdvance ? controller.next : null,
              child: Text(
                isLast ? '開始使用' : '下一個',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
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
    // 高亮框外框，讓被介紹的區塊更明顯。
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
