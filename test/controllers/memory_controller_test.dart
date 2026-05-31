import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/services/memory_service.dart';

void main() {
  group('MemoryController.syncUserId（CR-0006 Batch 3d）', () {
    test('預設 userId 為 default_user', () {
      final controller = MemoryController(MemoryService());
      expect(controller.userId, 'default_user');
    });

    test('CR-0009：換帳號重置問候 slot，新帳號可再拿到屬於自己名字的問候', () async {
      // memoryService 連 localhost 失敗 → 走 _fallbackGreeting(petName)，
      // 因此問候字串會包含當下帳號的寵物名。
      final controller = MemoryController(MemoryService());

      final g1 =
          await controller.getGreeting(petName: '小白', isRealtimeActive: false);
      expect(g1, isNotNull);
      expect(g1, contains('小白'));

      // 同一時段第二次 → 被 slot 守門跳過。
      final g2 =
          await controller.getGreeting(petName: '小白', isRealtimeActive: false);
      expect(g2, isNull);

      // 換帳號 → 重置 slot，新帳號可再拿到問候，且用新名字。
      controller.syncUserId('elder-B');
      final g3 =
          await controller.getGreeting(petName: '來福', isRealtimeActive: false);
      expect(g3, isNotNull);
      expect(g3, contains('來福'));
      expect(g3, isNot(contains('小白')));
    });

    test('syncUserId 可切換到指定 elderId 並通知監聽者', () {
      final controller = MemoryController(MemoryService());
      var notified = 0;
      controller.addListener(() => notified++);

      controller.syncUserId('elder-789');

      expect(controller.userId, 'elder-789');
      expect(notified, 1);
    });

    test("syncUserId('') 回退 default_user", () {
      final controller = MemoryController(MemoryService());
      controller.syncUserId('elder-789');
      expect(controller.userId, 'elder-789');

      controller.syncUserId('');

      expect(controller.userId, 'default_user');
    });

    test('同值 syncUserId 不重複通知（避免多餘 rebuild）', () {
      final controller = MemoryController(MemoryService());
      var notified = 0;
      controller.addListener(() => notified++);

      // default → default 是 no-op。
      controller.syncUserId('default_user');
      expect(notified, 0);

      controller.syncUserId('elder-1');
      controller.syncUserId('elder-1');
      expect(notified, 1);
    });
  });
}
