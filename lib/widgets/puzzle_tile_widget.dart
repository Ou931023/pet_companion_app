import 'dart:io';

import 'package:flutter/material.dart';

class PuzzleTileWidget extends StatelessWidget {
  const PuzzleTileWidget({
    super.key,
    required this.imageFile,
    required this.gridSize,
    required this.correctIndex,
    required this.showNumberHint,
    required this.onTap,
  });

  final File imageFile;
  final int gridSize;
  final int correctIndex;
  final bool showNumberHint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = correctIndex ~/ gridSize;
    final col = correctIndex % gridSize;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        clipBehavior: Clip.hardEdge,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final tileW = constraints.maxWidth;
            final tileH = constraints.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: -col * tileW,
                  top: -row * tileH,
                  child: Image.file(
                    imageFile,
                    width: tileW * gridSize,
                    height: tileH * gridSize,
                    fit: BoxFit.cover,
                  ),
                ),
                if (showNumberHint)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${correctIndex + 1}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
