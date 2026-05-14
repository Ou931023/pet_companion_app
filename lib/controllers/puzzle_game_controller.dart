import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/puzzle_tile.dart';

class PuzzleGameController extends ChangeNotifier {
  final Random _random = Random();
  Timer? _timer;

  int _size = 3;
  List<int> _board = const [];
  int _moveCount = 0;
  int _elapsedSeconds = 0;
  bool _isComplete = false;
  bool _showNumberHint = false;

  int get size => _size;
  int get moveCount => _moveCount;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isComplete => _isComplete;
  bool get showNumberHint => _showNumberHint;
  List<PuzzleTile> get tiles {
    return List<PuzzleTile>.generate(_board.length, (index) {
      return PuzzleTile(currentIndex: index, correctIndex: _board[index]);
    });
  }

  void startGame(int size) {
    _size = size;
    final total = size * size;
    _board = List<int>.generate(total, (index) => index);
    _shuffleByLegalMoves(150 + size * 40);
    _moveCount = 0;
    _elapsedSeconds = 0;
    _isComplete = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
    notifyListeners();
  }

  void setNumberHint(bool value) {
    if (_showNumberHint == value) return;
    _showNumberHint = value;
    notifyListeners();
  }

  bool moveTile(int index) {
    if (_isComplete) return false;
    final blankIndex = _board.indexOf(_board.length - 1);
    if (!_isNeighbor(index, blankIndex)) return false;
    final temp = _board[index];
    _board[index] = _board[blankIndex];
    _board[blankIndex] = temp;
    _moveCount++;
    _isComplete = _isSolved();
    if (_isComplete) {
      _timer?.cancel();
    }
    notifyListeners();
    return true;
  }

  int rewardCoins() {
    if (_size == 3) {
      if (_random.nextDouble() <= 0.7) {
        return 5 + _random.nextInt(11);
      }
      return 0;
    }
    if (_random.nextDouble() <= 0.85) {
      return 10 + _random.nextInt(21);
    }
    return 0;
  }

  String get elapsedLabel {
    final mm = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  bool isBlankAt(int index) => _board[index] == _board.length - 1;

  int pieceAt(int index) => _board[index];

  void _shuffleByLegalMoves(int steps) {
    for (var i = 0; i < steps; i++) {
      final blankIndex = _board.indexOf(_board.length - 1);
      final neighbors = _neighborsOf(blankIndex);
      final picked = neighbors[_random.nextInt(neighbors.length)];
      final temp = _board[picked];
      _board[picked] = _board[blankIndex];
      _board[blankIndex] = temp;
    }
    if (_isSolved()) {
      _shuffleByLegalMoves(10);
    }
  }

  List<int> _neighborsOf(int index) {
    final row = index ~/ _size;
    final col = index % _size;
    final neighbors = <int>[];
    if (row > 0) neighbors.add(index - _size);
    if (row < _size - 1) neighbors.add(index + _size);
    if (col > 0) neighbors.add(index - 1);
    if (col < _size - 1) neighbors.add(index + 1);
    return neighbors;
  }

  bool _isNeighbor(int a, int b) => _neighborsOf(b).contains(a);

  bool _isSolved() {
    for (var i = 0; i < _board.length; i++) {
      if (_board[i] != i) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
