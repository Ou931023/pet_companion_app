import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/puzzle_game_controller.dart';

void main() {
  // 固定亂數種子，讓打亂結果可重現、好斷言。
  PuzzleGameController make() => PuzzleGameController(random: Random(42));

  test('3x3 產生 9 塊、4x4 產生 16 塊', () {
    final c = make();
    addTearDown(c.dispose);

    c.startGame(3);
    expect(c.totalPieces, 9);
    expect(c.trayPieces.length, 9);
    expect(c.board.length, 9);
    expect(c.board.every((slot) => slot == null), isTrue);
    expect(c.difficultyLabel, '3x3');

    c.startGame(4);
    expect(c.totalPieces, 16);
    expect(c.trayPieces.length, 16);
    expect(c.difficultyLabel, '4x4');
  });

  test('打亂後不是排好的順序（不會一開始就完成）', () {
    final c = make();
    addTearDown(c.dispose);
    c.startGame(3);

    final sorted = List<int>.generate(9, (i) => i);
    expect(c.trayPieces, isNot(sorted));
    expect(c.isComplete, isFalse);
  });

  test('拖到正確位置會吸附；錯誤位置會彈回（留在下方）', () {
    final c = make();
    addTearDown(c.dispose);
    c.startGame(3);

    // 正確：piece 放到它自己的格 → 吸附、從下方移除。
    final piece = c.trayPieces.first;
    expect(c.placePiece(piece, piece), isTrue);
    expect(c.pieceAt(piece), piece);
    expect(c.trayPieces.contains(piece), isFalse);
    expect(c.correctDrops, 1);
    expect(c.moveAttempts, 1);

    // 錯誤：把另一塊放到不對的空格 → 不放置、留在下方、記一次錯誤。
    final other = c.trayPieces.firstWhere((p) => p != piece);
    final wrongSlot =
        c.trayPieces.firstWhere((s) => s != other && s != piece);
    expect(c.placePiece(other, wrongSlot), isFalse);
    expect(c.pieceAt(wrongSlot), isNull);
    expect(c.trayPieces.contains(other), isTrue);
    expect(c.wrongDrops, 1);
    expect(c.moveAttempts, 2);
  });

  test('全部放對 → 完成，且結果有 elapsedSeconds / moveAttempts / wrongDrops', () {
    final c = make();
    addTearDown(c.dispose);
    c.startGame(3);

    for (var i = 0; i < 9; i++) {
      c.placePiece(i, i);
    }

    expect(c.isComplete, isTrue);
    final r = c.result;
    expect(r, isNotNull);
    expect(r!.completed, isTrue);
    expect(r.difficulty, '3x3');
    expect(r.totalPieces, 9);
    expect(r.elapsedSeconds, greaterThanOrEqualTo(0));
    expect(r.moveAttempts, 9);
    expect(r.correctDrops, 9);
    expect(r.wrongDrops, 0);
  });

  test('4x4 全部放對也會完成（16 塊）', () {
    final c = make();
    addTearDown(c.dispose);
    c.startGame(4);
    for (var i = 0; i < 16; i++) {
      c.placePiece(i, i);
    }
    expect(c.isComplete, isTrue);
    expect(c.result!.totalPieces, 16);
  });

  test('已放對的格 / 完成後不可再放', () {
    final c = make();
    addTearDown(c.dispose);
    c.startGame(3);

    c.placePiece(0, 0);
    expect(c.placePiece(0, 0), isFalse); // 該格已放對
    for (var i = 1; i < 9; i++) {
      c.placePiece(i, i);
    }
    expect(c.isComplete, isTrue);
    expect(c.placePiece(0, 0), isFalse); // 完成後不可再操作
  });
}
