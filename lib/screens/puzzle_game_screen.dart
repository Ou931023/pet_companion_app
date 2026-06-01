import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_stats_controller.dart';
import '../controllers/puzzle_game_controller.dart';
import '../controllers/wallet_controller.dart';
import '../services/photo_picker_service.dart';
import '../widgets/puzzle_board.dart';
import '../widgets/puzzle_tile_widget.dart';

/// 回憶拼圖小遊戲：選一張照片 → 選難度 → 把下方打亂的 jigsaw 拼圖塊拖到上面正確位置。
class PuzzleGameScreen extends StatefulWidget {
  const PuzzleGameScreen({super.key});

  @override
  State<PuzzleGameScreen> createState() => _PuzzleGameScreenState();
}

class _PuzzleGameScreenState extends State<PuzzleGameScreen> {
  File? _imageFile;
  bool _rewarded = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PuzzleGameController(),
      child: Scaffold(
        appBar: AppBar(title: const Text('回憶拼圖')),
        body: Consumer<PuzzleGameController>(
          builder: (context, controller, _) {
            if (controller.isComplete && !_rewarded) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _onCompleted(controller));
            }
            if (_imageFile == null) {
              return _buildPickPrompt(controller);
            }
            if (!controller.isStarted) {
              return _buildDifficultyPrompt(controller);
            }
            return _buildGame(controller);
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _buildPickPrompt(PuzzleGameController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              '選一張照片，拼回屬於你的回憶。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _pickImage(controller),
              icon: const Icon(Icons.photo_library, size: 26),
              label: const Text('從相簿選照片',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyPrompt(PuzzleGameController controller) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('選擇難度',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('把下面的小拼圖拖到上面正確的位置。',
            style: TextStyle(
                fontSize: 16, color: Colors.black.withValues(alpha: 0.6))),
        const SizedBox(height: 16),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.file(_imageFile!, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _difficultyButton(controller, label: '簡單：3 x 3', size: 3),
        const SizedBox(height: 12),
        _difficultyButton(controller, label: '挑戰：4 x 4', size: 4),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _pickImage(controller),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('換一張照片'),
        ),
      ],
    );
  }

  Widget _difficultyButton(
    PuzzleGameController controller, {
    required String label,
    required int size,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: () {
          setState(() => _rewarded = false);
          controller.startGame(size);
        },
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _buildGame(PuzzleGameController controller) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('時間 ${controller.elapsedLabel}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('步數 ${controller.moveAttempts}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        // 上方拼圖板。
        PuzzleBoard(
          controller: controller,
          imageFile: _imageFile!,
          onWrong: _showWrongHint,
        ),
        const SizedBox(height: 14),
        Text(
          '把下面的小拼圖拖到上面正確的位置',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 15, color: Colors.black.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 10),
        // 下方拼圖區（打亂、可換行）。
        _buildTray(controller),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() => _rewarded = false);
                  controller.startGame(controller.size);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('再玩一次'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(controller),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('換一張照片'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTray(PuzzleGameController controller) {
    const cell = 64.0;
    final box = JigsawPiece.boxOf(cell);
    final pieces = controller.trayPieces;
    if (pieces.isEmpty) {
      return SizedBox(height: box);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final piece in pieces)
          Draggable<int>(
            data: piece,
            feedback: Material(
              color: Colors.transparent,
              child: JigsawPiece(
                imageFile: _imageFile!,
                gridSize: controller.size,
                index: piece,
                cell: cell * 1.1,
              ),
            ),
            childWhenDragging: SizedBox(width: box, height: box),
            child: JigsawPiece(
              imageFile: _imageFile!,
              gridSize: controller.size,
              index: piece,
              cell: cell,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------

  void _showWrongHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('位置不對，拼圖會回到下面喔'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _pickImage(PuzzleGameController controller) async {
    final picked = await PhotoPickerService().pickFromGallery();
    if (picked == null || !mounted) return; // 取消選圖：不做事、不 crash
    final hadImage = _imageFile != null;
    setState(() {
      _imageFile = picked;
      _rewarded = false;
    });
    // 已經在玩了（換照片）→ 直接用同難度重開；第一次選圖則停在難度選擇。
    if (hadImage && controller.isStarted) {
      controller.startGame(controller.size);
    }
  }

  Future<void> _onCompleted(PuzzleGameController controller) async {
    if (!controller.isComplete || _rewarded || !mounted) return;
    _rewarded = true;

    final result = controller.result;
    final wallet = context.read<WalletController>();
    final petStats = context.read<PetStatsController>();
    final coins = controller.rewardCoins();
    if (coins > 0) await wallet.addCoins(coins);
    await petStats.markPuzzleCompleted();

    if (!mounted || result == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          '太棒了，回憶拼圖完成！',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '用時 ${controller.elapsedLabel}，總共 ${result.moveAttempts} 步。\n'
          '${coins > 0 ? '獲得 $coins 金幣，' : ''}親密度 +2、心情 +5。',
          style: const TextStyle(fontSize: 17, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() => _rewarded = false);
              controller.startGame(controller.size);
            },
            child: const Text('再玩一次', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _pickImage(controller);
            },
            child: const Text('換一張照片', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}
