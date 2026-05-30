import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/care_alert_controller.dart';
import '../models/care_alert.dart';

/// 長照提醒紀錄頁。
///
/// 讓長照人員或家屬查看寵物從對話中注意到、可能需要關心的狀況。
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
      appBar: AppBar(title: const Text('長照提醒紀錄')),
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
                _CareAlertCard(
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: const Text(
        '這裡記錄寵物在對話中注意到、可能需要多關心的狀況，方便家人或照護人員了解長者近況。',
        style: TextStyle(fontSize: 16, height: 1.4),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Text(
        '目前沒有需要特別注意的提醒紀錄',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, height: 1.4),
      ),
    );
  }
}

class _CareAlertCard extends StatelessWidget {
  const _CareAlertCard({
    required this.alert,
    required this.onMarkRead,
  });

  final CareAlert alert;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(alert.riskLevel);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              alert.isRead ? Colors.black12 : color.withValues(alpha: 0.55),
          width: alert.isRead ? 1 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  alert.riskLevel.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert.category.label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!alert.isRead)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '未查看',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatTime(alert.createdAt),
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.55),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (alert.triggerSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              alert.triggerSummary,
              style: const TextStyle(fontSize: 17, height: 1.4),
            ),
          ],
          if (alert.transcriptSnippet.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '長者說：「${alert.transcriptSnippet}」',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: alert.isRead
                ? const _ReadLabel()
                : FilledButton.icon(
                    onPressed: onMarkRead,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('標記已查看'),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Color _riskColor(CareAlertRiskLevel level) {
    return switch (level) {
      // 權威四級
      CareAlertRiskLevel.urgent => Colors.red.shade700,
      CareAlertRiskLevel.high => Colors.deepOrange.shade700,
      CareAlertRiskLevel.medium => Colors.orange.shade700,
      CareAlertRiskLevel.low => Colors.indigo,
      // 舊代碼（legacy，向下相容顯示）
      CareAlertRiskLevel.attention => Colors.orange.shade800,
      CareAlertRiskLevel.normal => Colors.indigo,
    };
  }
}

class _ReadLabel extends StatelessWidget {
  const _ReadLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
        const SizedBox(width: 6),
        Text(
          '已查看',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.5),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
