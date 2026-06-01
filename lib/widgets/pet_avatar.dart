import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../utils/asset_paths.dart';

class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    required this.mode,
    this.skin = PetSkin.dog,
    this.size = 220,
  });

  final PetMode mode;
  final PetSkin skin;
  final double size;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> {
  int _frameIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _setupAnimationTimer();
  }

  @override
  void didUpdateWidget(covariant PetAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 換外觀或換狀態都要從第一張重新播，避免沿用上一隻寵物的 frame index。
    if (widget.mode != oldWidget.mode || widget.skin != oldWidget.skin) {
      _frameIndex = 0;
      _setupAnimationTimer();
    }
  }

  void _setupAnimationTimer() {
    _timer?.cancel();
    if (widget.mode == PetMode.talking || widget.mode == PetMode.rest) {
      _timer = Timer.periodic(const Duration(milliseconds: 220), (_) {
        if (!mounted) return;
        setState(() => _frameIndex++);
      });
    }
  }

  String _imagePath() {
    if (widget.mode == PetMode.talking) {
      final frames = AssetPaths.talkingFrames(widget.skin);
      // 用取餘數，guineaPig 只有 3 張也能安全循環，不會越界。
      return frames[_frameIndex % frames.length];
    }
    if (widget.mode == PetMode.rest) {
      final frames = AssetPaths.restFrames(widget.skin);
      return frames[_frameIndex % frames.length];
    }
    if (widget.mode == PetMode.listening) {
      return AssetPaths.listening(widget.skin);
    }
    return AssetPaths.stateImage(widget.skin, widget.mode);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = _imagePath();
    return Image.asset(
      path,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        // 第一層 fallback：該外觀自己的 rest_01。
        return Image.asset(
          AssetPaths.skinRestPrimary(widget.skin),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) {
            // 第二層 fallback：永遠存在的狗狗 rest_01。
            return Image.asset(
              AssetPaths.defaultRestImage,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                // 真的全缺時才顯示白話提示（不顯示任何 asset path）。
                return Container(
                  width: widget.size,
                  height: widget.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '寵物圖片載入中',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
