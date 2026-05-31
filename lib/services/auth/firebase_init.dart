import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase 的「安全初始化」包裝（CR-0006 Batch 4a）。
///
/// 設計重點：**初始化失敗絕對不可讓 App crash**。當缺少
/// `GoogleService-Info.plist` / `google-services.json`、或原生 Firebase 設定
/// 尚未完成時，`Firebase.initializeApp()` 會丟例外；這裡一律 try/catch 吞掉，
/// 只把可用性標記為 false，讓 App 照常啟動並可用 Demo 登入。
///
/// 本批不接 Email / Google 真登入，只提供「Firebase 是否可用」的查詢，
/// 供 Batch 4b / 4c 與 UI 判斷要不要顯示真登入入口。
class FirebaseInitializer {
  /// [initialize] 預設呼叫真正的 `Firebase.initializeApp()`；測試可注入假實作，
  /// 避免依賴原生外掛。
  FirebaseInitializer({Future<void> Function()? initialize})
      : _initialize = initialize ?? (() => Firebase.initializeApp());

  /// App 全域共用的單例（main 啟動時使用）。
  static final FirebaseInitializer instance = FirebaseInitializer();

  final Future<void> Function() _initialize;

  bool _available = false;
  bool _attempted = false;

  /// Firebase 是否初始化成功且可用。
  bool get isAvailable => _available;

  /// 是否已嘗試過初始化（不論成功失敗）。
  bool get attempted => _attempted;

  /// 嘗試初始化 Firebase。**永遠不丟例外**：成功回 true、失敗回 false。
  /// 重複呼叫只會嘗試一次（memoized），之後直接回上次結果。
  Future<bool> ensureInitialized() async {
    if (_attempted) return _available;
    _attempted = true;
    try {
      await _initialize();
      _available = true;
    } catch (error) {
      _available = false;
      debugPrint(
        '[FIREBASE] 初始化未完成，改用 Demo 登入即可（不影響啟動）：$error',
      );
    }
    return _available;
  }
}
