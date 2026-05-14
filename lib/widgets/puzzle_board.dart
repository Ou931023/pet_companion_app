import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/puzzle_game_controller.dart';
import 'puzzle_tile_widget.dart';

class PuzzleBoard extends StatelessWidget {
  const PuzzleBoard({
    super.key,
    required this.controller,
    required this.imageFile,
  });

  final PuzzleGameController controller;
  final File imageFile;

  @override
  Widget build(BuildContext context) {
    final total = controller.size * controller.size;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: total,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: controller.size,
      ),
      itemBuilder: (_, index) {
        if (controller.isBlankAt(index)) {
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }
        return PuzzleTileWidget(
          imageFile: imageFile,
          gridSize: controller.size,
          correctIndex: controller.pieceAt(index),
          showNumberHint: controller.showNumberHint,
          onTap: () => controller.moveTile(index),
        );
      },
    );
  }
}
