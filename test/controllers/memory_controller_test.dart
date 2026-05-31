import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/services/memory_service.dart';

void main() {
  group('MemoryController.syncUserId（CR-0006 Batch 3d）', () {
    test('預設 userId 為 default_user', () {
      final controller = MemoryController(MemoryService());
      expect(controller.userId, 'default_user');
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
