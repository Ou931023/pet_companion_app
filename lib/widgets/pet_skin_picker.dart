import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_controller.dart';
import '../controllers/wallet_controller.dart';
import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../utils/asset_paths.dart';

/// 長者友善的寵物外觀選擇器：每個選項一張預覽圖 + 中文名稱。
///
/// - 已擁有：可直接點一下套用（目前使用中的標「使用中」）。
/// - 未擁有：顯示解鎖所需金幣，點一下先確認、再用既有 wallet 扣點解鎖並套用。
///   點數不足會顯示長者看得懂的提醒，不會直接扣點。
///
/// 用於設定頁與首頁「更換外觀」彈出視窗（[purchasable] 預設 true）。
/// 新手導覽「選夥伴」用 [purchasable] = false：免費挑一隻起始夥伴。
class PetSkinPicker extends StatelessWidget {
  const PetSkinPicker({
    super.key,
    this.compact = false,
    this.purchasable = true,
    this.onSkinApplied,
  });

  /// 緊湊模式：略縮預覽圖與卡片內距，給空間有限的場合（如首頁 bottom sheet）。
  final bool compact;

  /// 是否走「購買 / 解鎖」流程。false → 免費挑起始夥伴（新手導覽用）。
  final bool purchasable;

  /// 成功換上新外觀後呼叫。重複點目前使用中的外觀不會觸發。
  final ValueChanged<PetSkin>? onSkinApplied;

  Future<void> _handleTap(BuildContext context, PetSkin skin) async {
    final pet = context.read<PetController>();
    final previous = pet.currentSkin;

    // 新手導覽：免費挑起始夥伴，不走購買。
    if (!purchasable) {
      await pet.selectStarterSkin(skin);
      if (pet.currentSkin != previous) onSkinApplied?.call(pet.currentSkin);
      return;
    }

    // 已擁有：點一下立即套用。
    if (pet.isOwned(skin)) {
      await pet.changeSkin(skin);
      if (pet.currentSkin != previous) onSkinApplied?.call(pet.currentSkin);
      return;
    }

    // 未擁有：先確認，再扣點（不直接扣點）。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('解鎖${skin.label}'),
        content: Text('要用 ${skin.unlockCost} 點解鎖${skin.label}，並換上牠嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先不要', style: TextStyle(fontSize: 18)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('解鎖', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final wallet = context.read<WalletController>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await pet.purchaseAndApplySkin(
      skin,
      spendCoins: wallet.spendCoins,
    );
    if (!context.mounted) return;
    if (pet.currentSkin != previous &&
        result != SkinPurchaseResult.insufficientCoins) {
      onSkinApplied?.call(pet.currentSkin);
    }
    final message = switch (result) {
      SkinPurchaseResult.insufficientCoins => '點數還不夠喔，可以先完成每日任務再來解鎖。',
      SkinPurchaseResult.purchasedAndApplied => '已經幫你換上${skin.label}了。',
      SkinPurchaseResult.applied => '已換上${skin.label}。',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final petController = context.watch<PetController>();
    final current = petController.currentSkin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final skin in PetSkin.values) ...[
          _SkinOptionTile(
            skin: skin,
            selected: skin == current,
            owned: !purchasable || petController.isOwned(skin),
            purchasable: purchasable,
            compact: compact,
            onTap: () => _handleTap(context, skin),
          ),
          if (skin != PetSkin.values.last) SizedBox(height: compact ? 8 : 10),
        ],
      ],
    );
  }
}

class _SkinOptionTile extends StatelessWidget {
  const _SkinOptionTile({
    required this.skin,
    required this.selected,
    required this.owned,
    required this.purchasable,
    required this.onTap,
    this.compact = false,
  });

  final PetSkin skin;
  final bool selected;
  final bool owned;
  final bool purchasable;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final semanticsLabel = selected
        ? '${skin.label}，使用中'
        : owned
            ? '${skin.label}，使用這個外觀'
            : '${skin.label}，尚未解鎖，需要 ${skin.unlockCost} 點';
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: Material(
        color: selected ? primary.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(compact ? 9 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? primary : Colors.black12,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _SkinPreview(skin: skin, selected: selected, compact: compact),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        skin.label,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        owned ? skin.tagline : '需要 ${skin.unlockCost} 點解鎖',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  selected: selected,
                  owned: owned,
                  cost: skin.unlockCost,
                  primary: primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 外觀狀態徽章：
/// - 使用中 → 實心主色「使用中」。
/// - 已擁有未使用 → 柔色「使用這個外觀」。
/// - 未擁有 → 柔色「解鎖 NN」。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.selected,
    required this.owned,
    required this.cost,
    required this.primary,
  });

  final bool selected;
  final bool owned;
  final int cost;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final label = selected
        ? '使用中'
        : owned
            ? '使用這個外觀'
            : '解鎖 $cost';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? primary : primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : primary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SkinPreview extends StatelessWidget {
  const _SkinPreview({
    required this.skin,
    this.selected = false,
    this.compact = false,
  });

  final PetSkin skin;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final size = compact ? 72.0 : 84.0;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: selected
            ? primary.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Image.asset(
        AssetPaths.stateImage(skin, PetMode.normal),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Image.asset(
          AssetPaths.skinRestPrimary(skin),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.asset(
            AssetPaths.defaultRestImage,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 40),
          ),
        ),
      ),
    );
  }
}
