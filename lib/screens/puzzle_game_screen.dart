import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_stats_controller.dart';
import '../controllers/puzzle_game_controller.dart';
import '../controllers/wallet_controller.dart';
import '../services/photo_picker_service.dart';
import '../widgets/puzzle_board.dart';

class PuzzleGameScreen extends StatefulWidget {
  const PuzzleGameScreen({super.key});

  @override
  State<PuzzleGameScreen> createState() => _PuzzleGameScreenState();
}

class _PuzzleGameScreenState extends State<PuzzleGameScreen> {
  int? _selectedSize;
  File? _imageFile;
  bool _rewarded = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PuzzleGameController(),
      child: Scaffold(
        appBar: AppBar(title: const Text('華容道拼圖')),
        body: Consumer<PuzzleGameController>(
          builder: (context, controller, _) {
            if (controller.isComplete && !_rewarded) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _onGameCompleted(controller));
            }
            if (_selectedSize == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('選擇模式',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _selectedSize = 3),
                      child: const Text('3 x 3'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => setState(() => _selectedSize = 4),
                      child: const Text('4 x 4'),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('3x3'),
                            selected: _selectedSize == 3,
                            onSelected: (_) {
                              setState(() {
                                _selectedSize = 3;
                                _rewarded = false;
                              });
                              if (_imageFile != null) {
                                controller.startGame(3);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('4x4'),
                            selected: _selectedSize == 4,
                            onSelected: (_) {
                              setState(() {
                                _selectedSize = 4;
                                _rewarded = false;
                              });
                              if (_imageFile != null) {
                                controller.startGame(4);
                              }
                            },
                          ),
                          Text('步數 ${controller.moveCount}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('時間 ${controller.elapsedLabel}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('數字提示'),
                        value: controller.showNumberHint,
                        onChanged: controller.setNumberHint,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _pickImageAndStart(controller),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('更換圖片'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_imageFile == null)
                  FilledButton.icon(
                    onPressed: () => _pickImageAndStart(controller),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('從相簿選擇照片'),
                  ),
                if (_imageFile != null) ...[
                  AspectRatio(
                    aspectRatio: 1,
                    child: PuzzleBoard(
                        controller: controller, imageFile: _imageFile!),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: () {
                      controller.startGame(_selectedSize!);
                      setState(() => _rewarded = false);
                    },
                    child: const Text('重新洗牌'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _onGameCompleted(PuzzleGameController controller) async {
    if (!controller.isComplete || _rewarded || !mounted) return;
    _rewarded = true;

    final wallet = context.read<WalletController>();
    final petStats = context.read<PetStatsController>();
    final droppedCoins = controller.rewardCoins();
    if (droppedCoins > 0) {
      await wallet.addCoins(droppedCoins);
    }
    await petStats.markPuzzleCompleted();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('完成拼圖'),
        content: Text(
          droppedCoins > 0
              ? '恭喜完成！獲得 $droppedCoins 金幣，親密度 +2、心情 +5。'
              : '恭喜完成！這次沒有掉落金幣，親密度 +2、心情 +5。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('好')),
        ],
      ),
    );
  }

  Future<void> _pickImageAndStart(PuzzleGameController controller) async {
    final picked = await PhotoPickerService().pickFromGallery();
    if (picked == null || !mounted || _selectedSize == null) return;
    setState(() {
      _imageFile = picked;
      _rewarded = false;
    });
    controller.startGame(_selectedSize!);
  }
}
