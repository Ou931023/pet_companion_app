import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/auth_session.dart';

void main() {
  group('AuthSession.fromJson', () {
    test('解析後端 response 的所有欄位', () {
      final session = AuthSession.fromJson({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'role': 'elder',
        'bindingStatus': 'bound',
        'bindingDeadline': '2026-07-30T00:00:00.000Z',
        'isNewUser': true,
        'authMode': 'firebase',
      });

      expect(session.userId, 'user-123');
      expect(session.elderId, 'elder-456');
      expect(session.role, 'elder');
      expect(session.bindingStatus, 'bound');
      expect(session.bindingDeadline, '2026-07-30T00:00:00.000Z');
      expect(session.isNewUser, true);
      expect(session.authMode, 'firebase');
    });

    test('缺欄時 fallback 為 default_user / pending / mock', () {
      final session = AuthSession.fromJson(const {});

      expect(session.userId, 'default_user');
      expect(session.elderId, 'default_user');
      expect(session.bindingStatus, 'pending');
      expect(session.authMode, 'mock');
      expect(session.isNewUser, false);
      expect(session.role, isNull);
      expect(session.bindingDeadline, isNull);
    });
  });

  test('toPrefsMap / fromPrefs round-trip 保留欄位', () {
    final original = AuthSession.fromJson({
      'userId': 'u1',
      'elderId': 'e1',
      'role': 'elder',
      'bindingStatus': 'pending',
      'bindingDeadline': '2026-07-30T00:00:00.000Z',
      'isNewUser': false,
      'authMode': 'mock',
    });

    final restored = AuthSession.fromPrefs(original.toPrefsMap());

    expect(restored.userId, original.userId);
    expect(restored.elderId, original.elderId);
    expect(restored.role, original.role);
    expect(restored.bindingStatus, original.bindingStatus);
    expect(restored.bindingDeadline, original.bindingDeadline);
    expect(restored.isNewUser, original.isNewUser);
    expect(restored.authMode, original.authMode);
  });

  test('mockFallback 為 default_user / mock / pending', () {
    final session = AuthSession.mockFallback();

    expect(session.userId, 'default_user');
    expect(session.elderId, 'default_user');
    expect(session.authMode, 'mock');
    expect(session.bindingStatus, 'pending');
    expect(session.isNewUser, false);
  });
}
