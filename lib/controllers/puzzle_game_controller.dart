import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/puzzle_tile.dart';

/// 傳統照片拼圖的遊戲狀態（拖曳放置，非華容道滑塊）。
///
/// - 把一張照片切成 N×N 塊（3×3＝9 塊、4×4＝16 塊）。
/// - 每塊 piece 的編號就是它「該放的格子」（slot）。
/// - 下方拼圖區（[trayPieces]）放尚未放置的塊，順序打亂。
/// - 上方拼圖板（[board]）每格放對的塊會吸附並鎖定。
/// - 放對 → [placePiece] 回 true 並吸附；放錯 → 回 false（塊留在下方＝彈回）。
class PuzzleGameController extends ChangeNotifier {
  PuzzleGameController({Random? random}) : _random = random ?? Random();

  final Random _random;
  Timer? _timer;

  int _size = 3;
  final List<int> _tray = [];
  List<int?> _board = const [];
  int _moveAttempts = 0;
  int _correctDrops = 0;
  int _wrongDrops = 0;
  bool _started = false;
  DateTime? _startedAt;
  DateTime? _completedAt;
  int _elapsedSeconds = 0;

  int get size => _size;
  int get totalPieces => _size * _size;

  /// 下方尚未放置的拼圖塊（已打亂）。
  List<int> get trayPieces => List.unmodifiable(_tray);

  /// 上方拼圖板：board[slot] = 放在該格的塊編號，未放為 null。
  List<int?> get board => List.unmodifiable(_board);

  int get moveAttempts => _moveAttempts;
  int get correctDrops => _correctDrops;
  int get wrongDrops => _wrongDrops;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isStarted => _started;
  bool get isComplete => _started && _tray.isEmpty;
  String get difficultyLabel => '${_size}x$_size';

  String get elapsedLabel {
    final mm = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  int? pieceAt(int slot) => (slot >= 0 && slot < _board.length) ? _board[slot] : null;
  bool isPlaced(int slot) => pieceAt(slot) != null;

  /// 開始 / 重新洗牌一局（[size] 為 3 或 4）。
  void startGame(int size) {
    _size = (size == 4) ? 4 : 3;
    final total = _size * _size;
    _board = List<int?>.filled(total, null);
    _tray
      ..clear()
      ..addAll(List<int>.generate(total, (i) => i));
    _shuffleTray();
    _moveAttempts = 0;
    _correctDrops = 0;
    _wrongDrops = 0;
    _started = true;
    _startedAt = DateTime.now();
    _completedAt = null;
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  void _shuffleTray() {
    _tray.shuffle(_random);
    // 不要讓打亂後剛好是排好的順序（避免一開始就接近完成）。
    final sorted = List<int>.generate(_tray.length, (i) => i);
    if (_tray.length > 1 && listEquals(_tray, sorted)) {
      final first = _tray[0];
      _tray[0] = _tray[1];
      _tray[1] = first;
    }
  }

  /// 把 [piece] 放到 [slot]。
  ///
  /// - 正確（piece == slot）→ 吸附：從下方移除、放上該格、鎖定，回 true。
  /// - 錯誤 → 不放置，塊留在下方（UI 會彈回），記一次錯誤，回 false。
  /// 全部放對後自動結算（[isComplete]）。
  bool placePiece(int piece, int slot) {
    if (!_started || isComplete) return false;
    if (slot < 0 || slot >= _board.length) return false;
    if (_board[slot] != null) return false; // 該格已放對、不可再覆蓋
    if (!_tray.contains(piece)) return false;

    _moveAttempts++;
    if (piece == slot) {
      _board[slot] = piece;
      _tray.remove(piece);
      _correctDrops++;
      if (isComplete) _finish();
      notifyListeners();
      return true;
    }
    _wrongDrops++;
    notifyListeners();
    return false;
  }

  void _finish() {
    _completedAt = DateTime.now();
    if (_startedAt != null) {
      final secs = _completedAt!.difference(_startedAt!).inSeconds;
      _elapsedSeconds = secs < 0 ? 0 : secs;
    }
    _timer?.cancel();
    _timer = null;
  }

  /// 完成後的遊戲結果（退化指標用）；未完成回 null。
  PuzzleResult? get result {
    if (!isComplete) return null;
    return PuzzleResult(
      difficulty: difficultyLabel,
      totalPieces: totalPieces,
      elapsedSeconds: _elapsedSeconds,
      moveAttempts: _moveAttempts,
      correctDrops: _correctDrops,
      wrongDrops: _wrongDrops,
      completed: true,
      completedAt: _completedAt ?? DateTime.now(),
    );
  }

  /// 完成拼圖的金幣獎勵（沿用既有寵物 / 金幣經濟；難度越高給越多）。
  int rewardCoins() {
    if (!isComplete) return 0;
    return _size == 4 ? 8 : 5;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
