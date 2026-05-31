import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/auth/firebase_init.dart';

void main() {
  group('FirebaseInitializer（CR-0006 Batch 4a safe init）', () {
    test('初始化成功 → isAvailable=true、ensureInitialized 回 true', () async {
      final initializer = FirebaseInitializer(initialize: () async {});

      final ok = await initializer.ensureInitialized();

      expect(ok, true);
      expect(initializer.isAvailable, true);
      expect(initializer.attempted, true);
    });

    test('初始化失敗 → 不丟例外、isAvailable=false（Demo 仍可用）', () async {
      final initializer = FirebaseInitializer(
        initialize: () async => throw Exception('缺少原生 Firebase 設定'),
      );

      // 重點：不可丟例外。
      final ok = await initializer.ensureInitialized();

      expect(ok, false);
      expect(initializer.isAvailable, false);
      expect(initializer.attempted, true);
    });

    test('只嘗試一次（memoized）：第二次不再呼叫 initialize', () async {
      var calls = 0;
      final initializer = FirebaseInitializer(
        initialize: () async => calls++,
      );

      await initializer.ensureInitialized();
      await initializer.ensureInitialized();

      expect(calls, 1);
    });
  });
}
