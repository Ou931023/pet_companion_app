import 'package:flutter/material.dart';

import '../models/care_alert.dart';
import '../services/care_alert_storage_service.dart';

/// 管理長照提醒清單的 Controller。
///
/// 此批次只負責資料地基（讀取、新增、標記已查看、清空），
/// 尚未與對話偵測串接——不會由 AI 對話自動建立 CareAlert。
class CareAlertController extends ChangeNotifier {
  CareAlertController(this._storageService);

  final CareAlertStorageService _storageService;

  List<CareAlert> _alerts = const [];
  bool _isLoading = true;

  /// 依建立時間由新到舊排序的提醒清單。
  List<CareAlert> get alerts => List.unmodifiable(_alerts);

  bool get isLoading => _isLoading;

  /// 尚未被標記為已查看的提醒數量。
  int get unreadCount => _alerts.where((alert) => !alert.isRead).length;

  Future<void> loadAlerts() async {
    _isLoading = true;
    notifyListeners();
    final loaded = await _storageService.load();
    _alerts = _sortedByNewest(loaded);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addAlert(CareAlert alert) async {
    _alerts = _sortedByNewest([..._alerts, alert]);
    await _storageService.save(_alerts);
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    var changed = false;
    _alerts = _alerts.map((alert) {
      if (alert.id == id && !alert.isRead) {
        changed = true;
        return alert.copyWith(isRead: true);
      }
      return alert;
    }).toList();
    if (!changed) return;
    await _storageService.save(_alerts);
    notifyListeners();
  }

  Future<void> clearAllAlerts() async {
    if (_alerts.isEmpty) return;
    _alerts = const [];
    await _storageService.save(_alerts);
    notifyListeners();
  }

  List<CareAlert> _sortedByNewest(List<CareAlert> alerts) {
    return [...alerts]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
