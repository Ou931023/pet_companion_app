import 'package:flutter/foundation.dart';

import '../models/marketplace_product.dart';
import '../services/marketplace_service.dart';

/// 長照商城商品狀態管理（CR-0032）。
///
/// 負責向後端載入上架中的商品、分類篩選與白話錯誤訊息。
/// 不碰購物車（由 [CartController] 負責），也不碰下單（由畫面呼叫 service）。
class MarketplaceController extends ChangeNotifier {
  MarketplaceController(this._service);

  final MarketplaceService _service;

  List<MarketplaceProduct> _products = const [];
  bool _isLoading = false;
  String? _errorMessage;
  String _category = '';
  bool _disposed = false;

  List<MarketplaceProduct> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;

  /// 白話錯誤訊息（無錯誤為 null）。畫面只顯示這個，不顯示工程細節。
  String? get errorMessage => _errorMessage;

  /// 目前選取的分類（空字串＝全部）。
  String get category => _category;

  /// 商城出現過的分類清單（依商品動態產生），給篩選列用。
  List<String> get availableCategories {
    final seen = <String>{};
    for (final product in _products) {
      if (product.category.trim().isNotEmpty) seen.add(product.category);
    }
    return seen.toList();
  }

  Future<void> loadProducts({String? category}) async {
    if (category != null) _category = category;
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();
    try {
      _products = await _service.listProducts(category: _category);
    } on MarketplaceApiException catch (error) {
      _errorMessage = error.friendlyMessage;
    } catch (_) {
      _errorMessage = '現在拿不到商品清單，待會再看看好嗎？';
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// 切換分類並重新載入。
  Future<void> selectCategory(String category) async {
    if (category == _category) return;
    await loadProducts(category: category);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
