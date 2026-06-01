import 'dart:io';

import 'package:flutter/material.dart';

/// 顯示一張照片裡第 [index] 格（N×N 中的一塊）的小圖；會填滿父層給的大小。
///
/// 用「整張照片放大成 N 格大、再用 Positioned 平移露出該格」的方式裁出小塊，
/// 不會變形（[BoxFit.cover]），也不需要事先把照片切檔。
class PuzzlePieceImage extends StatelessWidget {
  const PuzzlePieceImage({
    super.key,
    required this.imageFile,
    required this.gridSize,
    required this.index,
  });

  final File imageFile;
  final int gridSize;
  final int index;

  @override
  Widget build(BuildContext context) {
    final row = index ~/ gridSize;
    final col = index % gridSize;
    return ClipRect(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: -col * w,
                top: -row * h,
                child: Image.file(
                  imageFile,
                  width: w * gridSize,
                  height: h * gridSize,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
