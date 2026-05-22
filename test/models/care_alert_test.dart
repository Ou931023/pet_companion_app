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
}
