import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/puzzle_game_controller.dart';
import 'puzzle_tile_widget.dart';

/// 上方拼圖板：N×N 格。空格可接收拖曳；放對的格顯示 jigsaw 拼圖塊並鎖定。
///
/// 用 Stack 疊放，讓拼圖塊的凸起能鼓進相鄰格、看起來像真的接合。
/// 放對 → 吸附；放錯 → [onWrong] 回呼（提示「會回到下面」），塊留在下方。
class PuzzleBoard extends StatelessWidget {
  const PuzzleBoard({
    super.key,
    required this.controller,
    required this.imageFile,
    required this.onWrong,
  });

  final PuzzleGameController controller;
  final File imageFile;
  final VoidCallback onWrong;

  @override
  Widget build(BuildContext context) {
    final n = controller.size;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        final cell = side / n;
        final k = JigsawPiece.knobOf(cell);
        final emptySlots = <Widget>[];
        final placedPieces = <Widget>[];
        for (var slot = 0; slot < n * n; slot++) {
          final row = slot ~/ n;
          final col = slot % n;
          final placed = controller.pieceAt(slot);
          if (placed == null) {
            emptySlots.add(Positioned(
              left: col * cell,
              top: row * cell,
              width: cell,
              height: cell,
              child: _emptyTarget(slot),
            ));
          } else {
            placedPieces.add(Positioned(
              left: col * cell - k,
              top: row * cell - k,
              width: cell + 2 * k,
              height: cell + 2 * k,
              // 已放對：鎖定、不擋拖曳（讓凸起底下的空格仍可接收）。
              child: IgnorePointer(
                child: JigsawPiece(
                  imageFile: imageFile,
                  gridSize: n,
                  index: placed,
                  cell: cell,
                ),
              ),
            ));
          }
        }
        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            clipBehavior: Clip.none,
            children: [...emptySlots, ...placedPieces],
          ),
        );
      },
    );
  }

  Widget _emptyTarget(int slot) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final ok = controller.placePiece(details.data, slot);
        if (!ok) onWrong();
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: hovering
                ? Colors.amber.withValues(alpha: 0.35)
                : Colors.grey.shade200,
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
        );
      },
    );
  }
}
