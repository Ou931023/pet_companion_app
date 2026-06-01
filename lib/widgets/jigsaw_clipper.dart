import 'package:flutter/widgets.dart';

/// 把一塊拼圖裁成真實 jigsaw 形狀（有凸 / 有凹）的 clipper。
///
/// 在一個 [core] + 兩側各 [knob] 的方框（邊長 `core + 2*knob`）裡作畫：中央 [core]
/// 是拼圖塊本體；每條「內部邊」會凸出一個 tab（往外鼓到方框邊緣）或凹進一個 blank；
/// 「外框邊」（拼圖最外圈）保持平直。相鄰兩塊共用的邊互補（一凸一凹），拼起來會接合。
class JigsawClipper extends CustomClipper<Path> {
  const JigsawClipper({
    required this.gridSize,
    required this.index,
    required this.knob,
    required this.core,
  });

  final int gridSize;
  final int index;
  final double knob;
  final double core;

  int get _row => index ~/ gridSize;
  int get _col => index % gridSize;

  // 內部邊的凸凹樣式（固定規則 → 相鄰可互補）。1 = 凸(tab)、-1 = 凹(blank)。
  int _vEdge(int row, int col) => ((row * 2 + col) % 2 == 0) ? 1 : -1; // 上下邊
  int _hEdge(int row, int col) => ((row + col * 2) % 2 == 0) ? 1 : -1; // 左右邊

  int get _topType => _row == 0 ? 0 : -_vEdge(_row - 1, _col);
  int get _bottomType => _row == gridSize - 1 ? 0 : _vEdge(_row, _col);
  int get _leftType => _col == 0 ? 0 : -_hEdge(_row, _col - 1);
  int get _rightType => _col == gridSize - 1 ? 0 : _hEdge(_row, _col);

  @override
  Path getClip(Size size) {
    final k = knob;
    // 本體四角（方框內縮 knob）。
    final tl = Offset(k, k);
    final tr = Offset(k + core, k);
    final br = Offset(k + core, k + core);
    final bl = Offset(k, k + core);

    final path = Path()..moveTo(tl.dx, tl.dy);
    _edge(path, tl, tr, _topType); // 上：左→右，外側為上
    _edge(path, tr, br, _rightType); // 右：上→下，外側為右
    _edge(path, br, bl, _bottomType); // 下：右→左，外側為下
    _edge(path, bl, tl, _leftType); // 左：下→上，外側為左
    path.close();
    return path;
  }

  void _edge(Path path, Offset a, Offset b, int type) {
    if (type == 0) {
      path.lineTo(b.dx, b.dy);
      return;
    }
    final v = b - a;
    final len = v.distance;
    final dir = v / len;
    // 順時針繞行時的「向外」法線。
    final out = Offset(dir.dy, -dir.dx);
    final mid = a + v * 0.5;
    final half = len * 0.18;
    final p1 = mid - dir * half;
    final p2 = mid + dir * half;
    final reach = out * (type * knob);
    final c1 = p1 + reach * 1.25;
    final c2 = p2 + reach * 1.25;
    path.lineTo(p1.dx, p1.dy);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    path.lineTo(b.dx, b.dy);
  }

  @override
  bool shouldReclip(JigsawClipper oldClipper) =>
      oldClipper.gridSize != gridSize ||
      oldClipper.index != index ||
      oldClipper.knob != knob ||
      oldClipper.core != core;
}
