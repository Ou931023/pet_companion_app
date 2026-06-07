import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/services/auth/consent_api_service.dart';
import 'package:pet_companion_app/services/consent_service.dart';

/// 捕捉用的同意補送 stub：記錄每次呼叫的參數，並可設定回傳值。
/// 在 body 一開始就同步記錄參數，方便驗證 [ConsentService] 是否觸發補送。
class _CapturingConsentApi extends ConsentApiService {
  int callCount = 0;
  bool returnValue = true;

  String? consentType;
  String? consentVersion;
  String? action;
  String? source;
  String? firebaseUid;
  String? idToken;
  String? userId;
  String? elderId;
  String? platform;
  String? agreedAt;

  @override
  Future<bool> submitConsent({
    required String consentType,
    required String consentVersion,
    String action = 'granted',
    String? source,
    String? firebaseUid,
    String? idToken,
    String? userId,
    String? elderId,
    String? appVersion,
    String? platform,
    String? agreedAt,
  }) async {
    callCount++;
    this.consentType = consentType;
    this.consentVersion = consentVersion;
    this.action = action;
    this.source = source;
    this.firebaseUid = firebaseUid;
    this.idToken = idToken;
    this.userId = userId;
    this.elderId = elderId;
    this.platform = platform;
    this.agreedAt = agreedAt;
    return returnValue;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConsentApiService.submitConsent（HTTP，用 MockClient 不打網路）', () {
    test('2xx + success:true → 回 true，且 body 帶必填欄位、不含 ip / userAgent', () async {
      Map<String, dynamic>? sentBody;
      final api = ConsentApiService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'record': {
                'id': 'r1',
                'consentType': 'privacy_terms',
                'consentVersion': '1.0.0',
                'action': 'granted',
                'agreedAt': '2026-01-01T00:00:00.000Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final ok = await api.submitConsent(
        consentType: 'privacy_terms',
        consentVersion: '1.0.0',
        source: 'elder_app',
        agreedAt: '2026-01-01T00:00:00.000Z',
        platform: 'ios',
      );

      expect(ok, isTrue);
      expect(sentBody!['consentType'], 'privacy_terms');
      expect(sentBody!['consentVersion'], '1.0.0');
      expect(sentBody!['action'], 'granted');
      expect(sentBody!['source'], 'elder_app');
      // PII 紅線：前端絕不送 ip / userAgent。
      expect(sentBody!.containsKey('ip'), isFalse);
      expect(sentBody!.containsKey('userAgent'), isFalse);
      expect(sentBody!.containsKey('user_agent'), isFalse);
      // 無身份時不帶這些 key（後端契約允許）。
      expect(sentBody!.containsKey('firebaseUid'), isFalse);
      expect(sentBody!.containsKey('idToken'), isFalse);
    });

    test('帶身份時 body 會包含 firebaseUid / idToken / userId / elderId', () async {
      Map<String, dynamic>? sentBody;
      final api = ConsentApiService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );

      await api.submitConsent(
        consentType: 'privacy_terms',
        consentVersion: '1.0.0',
        firebaseUid: 'uid-1',
        idToken: 'tok-1',
        userId: 'user-1',
        elderId: 'elder-1',
      );

      expect(sentBody!['firebaseUid'], 'uid-1');
      expect(sentBody!['idToken'], 'tok-1');
      expect(sentBody!['userId'], 'user-1');
      expect(sentBody!['elderId'], 'elder-1');
    });

    test('非 2xx（500）→ 回 false，不丟例外', () async {
      final api = ConsentApiService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'success': false, 'error': 'consent_failed'}),
            500,
          );
        }),
      );

      final ok = await api.submitConsent(
        consentType: 'privacy_terms',
        consentVersion: '1.0.0',
      );
      expect(ok, isFalse);
    });

    test('連線錯誤（拋例外）→ 回 false，不丟例外', () async {
      final api = ConsentApiService(
        client: MockClient((request) async {
          throw const SocketLikeException();
        }),
      );

      final ok = await api.submitConsent(
        consentType: 'privacy_terms',
        consentVersion: '1.0.0',
      );
      expect(ok, isFalse);
    });
  });

  group('ConsentService.recordConsent → 寫本機成功後觸發 best-effort 補送', () {
    test('寫本機成功會觸發補送，且帶 privacy_terms / 版本 / granted / agreedAt', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _CapturingConsentApi();
      final service = ConsentService(consentApi: api);

      final record = await service.recordConsent('1.2.3');

      // 本機已寫入（單一判斷來源）。
      expect(record.version, '1.2.3');
      expect(await service.hasConsentedTo('1.2.3'), isTrue);
      // 觸發了補送，參數正確。
      expect(api.callCount, 1);
      expect(api.consentType, 'privacy_terms');
      expect(api.consentVersion, '1.2.3');
      expect(api.action, 'granted');
      expect(api.source, 'elder_app');
      expect(api.agreedAt, record.grantedAt);
    });

    test('無身份（未登入）時仍會補送，且四個身份欄位皆為 null', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _CapturingConsentApi();
      final service = ConsentService(consentApi: api);

      await service.recordConsent('1.2.3');

      expect(api.callCount, 1);
      expect(api.firebaseUid, isNull);
      expect(api.idToken, isNull);
      expect(api.userId, isNull);
      expect(api.elderId, isNull);
    });

    test('帶 identity 時會把身份傳給補送（如設定頁登入後重新同意）', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _CapturingConsentApi();
      final service = ConsentService(consentApi: api);

      await service.recordConsent(
        '1.2.3',
        identity: const ConsentIdentity(
          firebaseUid: 'uid-9',
          idToken: 'tok-9',
          userId: 'user-9',
          elderId: 'elder-9',
        ),
      );

      expect(api.firebaseUid, 'uid-9');
      expect(api.idToken, 'tok-9');
      expect(api.userId, 'user-9');
      expect(api.elderId, 'elder-9');
    });

    test('補送失敗（回 false）不影響本機已同意狀態、不 throw 到呼叫端', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _CapturingConsentApi()..returnValue = false;
      final service = ConsentService(consentApi: api);

      // 不應 throw。
      final record = await service.recordConsent('1.2.3');

      expect(record.version, '1.2.3');
      expect(await service.hasConsentedTo('1.2.3'), isTrue);
      expect(api.callCount, 1);
    });

    test('補送走真實 ConsentApiService 且後端 500 時，本機同意仍成立、不 throw',
        () async {
      SharedPreferences.setMockInitialValues({});
      // 真實 service 內部攔截所有例外並回 false，故背景 fire-and-forget 不會冒泡。
      final api = ConsentApiService(
        client: MockClient((request) async {
          return http.Response('{"success":false,"error":"consent_failed"}', 500);
        }),
      );
      final service = ConsentService(consentApi: api);

      final record = await service.recordConsent('1.2.3');
      // 讓背景補送有機會完成（驗證不會冒出未處理例外）。
      await Future<void>.delayed(Duration.zero);

      expect(record.version, '1.2.3');
      expect(await service.hasConsentedTo('1.2.3'), isTrue);
    });
  });
}

/// MockClient 用：模擬連線層丟出的例外（被 submitConsent 內部 catch 攔下）。
class SocketLikeException implements Exception {
  const SocketLikeException();
  @override
  String toString() => 'SocketLikeException';
}
