import 'dart:io';

import 'package:flutter/material.dart';

import 'jigsaw_clipper.dart';

/// 顯示一張照片裡第 [index] 格（N×N 中的一塊），裁成真實 jigsaw 形狀（有凸有凹）。
///
/// 元件實際大小是 [cell] + 兩側各 knob（讓凸起 tab 有空間鼓出來、且有照片內容填充）；
/// 用 [JigsawClipper] 把照片 mask 成拼圖塊形狀。不需要事先把照片切檔，也不變形。
class JigsawPiece extends StatelessWidget {
  const JigsawPiece({
    super.key,
    required this.imageFile,
    required this.gridSize,
    required this.index,
    required this.cell,
  });

  final File imageFile;
  final int gridSize;
  final int index;

  /// 拼圖塊本體（中央方格）的邊長；元件外框會比它大 2*knob。
  final double cell;

  /// 凸起 / 凹槽的深度，依本體大小比例。
  static double knobOf(double cell) => cell * 0.16;

  /// 含凸起的完整元件外框邊長。
  static double boxOf(double cell) => cell + 2 * knobOf(cell);

  @override
  Widget build(BuildContext context) {
    final k = knobOf(cell);
    final box = boxOf(cell);
    final row = index ~/ gridSize;
    final col = index % gridSize;
    return SizedBox(
      width: box,
      height: box,
      child: ClipPath(
        clipper: JigsawClipper(
          gridSize: gridSize,
          index: index,
          knob: k,
          core: cell,
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // 把整張照片放大到 N 格大，平移到讓本體中央露出第 index 格；
            // 兩側多出的 knob 區會自然顯示鄰格的照片，凸起才有內容、不會是空白。
            Positioned(
              left: k - col * cell,
              top: k - row * cell,
              width: cell * gridSize,
              height: cell * gridSize,
              child: Image.file(
                imageFile,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
