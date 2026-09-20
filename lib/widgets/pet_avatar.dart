import 'dart:math' as math;

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

/// 舊版 full-frame 動畫的測試相容常數。
///
/// CR-0100F 起，正式 renderer 不再依這兩個間隔切換整張角色圖，避免臉型、
/// 身形與腳底基準線在說話時閃爍。角色改由固定主圖搭配連續 motion 動畫。
@Deprecated('PetAvatar now uses continuous motion instead of full-frame swaps.')
const Duration kTalkFrameDuration = Duration(milliseconds: 320);
@Deprecated('PetAvatar now uses continuous motion instead of full-frame swaps.')
const Duration kRestFrameDuration = Duration(milliseconds: 480);

const Duration kPetImageTransitionDuration = Duration(milliseconds: 220);
const Duration kPetTalkingMotionDuration = Duration(milliseconds: 720);
const Duration kPetListeningMotionDuration = Duration(milliseconds: 1200);
const Duration kPetExcitedMotionDuration = Duration(milliseconds: 820);
const Duration kPetBreathingMotionDuration = Duration(milliseconds: 2400);

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

class _PetAvatarState extends State<PetAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(vsync: this);
    _configureMotion(restart: true);
  }

  @override
  void didUpdateWidget(covariant PetAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode ||
        widget.skin != oldWidget.skin ||
        widget.visualStyle != oldWidget.visualStyle ||
        widget.growthStage != oldWidget.growthStage) {
      _configureMotion(restart: true);
    }
  }

  void _configureMotion({required bool restart}) {
    _motionController.duration = switch (widget.mode) {
      PetMode.talking => kPetTalkingMotionDuration,
      PetMode.listening => kPetListeningMotionDuration,
      PetMode.happy ||
      PetMode.smile ||
      PetMode.excited =>
        kPetExcitedMotionDuration,
      _ => kPetBreathingMotionDuration,
    };
    if (restart) _motionController.value = 0;
    _motionController.repeat(reverse: true);
  }

  String _imagePath() {
    if (widget.mode == PetMode.talking) {
      // 說話時固定角色主圖，只做連續律動。舊版輪播不同全身姿勢會造成
      // 臉型、四肢與比例閃動，對長者尤其干擾。
      return AssetPaths.skinRestPrimaryForStyle(
        widget.skin,
        visualStyle: widget.visualStyle,
        growthStage: widget.growthStage,
      );
    }
    if (widget.mode == PetMode.rest) {
      return AssetPaths.skinRestPrimaryForStyle(
        widget.skin,
        visualStyle: widget.visualStyle,
        growthStage: widget.growthStage,
      );
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
    _motionController.dispose();
    super.dispose();
  }

  ({double scale, double translateY, double rotation}) _motionAt(
    double rawValue,
  ) {
    final value = Curves.easeInOut.transform(rawValue);
    final wave = math.sin(value * math.pi);
    return switch (widget.mode) {
      PetMode.talking => (
          scale: 1 + (wave * 0.018),
          translateY: -widget.size * wave * 0.012,
          rotation: math.sin(value * math.pi * 2) * 0.004,
        ),
      PetMode.listening => (
          scale: 1 + (wave * 0.008),
          translateY: -widget.size * wave * 0.004,
          rotation: (value - 0.5) * 0.024,
        ),
      PetMode.happy || PetMode.smile || PetMode.excited => (
          scale: 1 + (wave * 0.014),
          translateY: -widget.size * wave * 0.018,
          rotation: math.sin(value * math.pi * 2) * 0.006,
        ),
      _ => (
          scale: 1 + (wave * 0.010),
          translateY: widget.size * wave * 0.006,
          rotation: 0,
        ),
    };
  }

  Widget _buildImage(String path) {
    return Image.asset(
      path,
      key: ValueKey('pet-avatar-image-$path'),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        final styleFallback = AssetPaths.skinRestPrimaryForStyle(
          widget.skin,
          visualStyle: widget.visualStyle,
          growthStage: widget.growthStage,
        );
        return Image.asset(
          path == styleFallback ? AssetPaths.defaultRestImage : styleFallback,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Image.asset(
            AssetPaths.defaultRestImage,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
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
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = _imagePath();
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _motionController,
          builder: (context, child) {
            final motion = _motionAt(_motionController.value);
            return Transform.translate(
              key: const ValueKey('pet-avatar-motion'),
              offset: Offset(0, motion.translateY),
              child: Transform.rotate(
                angle: motion.rotation,
                child: Transform.scale(scale: motion.scale, child: child),
              ),
            );
          },
          child: AnimatedSwitcher(
            duration: kPetImageTransitionDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.center,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild
              ],
            ),
            child: _buildImage(path),
          ),
        ),
      ),
    );
  }
}
