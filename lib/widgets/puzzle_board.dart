import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/puzzle_game_controller.dart';
import 'puzzle_tile_widget.dart';

/// 上方拼圖板：N×N 格。空格可接收拖曳；放對的格顯示照片小塊並鎖定。
///
/// 放對 → 吸附；放錯 → [onWrong] 回呼（讓畫面提示「會回到下面」），塊留在下方。
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
        return SizedBox(
          width: side,
          height: side,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < n; row++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var col = 0; col < n; col++)
                      SizedBox(
                        width: cell,
                        height: cell,
                        child: _slot(context, row * n + col),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _slot(BuildContext context, int slot) {
    final placed = controller.pieceAt(slot);
    if (placed != null) {
      // 已放對：顯示照片小塊、鎖定（不可再拖）。
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: PuzzlePieceImage(
          imageFile: imageFile,
          gridSize: controller.size,
          index: placed,
        ),
      );
    }
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
