import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/cart_item.dart';
import '../models/marketplace_order.dart';
import '../models/marketplace_product.dart';
import '../utils/app_log.dart';

/// 商城 API 呼叫失敗時丟出的應用層例外（訊息已是白話，可直接顯示給長者）。
class MarketplaceApiException implements Exception {
  const MarketplaceApiException(this.friendlyMessage);
  final String friendlyMessage;
  @override
  String toString() => 'MarketplaceApiException($friendlyMessage)';
}

/// 呼叫後端 `/api/marketplace/*` 端點的 HTTP 服務（CR-0032）。
///
/// 失敗一律轉成白話 [MarketplaceApiException]，不外洩工程訊息（長者友善）。
/// HTTP client 可注入，方便測試。
class MarketplaceService {
  MarketplaceService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  String get _base => AppConfig.backendBaseUrl;

  /// 後端錯誤碼 → 白話訊息（長者看得懂、不工程化）。
  static const Map<String, String> _orderErrorMessages = {
    'empty_cart': '購物車是空的，先挑幾樣需要的用品吧。',
    'invalid_item': '購物車的資料怪怪的，請重新加入商品再試一次。',
    'product_not_found': '有商品剛好下架了，請回商城重新挑選。',
    'product_unavailable': '有商品目前暫停販售，請回商城重新挑選。',
    'insufficient_stock': '有商品剛好庫存不夠了，請調整數量後再送出。',
    'multiple_centers': '一次只能訂購同一間照護中心的商品，請分開下單。',
  };

  /// 取得上架中的商品（長者端只看得到 active）。
  Future<List<MarketplaceProduct>> listProducts({String category = ''}) async {
    final query = <String, String>{};
    if (category.trim().isNotEmpty) query['category'] = category.trim();
    final uri = Uri.parse('$_base/api/marketplace/products').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    try {
      final response = await _client.get(uri).timeout(_timeout);
      final decoded = _decodeOk(response);
      final products = (decoded['products'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceProduct.fromJson)
          .toList();
      return products;
    } catch (error) {
      throw _friendly(error, '現在拿不到商品清單，待會再看看好嗎？');
    }
  }

  /// 建立訂單。金額由後端依當下商品重算，這裡只送 productId / quantity。
  Future<MarketplaceOrder> createOrder({
    required String userId,
    required String elderName,
    required String deliveryNote,
    required List<CartItem> items,
  }) async {
    final uri = Uri.parse('$_base/api/marketplace/orders');
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'elderName': elderName,
              'deliveryNote': deliveryNote,
              'items': items
                  .map((item) => {
                        'productId': item.product.id,
                        'quantity': item.quantity,
                      })
                  .toList(),
            }),
          )
          .timeout(_timeout);
      final decoded = _decodeOk(response, orderContext: true);
      return MarketplaceOrder.fromJson(decoded['order'] as Map<String, dynamic>);
    } catch (error) {
      throw _friendly(error, '現在沒辦法送出訂單，待會再試一次好嗎？');
    }
  }

  Map<String, dynamic> _decodeOk(
    http.Response response, {
    bool orderContext = false,
  }) {
    // 4xx 嘗試解析後端錯誤碼，轉成白話（尤其下單的庫存 / 跨中心錯誤）。
    if (response.statusCode >= 400 && response.statusCode < 500) {
      String? code;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) code = body['error']?.toString();
      } catch (_) {
        // 解析失敗就走預設訊息。
      }
      if (orderContext && code != null && _orderErrorMessages.containsKey(code)) {
        throw MarketplaceApiException(_orderErrorMessages[code]!);
      }
      throw const MarketplaceApiException('伺服器回應怪怪的，待會再試一次好嗎？');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const MarketplaceApiException('伺服器忙線中，待會再試一次好嗎？');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      throw const MarketplaceApiException('伺服器回應怪怪的，待會再試一次好嗎？');
    }
    return decoded;
  }

  MarketplaceApiException _friendly(Object error, String fallback) {
    if (error is MarketplaceApiException) return error;
    AppLog.error('[MARKETPLACE] API 失敗', error);
    return MarketplaceApiException(fallback);
  }
}
