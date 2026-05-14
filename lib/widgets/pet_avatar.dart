import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet_status.dart';
import '../utils/asset_paths.dart';

class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    required this.mode,
    this.size = 220,
  });

  final PetMode mode;
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
    if (widget.mode != oldWidget.mode) {
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
      return AssetPaths
          .talkingFrames[_frameIndex % AssetPaths.talkingFrames.length];
    }
    if (widget.mode == PetMode.rest) {
      return AssetPaths.restFrames[_frameIndex % AssetPaths.restFrames.length];
    }
    if (widget.mode == PetMode.listening) {
      return AssetPaths.listening;
    }
    return AssetPaths.staticModes[widget.mode] ??
        AssetPaths.staticModes[PetMode.normal]!;
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
        // If specific state images (such as dog_normal.png / dog_sad.png) are missing,
        // safely fallback to dog_rest_01.png to avoid runtime crashes.
        return Image.asset(
          'assets/pets/rest/dog_rest_01.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) {
            return Container(
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                '請放置寵物圖片素材',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            );
          },
        );
      },
    );
  }
}
