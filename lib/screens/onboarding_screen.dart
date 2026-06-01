import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/profile_controller.dart';
import '../utils/asset_paths.dart';
import '../widgets/feature_tour.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _nameController;
  // CR-0010：先看完功能導覽（可略過），再進到寵物命名。命名完成 → completeOnboarding
  // 翻轉 elderId 各自的 hasCompletedOnboarding，沿用既有 app gate 不重寫。
  bool _tourDone = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_tourDone) {
      return FeatureTourView(
        pages: featureTourPages,
        finishLabel: '下一步',
        onFinish: () => setState(() => _tourDone = true),
        onSkip: () => setState(() => _tourDone = true),
      );
    }
    return _buildNamingStep(context);
  }

  Widget _buildNamingStep(BuildContext context) {
    final profileController = context.read<ProfileController>();
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const pagePadding = EdgeInsets.all(24);
            final minContentHeight =
                (constraints.maxHeight - pagePadding.vertical)
                    .clamp(0.0, double.infinity);

            return SingleChildScrollView(
              padding: pagePadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minContentHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        '歡迎使用愛陪伴，先幫你的陪伴寵物取一個名字吧。',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Image.asset(
                          AssetPaths.defaultRestImage,
                          width: 240,
                          height: 240,
                          errorBuilder: (_, __, ___) => Container(
                            width: 240,
                            height: 240,
                            alignment: Alignment.center,
                            color: Colors.grey.shade200,
                            child: const Icon(
                              Icons.pets,
                              size: 96,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          labelText: '寵物名稱',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) =>
                            _completeOnboarding(context, profileController),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () =>
                              _completeOnboarding(context, profileController),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              '開始使用',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _completeOnboarding(
    BuildContext context,
    ProfileController profileController,
  ) async {
    final petName = _nameController.text.trim();
    if (petName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('還沒有幫寵物取名唷')),
      );
      return;
    }

    await profileController.completeOnboarding(petName);
  }
}
