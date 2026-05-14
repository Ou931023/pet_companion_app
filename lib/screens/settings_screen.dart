import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_controller.dart';
import '../controllers/profile_controller.dart';
import '../routes/app_routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _petNameController;
  late FocusNode _petNameFocusNode;

  @override
  void initState() {
    super.initState();
    _petNameController = TextEditingController();
    _petNameFocusNode = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = context.read<ProfileController>();
    if (!_petNameFocusNode.hasFocus) {
      _petNameController.text = profile.petName;
    }
  }

  @override
  void dispose() {
    _petNameController.dispose();
    _petNameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    if (!_petNameFocusNode.hasFocus &&
        _petNameController.text != profile.petName) {
      _petNameController.text = profile.petName;
      _petNameController.selection =
          TextSelection.collapsed(offset: _petNameController.text.length);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '設定',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: '寵物名字',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _petNameController,
                focusNode: _petNameFocusNode,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '想怎麼叫牠？',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _confirmRenamePet(context, profile),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _confirmRenamePet(context, profile),
                icon: const Icon(Icons.check),
                label: const Text('更新名字'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: '看得更舒服',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fontScaleLabel(profile.fontScale),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              Slider(
                value: profile.fontScale,
                min: 0.9,
                max: 1.3,
                divisions: 4,
                label: _fontScaleLabel(profile.fontScale),
                onChanged: profile.setFontScale,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: '寵物聲音',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: profile.ttsEnabled,
                title: const Text('讓寵物出聲說話'),
                onChanged: profile.setTtsEnabled,
              ),
              Row(
                children: [
                  const Icon(Icons.volume_down),
                  Expanded(
                    child: Slider(
                      value: profile.petVolume,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      label: '${(profile.petVolume * 100).round()}%',
                      onChanged:
                          profile.ttsEnabled ? profile.setPetVolume : null,
                    ),
                  ),
                  const Icon(Icons.volume_up),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: '說話方式',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'gentle', label: Text('溫柔')),
              ButtonSegment(value: 'calm', label: Text('慢慢說')),
              ButtonSegment(value: 'bright', label: Text('有精神')),
            ],
            selected: {profile.speechStyle},
            onSelectionChanged: (values) =>
                profile.setSpeechStyle(values.first),
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: '喜歡聽的內容',
          child: Column(
            children: [
              _PreferenceTile(
                value: 'story',
                title: '喜歡聽故事',
                profile: profile,
              ),
              _PreferenceTile(
                value: 'news',
                title: '喜歡聽新聞',
                profile: profile,
              ),
              _PreferenceTile(
                value: 'healthTip',
                title: '喜歡健康提醒',
                profile: profile,
              ),
              _PreferenceTile(
                value: 'lifeTip',
                title: '喜歡生活小知識',
                profile: profile,
              ),
              _PreferenceTile(
                value: 'spiritual',
                title: '喜歡心靈鼓勵',
                profile: profile,
              ),
              _PreferenceTile(
                value: 'nostalgicStory',
                title: '喜歡懷舊話題',
                profile: profile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: '日常提醒',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoute.reminders),
                icon: const Icon(Icons.alarm),
                label: const Text('管理提醒'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoute.memories),
                icon: const Icon(Icons.psychology_alt_outlined),
                label: const Text('管理長期記憶'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRenamePet(
    BuildContext context,
    ProfileController profile,
  ) async {
    final newName = _petNameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('還沒有幫寵物取名唷')),
      );
      return;
    }

    if (newName == profile.petName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名字沒有變更')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認更改名字？'),
        content: Text('要把寵物名字改成「$newName」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先不要'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認更改'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await profile.renamePet(newName, source: 'settings');
    if (!context.mounted) return;
    context.read<PetController>().setMessage('好呀，以後我就叫$newName。');
    _petNameFocusNode.unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已更新為 $newName')),
    );
  }

  String _fontScaleLabel(double value) {
    if (value >= 1.25) return '文字：最大';
    if (value >= 1.1) return '文字：較大';
    if (value < 1.0) return '文字：較小';
    return '文字：標準';
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.value,
    required this.title,
    required this.profile,
  });

  final String value;
  final String title;
  final ProfileController profile;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: profile.contentPreferences.contains(value),
      title: Text(title),
      onChanged: (checked) =>
          profile.setContentPreference(value, checked ?? false),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
