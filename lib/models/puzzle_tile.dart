class PuzzleTile {
  const PuzzleTile({
    required this.currentIndex,
    required this.correctIndex,
  });

  final int currentIndex;
  final int correctIndex;
  int get displayNumber => correctIndex + 1;
}
