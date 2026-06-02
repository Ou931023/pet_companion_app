import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/daily_care_task.dart';

void main() {
  test('DailyCareTask.fromJson 解析基本欄位', () {
    final task = DailyCareTask.fromJson({
      'id': 't1',
      'elderId': 'elder-1',
      'title': '早上吃藥',
      'type': 'medication',
      'scheduledTime': '08:00',
      'status': 'pending',
      'proofRequired': true,
    });
    expect(task.id, 't1');
    expect(task.type, DailyCareTaskType.medication);
    expect(task.status, DailyCareTaskStatus.pending);
    expect(task.proofRequired, true);
    expect(task.typeLabel, '吃藥');
    expect(task.statusLabel, '待完成');
  });

  test('type walk → exercise；未知 → medication', () {
    expect(dailyCareTaskTypeFromString('walk'), DailyCareTaskType.exercise);
    expect(dailyCareTaskTypeFromString('???'), DailyCareTaskType.medication);
  });

  test('status needs_review → needsReview，文案為等待照護人員查看', () {
    final status = dailyCareTaskStatusFromString('needs_review');
    expect(status, DailyCareTaskStatus.needsReview);
    expect(dailyCareTaskStatusLabel(status), '等待照護人員查看');
  });

  test('狀態文案涵蓋六種', () {
    expect(dailyCareTaskStatusLabel(DailyCareTaskStatus.submitted), '已送出');
    expect(dailyCareTaskStatusLabel(DailyCareTaskStatus.completed), '已完成');
    expect(dailyCareTaskStatusLabel(DailyCareTaskStatus.rejected), '未通過');
    expect(dailyCareTaskStatusLabel(DailyCareTaskStatus.missed), '已逾時');
  });

  test('DailyCareTaskVerification.fromJson + 信心百分比', () {
    final v = DailyCareTaskVerification.fromJson({
      'verificationStatus': 'passed',
      'confidence': 0.83,
      'reason': '看起來有藥盒',
      'detectedObjects': ['藥盒', '藥丸'],
      'reviewRequired': false,
    });
    expect(v.status, DailyCareVerificationStatus.passed);
    expect(v.confidence, 0.83);
    expect(v.detectedObjects, ['藥盒', '藥丸']);
    expect(v.reviewRequired, false);
    expect(v.confidencePercentLabel, '83%');
  });

  test('帶 latestSubmission 的任務（管理者端形狀）', () {
    final task = DailyCareTask.fromJson({
      'id': 't2',
      'elderId': 'e',
      'title': '喝水',
      'type': 'hydration',
      'status': 'needs_review',
      'latestSubmission': {
        'id': 's1',
        'taskId': 't2',
        'status': 'needs_review',
        'submittedAt': '2026-06-02T08:00:00Z',
        'verification': {
          'verificationStatus': 'uncertain',
          'confidence': 0.2,
          'reviewRequired': true,
        },
      },
    });
    expect(task.latestSubmission, isNotNull);
    expect(
      task.latestSubmission!.verification!.status,
      DailyCareVerificationStatus.uncertain,
    );
  });
}
