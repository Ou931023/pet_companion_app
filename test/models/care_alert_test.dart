import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/care_alert.dart';

void main() {
  test('CareAlert toJson / fromJson round-trips all fields', () {
    final alert = CareAlert(
      id: 'care_alert_1',
      createdAt: DateTime.parse('2026-05-22T09:30:00.000'),
      riskLevel: CareAlertRiskLevel.urgent,
      category: CareAlertCategory.fall,
      triggerSummary: '長者提到跌倒',
      transcriptSnippet: '我剛剛在浴室跌倒了',
      source: 'companion_analysis',
      isRead: false,
    );

    final restored = CareAlert.fromJson(alert.toJson());

    expect(restored.id, 'care_alert_1');
    expect(restored.createdAt, DateTime.parse('2026-05-22T09:30:00.000'));
    expect(restored.riskLevel, CareAlertRiskLevel.urgent);
    expect(restored.category, CareAlertCategory.fall);
    expect(restored.triggerSummary, '長者提到跌倒');
    expect(restored.transcriptSnippet, '我剛剛在浴室跌倒了');
    expect(restored.source, 'companion_analysis');
    expect(restored.isRead, isFalse);
  });

  test('CareAlert.fromJson falls back safely on unknown enum values', () {
    final alert = CareAlert.fromJson({
      'id': 'x',
      'createdAt': '2026-05-22T09:30:00.000',
      'riskLevel': 'something_unknown',
      'category': 'something_unknown',
      'source': 'test',
      'isRead': true,
    });

    expect(alert.riskLevel, CareAlertRiskLevel.normal);
    expect(alert.category, CareAlertCategory.other);
    expect(alert.triggerSummary, '');
    expect(alert.transcriptSnippet, '');
    expect(alert.isRead, isTrue);
  });

  test('copyWith only changes provided fields', () {
    final alert = CareAlert(
      id: 'a',
      createdAt: DateTime(2026, 5, 22),
      riskLevel: CareAlertRiskLevel.attention,
      category: CareAlertCategory.loneliness,
      triggerSummary: 's',
      transcriptSnippet: 't',
      source: 'test',
      isRead: false,
    );

    final read = alert.copyWith(isRead: true);

    expect(read.isRead, isTrue);
    expect(read.id, 'a');
    expect(read.category, CareAlertCategory.loneliness);
    expect(read.riskLevel, CareAlertRiskLevel.attention);
  });

  group('CareAlertRiskLevel CR-0002 backward compatibility', () {
    test('fromJson parses authoritative four levels', () {
      expect(CareAlertRiskLevel.fromJson('low'), CareAlertRiskLevel.low);
      expect(CareAlertRiskLevel.fromJson('medium'), CareAlertRiskLevel.medium);
      expect(CareAlertRiskLevel.fromJson('high'), CareAlertRiskLevel.high);
      expect(CareAlertRiskLevel.fromJson('urgent'), CareAlertRiskLevel.urgent);
    });

    test('fromJson still parses legacy codes', () {
      expect(CareAlertRiskLevel.fromJson('normal'), CareAlertRiskLevel.normal);
      expect(
        CareAlertRiskLevel.fromJson('attention'),
        CareAlertRiskLevel.attention,
      );
      expect(CareAlertRiskLevel.fromJson('urgent'), CareAlertRiskLevel.urgent);
    });

    test('toJson preserves the original code (no premature data-layer switch)',
        () {
      // 舊值必須原樣 round-trip，不可被改寫成 low/medium，否則等於提前切換資料層。
      for (final level in CareAlertRiskLevel.values) {
        expect(CareAlertRiskLevel.fromJson(level.toJson()), level);
      }
      expect(CareAlertRiskLevel.normal.toJson(), 'normal');
      expect(CareAlertRiskLevel.attention.toJson(), 'attention');
      expect(CareAlertRiskLevel.high.toJson(), 'high');
    });

    test('canonical maps legacy codes to authoritative four levels', () {
      expect(CareAlertRiskLevel.normal.canonical, CareAlertRiskLevel.low);
      expect(CareAlertRiskLevel.attention.canonical, CareAlertRiskLevel.medium);
      expect(CareAlertRiskLevel.urgent.canonical, CareAlertRiskLevel.urgent);
      expect(CareAlertRiskLevel.low.canonical, CareAlertRiskLevel.low);
      expect(CareAlertRiskLevel.medium.canonical, CareAlertRiskLevel.medium);
      expect(CareAlertRiskLevel.high.canonical, CareAlertRiskLevel.high);
    });

    test('every level has a non-empty Chinese label', () {
      for (final level in CareAlertRiskLevel.values) {
        expect(level.label, isNotEmpty);
      }
      expect(CareAlertRiskLevel.high.label, '需通知');
      expect(CareAlertRiskLevel.medium.label, '持續觀察');
      expect(CareAlertRiskLevel.low.label, '一般');
      // legacy 顯示文字維持不變
      expect(CareAlertRiskLevel.attention.label, '需注意');
    });

    test('unknown value still falls back to normal (canonically low)', () {
      final level = CareAlertRiskLevel.fromJson('totally_unknown');
      expect(level, CareAlertRiskLevel.normal);
      expect(level.canonical, CareAlertRiskLevel.low);
    });

    test('CareAlert round-trips a new-scheme high alert', () {
      final alert = CareAlert(
        id: 'h1',
        createdAt: DateTime.parse('2026-05-29T10:00:00.000'),
        riskLevel: CareAlertRiskLevel.high,
        category: CareAlertCategory.depressed,
        triggerSummary: '長期情緒低落',
        transcriptSnippet: '我最近都睡不好',
        source: 'companion_analysis',
        isRead: false,
      );

      final restored = CareAlert.fromJson(alert.toJson());
      expect(restored.riskLevel, CareAlertRiskLevel.high);
    });
  });
}
