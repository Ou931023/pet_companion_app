import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/search_service.dart';

void main() {
  group('SearchService.search userId（CR-0006 Batch 3d）', () {
    test('預設送出 userId == default_user', () async {
      Map<String, dynamic>? sentBody;
      final service = SearchService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'results': [], 'summary': ''}),
            200,
          );
        }),
      );

      await service.search('睡不好怎麼辦');

      expect(sentBody, isNotNull);
      expect(sentBody!['userId'], 'default_user');
    });

    test('傳入 elderId 時 body 使用該 elderId', () async {
      Map<String, dynamic>? sentBody;
      final service = SearchService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'results': [], 'summary': ''}),
            200,
          );
        }),
      );

      await service.search('睡不好怎麼辦', userId: 'elder-789');

      expect(sentBody!['userId'], 'elder-789');
    });

    test("傳入空字串 userId 仍回退 default_user", () async {
      Map<String, dynamic>? sentBody;
      final service = SearchService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'results': [], 'summary': ''}),
            200,
          );
        }),
      );

      await service.search('睡不好怎麼辦', userId: '');

      expect(sentBody!['userId'], 'default_user');
    });

    test('後端 4xx → 仍回 fallback，不丟例外（Demo 不被擋）', () async {
      final service = SearchService(
        client: MockClient((request) async {
          return http.Response('error', 500);
        }),
      );

      final response = await service.search('睡不好怎麼辦', userId: 'elder-789');

      expect(response, isNotNull);
    });
  });
}
