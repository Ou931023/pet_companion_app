import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/auth/firebase_auth_service.dart';
import 'package:pet_companion_app/services/auth/firebase_init.dart';

void main() {
  group('FirebaseAuthService（CR-0006 Batch 4a 雛形）', () {
    test('isAvailable 反映 initializer 狀態', () async {
      final available = FirebaseInitializer(initialize: () async {});
      await available.ensureInitialized();
      expect(FirebaseAuthService(initializer: available).isAvailable, true);

      final unavailable = FirebaseInitializer(
        initialize: () async => throw Exception('no native config'),
      );
      await unavailable.ensureInitialized();
      expect(FirebaseAuthService(initializer: unavailable).isAvailable, false);
    });

    test('Firebase 不可用時 Email 方法丟 EmailAuthException(unavailable)，不碰原生',
        () async {
      // initializer 從未 ensureInitialized → isAvailable=false。
      final service = FirebaseAuthService(
        initializer: FirebaseInitializer(initialize: () async {}),
      );

      await expectLater(
        service.registerWithEmail(email: 'a@b.c', password: 'secret1'),
        throwsA(
          isA<EmailAuthException>()
              .having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      await expectLater(
        service.signInWithEmail(email: 'a@b.c', password: 'secret1'),
        throwsA(
          isA<EmailAuthException>()
              .having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });

    test(
        'Firebase 不可用時 signInWithGoogle 丟 GoogleAuthException(unavailable)，不碰原生',
        () async {
      final service = FirebaseAuthService(
        initializer: FirebaseInitializer(initialize: () async {}),
      );
      await expectLater(
        service.signInWithGoogle(),
        throwsA(
          isA<GoogleAuthException>()
              .having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });

    test('Firebase 不可用時 Apple 與密碼重設都安全失敗、不碰原生', () async {
      final service = FirebaseAuthService(
        initializer: FirebaseInitializer(initialize: () async {}),
      );

      await expectLater(
        service.signInWithApple(),
        throwsA(
          isA<AppleAuthException>()
              .having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      await expectLater(
        service.sendPasswordResetEmail('grandma@example.com'),
        throwsA(
          isA<EmailAuthException>()
              .having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });

    test('GoogleAuthException.isCanceled 只在 canceled 時為 true', () {
      expect(const GoogleAuthException('canceled').isCanceled, true);
      expect(const GoogleAuthException('interrupted').isCanceled, false);
      expect(const GoogleAuthException('unknown').isCanceled, false);
    });

    test('AppleAuthException.isCanceled 只在 canceled 時為 true', () {
      expect(const AppleAuthException('canceled').isCanceled, true);
      expect(const AppleAuthException('config').isCanceled, false);
      expect(const AppleAuthException('unknown').isCanceled, false);
    });

    test('Firebase 不可用時 signOut 為安全 no-op（不丟例外）', () async {
      final unavailable = FirebaseInitializer(
        initialize: () async => throw Exception('no native config'),
      );
      await unavailable.ensureInitialized();
      final service = FirebaseAuthService(initializer: unavailable);

      await expectLater(service.signOut(), completes);
    });
  });
}
