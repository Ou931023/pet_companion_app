import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/onboarding/coach_mark_controller.dart';

const _steps = [
  CoachMarkStep(text: '第一步'),
  CoachMarkStep(text: '第二步'),
  CoachMarkStep(text: '第三步'),
];

void main() {
  test('start：啟動後在第一步、列印中、非最後一步', () {
    final c = CoachMarkController();
    c.start(_steps);
    expect(c.isActive, isTrue);
    expect(c.currentIndex, 0);
    expect(c.currentStep?.text, '第一步');
    expect(c.isTyping, isTrue);
    expect(c.isLastStep, isFalse);
    expect(c.stepCount, 3);
  });

  test('空步驟不啟動', () {
    final c = CoachMarkController();
    c.start(const []);
    expect(c.isActive, isFalse);
  });

  test('列印完成前不解鎖；markTypingDone 後解鎖、next 前進', () {
    final c = CoachMarkController();
    c.start(_steps);
    expect(c.isTyping, isTrue);

    c.markTypingDone();
    expect(c.isTyping, isFalse);

    c.next();
    expect(c.currentIndex, 1);
    expect(c.currentStep?.text, '第二步');
    expect(c.isTyping, isTrue, reason: '進下一步要重新列印');
  });

  test('走到最後一步 → next 會結束導覽', () {
    final c = CoachMarkController();
    c.start(_steps);
    c.markTypingDone();
    c.next(); // 1
    c.markTypingDone();
    c.next(); // 2 (last)
    expect(c.isLastStep, isTrue);

    c.next(); // → finish
    expect(c.isActive, isFalse);
    expect(c.currentStep, isNull);
  });

  test('finish 直接結束', () {
    final c = CoachMarkController();
    c.start(_steps);
    c.finish();
    expect(c.isActive, isFalse);
  });

  test('requestReplay / consumeReplayRequest', () {
    final c = CoachMarkController();
    expect(c.replayRequested, isFalse);
    c.requestReplay();
    expect(c.replayRequested, isTrue);
    c.consumeReplayRequest();
    expect(c.replayRequested, isFalse);
  });

  test('notifyListeners：start / markTypingDone / next / finish 都會通知', () {
    final c = CoachMarkController();
    var notifications = 0;
    c.addListener(() => notifications++);
    c.start(_steps);
    c.markTypingDone();
    c.next();
    c.finish();
    expect(notifications, greaterThanOrEqualTo(4));
  });
}
