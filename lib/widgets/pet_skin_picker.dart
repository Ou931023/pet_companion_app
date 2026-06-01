import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_controller.dart';
import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../utils/asset_paths.dart';

/// 長者友善的寵物外觀選擇器：每個選項一張預覽圖 + 中文名稱，
/// 目前使用中的會標「使用中」。點一下立即切換並保存。
/// 同時用於設定頁與首頁「更換外觀」彈出視窗。
class PetSkinPicker extends StatelessWidget {
  const PetSkinPicker({super.key});

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
            onTap: () => petController.changeSkin(skin),
          ),
          if (skin != PetSkin.values.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SkinOptionTile extends StatelessWidget {
  const _SkinOptionTile({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final PetSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${skin.label}${selected ? '，使用中' : ''}',
      child: Material(
        color: selected ? primary.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? primary : Colors.black12,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _SkinPreview(skin: skin),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    skin.label,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '使用中',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkinPreview extends StatelessWidget {
  const _SkinPreview({required this.skin});

  final PetSkin skin;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    return SizedBox(
      width: size,
      height: size,
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
