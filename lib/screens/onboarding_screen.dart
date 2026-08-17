import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_controller.dart';
import '../controllers/profile_controller.dart';
import '../models/pet_status.dart';
import '../models/pet_skin.dart';
import '../services/app_usage_tracking_service.dart';
import '../utils/asset_paths.dart';
import '../widgets/auth/auth_visuals.dart';
import '../widgets/pet_skin_picker.dart';

/// 首次飼主設定流程。
///
/// 流程：功能導覽（可略過）→ 三步驟設定（選夥伴 → 選外觀 → 介紹一下牠）→
/// 完成儀式。命名前一律用中性稱呼（「你的陪伴夥伴」「牠」），取名後才顯示名字。
///
/// 重要：本流程**不改任何登入 / OAuth / API / 後端 / Realtime / Care Alert /
/// 記憶邏輯**。寵物外觀沿用既有 [PetController.changeSkin]、命名沿用既有
/// [ProfileController.completeOnboarding]、家人聯絡沿用既有
/// [ProfileController.setFamilyContacts]，只是把它們組裝成更有儀式感的多步驟 UI。
///
/// 註：本專案「寵物」與「外觀」是同一個概念（狗狗 / 天竺鼠 / 狐狸＝三種外觀），
/// 沒有獨立的裝扮系統，因此第二步呈現的是「把選到的夥伴放大看清楚、可再換」，
/// 不假造不存在的裝扮功能。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _familyAliasController;
  late final TextEditingController _familyPhoneController;

  /// 設定步驟：0 選夥伴（同時是外觀）、1 取名字、2 設定關心你的人。
  static const int _stepCount = 3;
  int _step = 0;

  /// 是否進入完成儀式畫面。
  bool _showCeremony = false;

  /// 完成設定當下取得的寵物名字（用於儀式畫面顯示）。
  String _confirmedName = '';

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _familyAliasController = TextEditingController();
    _familyPhoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _familyAliasController.dispose();
    _familyPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 不再於註冊後跳出舊版多頁導覽：直接進入三步驟設定。
    // 功能介紹改由首次進首頁的新版 Spotlight 導覽負責（CoachMarkHost），避免重複。
    if (_showCeremony) {
      return _buildCeremony(context);
    }
    return _buildSetupFlow(context);
  }

  // ---------------------------------------------------------------------------
  // 三步驟設定
  // ---------------------------------------------------------------------------

  Widget _buildSetupFlow(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _StepProgressBar(step: _step, total: _stepCount),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: _buildStepContent(context),
                ),
              ),
              _buildSetupBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(BuildContext context) {
    switch (_step) {
      case 0:
        return _buildChoosePartnerStep(context);
      case 1:
        return _buildNameStep();
      default:
        return _buildCareContactStep();
    }
  }

  /// 第一步：選擇陪伴夥伴（同時代表選寵物與外觀，不再拆成兩步）。
  /// 放大顯示目前選到的夥伴，下方三選一，讓「選誰」與「長什麼樣子」一次完成。
  Widget _buildChoosePartnerStep(BuildContext context) {
    final petController = context.watch<PetController>();
    final skin = petController.currentSkin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          title: '選一位陪伴你的夥伴',
          subtitle: '先挑一個喜歡的樣子，之後也可以在設定中更換。',
        ),
        const SizedBox(height: 12),
        Center(
          child: AuthPetHero(
            imagePath: AssetPaths.stateImageForStyle(
              skin,
              PetMode.happy,
              visualStyle: petController.currentVisualStyle,
              growthStage: petController.currentGrowthStage,
            ),
            size: 180,
          ),
        ),
        const SizedBox(height: 12),
        // 新手導覽「選夥伴」：免費挑一隻起始夥伴（不走購買 / 解鎖）。
        PetSkinPicker(
          purchasable: false,
          onSkinApplied: _trackStarterSkinSelected,
        ),
      ],
    );
  }

  void _trackStarterSkinSelected(PetSkin skin) {
    try {
      final profile = context.read<PetController>().currentVisualProfile;
      unawaited(
        context.read<AppUsageTrackingService>().track(
          'pet_style_changed',
          metadata: {
            'source': 'onboarding_starter',
            'selectedPetType': skin.storageId,
            ...profile.toTrackingMetadata(),
          },
        ),
      );
    } on ProviderNotFoundException {
      // Isolated widget tests may omit analytics. The production app injects it.
    }
  }

  /// 第二步：幫牠取一個名字。
  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          title: '幫牠取一個名字',
          subtitle: '這個名字會出現在首頁與對話中，讓牠更像你的專屬夥伴。',
        ),
        const SizedBox(height: 20),
        AuthCard(
          child: AuthTextField(
            controller: _nameController,
            label: '寵物名字',
            hint: '想怎麼叫牠？',
            icon: Icons.pets,
            enabled: !_isSubmitting,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handlePrimary(),
          ),
        ),
      ],
    );
  }

  /// 第三步：設定關心你的人（家人 / 照護者聯絡，維持選填）。
  Widget _buildCareContactStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeader(
          title: '設定關心你的人',
          subtitle: '可以先填家人或照護者的聯絡方式，需要時牠可以幫你提醒；不填也沒關係。',
        ),
        const SizedBox(height: 20),
        AuthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _familyAliasController,
                label: '稱呼（例如：女兒）',
                icon: Icons.favorite_border,
                enabled: !_isSubmitting,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _familyPhoneController,
                label: '聯絡電話',
                icon: Icons.phone_outlined,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetupBottomBar() {
    final isLast = _step == _stepCount - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _isSubmitting ? null : () => setState(() => _step -= 1),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  '上一步',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: _step > 0 ? 1 : 1,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handlePrimary,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isLast ? '完成設定' : '下一步',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePrimary() {
    // 第二步（取名）必須先有名字才能往下，否則完成畫面與首頁會沒有名字可用。
    if (_step == 1 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('還沒有幫牠取名字唷')),
      );
      return;
    }
    if (_step < _stepCount - 1) {
      FocusScope.of(context).unfocus();
      setState(() => _step += 1);
      return;
    }
    _finishSetup();
  }

  /// 完成三步驟：保存（選填）家人聯絡 → 進入完成儀式。
  /// 真正翻轉 onboarding 完成狀態的 [ProfileController.completeOnboarding]
  /// 留到儀式畫面按「開始使用」才呼叫，讓使用者先看到完成畫面。
  Future<void> _finishSetup() async {
    // 名字已在第二步驗證過，這裡只取值。
    final petName = _nameController.text.trim();

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    // 選填：家人 / 照護者聯絡。沿用既有 setFamilyContacts（已過濾全空白）。
    final alias = _familyAliasController.text.trim();
    final phone = _familyPhoneController.text.trim();
    if (alias.isNotEmpty || phone.isNotEmpty) {
      await context.read<ProfileController>().setFamilyContacts([
        {'alias': alias, 'phone': phone, 'email': ''},
      ]);
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _confirmedName = petName;
      _showCeremony = true;
    });
  }

  // ---------------------------------------------------------------------------
  // 完成儀式
  // ---------------------------------------------------------------------------

  Widget _buildCeremony(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final skin = context.watch<PetController>().currentSkin;
    final hasName = _confirmedName.isNotEmpty;
    final subtitle =
        hasName ? '$_confirmedName 準備好陪你開始生活了。' : '你的 AI 寵物準備好陪你開始生活了。';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              children: [
                const Spacer(),
                // 大勾勾 + 寵物小圖。
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AuthPetHero(
                        imagePath: AssetPaths.stateImage(skin, PetMode.excited),
                        size: 220,
                      ),
                      Positioned(
                        right: 18,
                        bottom: 18,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.4),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  '完成註冊！',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.5,
                    color: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _startUsing,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '開始使用',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 按「開始使用」：呼叫既有 completeOnboarding，翻轉狀態 → AuthGate 進主畫面。
  Future<void> _startUsing() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final profile = context.read<ProfileController>();
    // 完成帳號設定後**不**預先標記「已看過」：讓新帳號首次進首頁時，由 CoachMarkHost
    // 自動播放一次新手導覽（Spotlight），導覽播完才會自行記錄已看過。
    await profile.completeOnboarding(_confirmedName);
    // completeOnboarding 會 notifyListeners，AuthGate 會把本頁換成 MainShell，
    // 首次進首頁時 CoachMarkHost 會自動開始新手導覽。
  }
}

/// 精緻的三段式流程條 + 「步驟 X / N」標示。
class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        i <= step ? primary : primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              if (i != total - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '步驟 ${step + 1} / $total',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
      ],
    );
  }
}

/// 每一步的標題 + 說明（置中、文字柔和）。
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 18,
            height: 1.5,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
