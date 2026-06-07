import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/care_alert_controller.dart';
import '../models/care_alert.dart';

/// 今日關心紀錄頁（長者端）。
///
/// 這是給長者自己看的畫面，語氣溫暖、像「有人在關心你」，
/// 不顯示風險等級、分析摘要或原始對話等後台資訊
/// （那些只給家人 / 照護人員在 caregiver 端查看）。
class CareAlertScreen extends StatefulWidget {
  const CareAlertScreen({super.key});

  @override
  State<CareAlertScreen> createState() => _CareAlertScreenState();
}

class _CareAlertScreenState extends State<CareAlertScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CareAlertController>().loadAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CareAlertController>();
    final alerts = controller.alerts;

    return Scaffold(
      appBar: AppBar(title: const Text('今日關心紀錄')),
      body: RefreshIndicator(
        onRefresh: controller.loadAlerts,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _IntroNote(),
            const SizedBox(height: 14),
            if (controller.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (alerts.isEmpty)
              const _EmptyState()
            else
              for (final alert in alerts)
                _CareNoteCard(
                  alert: alert,
                  onMarkRead: () =>
                      context.read<CareAlertController>().markAsRead(alert.id),
                ),
          ],
        ),
      ),
    );
  }
}

class _IntroNote extends StatelessWidget {
  const _IntroNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3D7DE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💛', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '這裡放著想多陪你一點的小紀錄。你並不孤單，有人一直在關心你。',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text('🌷', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text(
            '今天一切都好，沒有特別的事。\n記得想聊天的時候，我都在喔。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 長者端的關心卡片。只呈現溫暖訊息與（必要時）柔和的主題，
/// 不顯示風險等級、分析摘要、原始對話與來源。
class _CareNoteCard extends StatelessWidget {
  const _CareNoteCard({
    required this.alert,
    required this.onMarkRead,
  });

  final CareAlert alert;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final topic = _warmTopic(alert.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.isRead
              ? Colors.black12
              : const Color(0xFFE7A6B4),
          width: alert.isRead ? 1 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💗', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '有人關心你',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _formatDay(alert.createdAt),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '我把你放在心上，記得你並不孤單，有需要的時候我都在你身邊。',
            style: TextStyle(
              fontSize: 17,
              height: 1.5,
              color: Colors.black.withValues(alpha: 0.85),
            ),
          ),
          if (topic != null) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF4F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                topic,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB05a6c),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: alert.isRead
                ? const _SeenLabel()
                : FilledButton(
                    onPressed: onMarkRead,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text(
                      '我知道了，謝謝你',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDay(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// 把分類轉成柔和、不像監控的主題；無明確主題（other）時不顯示。
  String? _warmTopic(CareAlertCategory category) {
    return switch (category) {
      CareAlertCategory.sleep => '想陪你聊聊：好好睡',
      CareAlertCategory.appetite => '想陪你聊聊：吃得開心',
      CareAlertCategory.dizziness => '想多關心你的身體',
      CareAlertCategory.fall => '想確認你平平安安',
      CareAlertCategory.loneliness => '想多陪陪你',
      CareAlertCategory.depressed => '想陪你放鬆心情',
      CareAlertCategory.selfHarm => '想好好陪在你身邊',
      CareAlertCategory.needHelp => '想看看能幫上什麼忙',
      CareAlertCategory.other => null,
    };
  }
}

class _SeenLabel extends StatelessWidget {
  const _SeenLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.favorite, size: 18, color: Colors.pink.shade300),
        const SizedBox(width: 6),
        Text(
          '你已經看過了',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.5),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
