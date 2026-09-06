import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../models/pet_visual_profile.dart';
import '../utils/asset_paths.dart';

/// CR-0093：rest 待機動畫的 ping-pong（來回）影格索引，通用支援 1～4 張 frame。
///
/// 不再讓最後一張直接跳回第一張，改成來回播放，看起來更柔和：
/// - N=1 → 0,0,0…
/// - N=2 → 0,1,0,1…
/// - N=3 → 0,1,2,1,0,1,2,1…（rest_01→02→03→02→01→…）
/// - N=4 → 0,1,2,3,2,1,0,1,2,3…
int pingPongFrameIndex(int counter, int frameCount) {
  if (frameCount <= 1) return 0;
  final period = 2 * (frameCount - 1); // 一個來回的長度
  final pos = counter % period;
  return pos < frameCount ? pos : period - pos;
}

/// CR-0093：動畫節奏放慢，讓待機與說話看起來更柔和（原本固定 220ms）。
const Duration kTalkFrameDuration = Duration(milliseconds: 320);
const Duration kRestFrameDuration = Duration(milliseconds: 480);

class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    required this.mode,
    this.skin = PetSkin.dog,
    this.visualStyle = PetVisualStyle.realistic,
    this.growthStage = PetGrowthStage.adult,
    this.size = 220,
  });

  final PetMode mode;
  final PetSkin skin;
  final PetVisualStyle visualStyle;
  final PetGrowthStage growthStage;
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
    if (widget.mode != oldWidget.mode ||
        widget.skin != oldWidget.skin ||
        widget.visualStyle != oldWidget.visualStyle ||
        widget.growthStage != oldWidget.growthStage) {
      _frameIndex = 0;
      _setupAnimationTimer();
    }
  }

  void _setupAnimationTimer() {
    _timer?.cancel();
    // CR-0093：talk / rest 動畫放慢；其餘狀態為單張靜態圖、不需計時器。
    final Duration? frameDuration = switch (widget.mode) {
      PetMode.talking => kTalkFrameDuration,
      PetMode.rest => kRestFrameDuration,
      _ => null,
    };
    if (frameDuration == null) return;
    _timer = Timer.periodic(frameDuration, (_) {
      if (!mounted) return;
      setState(() => _frameIndex++);
    });
  }

  String _imagePath() {
    if (widget.mode == PetMode.talking) {
      final frames = AssetPaths.talkingFramesForStyle(
        widget.skin,
        visualStyle: widget.visualStyle,
        growthStage: widget.growthStage,
      );
      // 用取餘數，guineaPig 只有 3 張也能安全循環，不會越界。
      return frames[_frameIndex % frames.length];
    }
    if (widget.mode == PetMode.rest) {
      final frames = AssetPaths.restFramesForStyle(
        widget.skin,
        visualStyle: widget.visualStyle,
        growthStage: widget.growthStage,
      );
      // CR-0093：ping-pong 來回播放（不讓最後一張直接跳回第一張）。
      return frames[pingPongFrameIndex(_frameIndex, frames.length)];
    }
    if (widget.mode == PetMode.listening) {
      return AssetPaths.listeningForStyle(
        widget.skin,
        visualStyle: widget.visualStyle,
        growthStage: widget.growthStage,
      );
    }
    return AssetPaths.stateImageForStyle(
      widget.skin,
      widget.mode,
      visualStyle: widget.visualStyle,
      growthStage: widget.growthStage,
    );
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
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        // 第一層 fallback：維持該寵物目前風格的 rest_01。
        return Image.asset(
          AssetPaths.skinRestPrimaryForStyle(
            widget.skin,
            visualStyle: widget.visualStyle,
            growthStage: widget.growthStage,
          ),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
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
