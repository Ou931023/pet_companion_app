import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../controllers/conversation_controller.dart';
import '../controllers/pet_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/voice_agent_controller.dart';
import '../models/language_route.dart';
import '../routes/app_routes.dart';
import '../services/realtime_voice_service.dart';
import '../widgets/companion_debug_panel.dart';

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
          title: '語音輸入方式',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<VoiceLanguageMode>(
                segments: const [
                  ButtonSegment(
                    value: VoiceLanguageMode.defaultOpenAiRealtime,
                    label: Text('即時語音對話'),
                  ),
                  ButtonSegment(
                    value: VoiceLanguageMode.taigiPreferred,
                    label: Text('台語短錄音'),
                  ),
                  ButtonSegment(
                    value: VoiceLanguageMode.manualOverride,
                    label: Text('手動'),
                  ),
                ],
                selected: {profile.voiceLanguageMode},
                onSelectionChanged: (values) {
                  context
                      .read<ConversationController>()
                      .clearPendingTaigiAsrTranscript();
                  profile.setVoiceLanguageMode(values.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                profile.voiceLanguageMode == VoiceLanguageMode.taigiPreferred
                    ? '台語短錄音會先錄下語音，再辨識成文字讓寵物回覆。'
                    : '即時語音對話會使用原本的 Realtime 連線。台語短錄音不會影響即時語音功能。',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (profile.voiceLanguageMode ==
                  VoiceLanguageMode.manualOverride) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: profile.manualAsrStrategy,
                  decoration: const InputDecoration(
                    labelText: '手動指定 ASR strategy',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'defaultOpenAiRealtime',
                      child: Text('OpenAI Realtime'),
                    ),
                    DropdownMenuItem(
                      value: 'mockTaigiAsr',
                      child: Text('台語 ASR adapter'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      profile.setManualAsrStrategy(value);
                    }
                  },
                ),
              ],
            ],
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
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'AI Agent',
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoute.agentToolDemo),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI Agent 工具測試'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _SettingsSection(
          title: '寵物代辦',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PetCommandChip(
                label: '幫我簽到',
                command: '幫我簽到',
              ),
              _PetCommandChip(
                label: '買小餅乾',
                command: '幫我買小餅乾',
              ),
              _PetCommandChip(
                label: '聲音關掉',
                command: '把聲音關掉',
              ),
              _PetCommandChip(
                label: '文字調大',
                command: '把文字調大',
              ),
              _PetCommandChip(
                label: '慢慢說',
                command: '說話慢一點',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Realtime Diagnostics',
          child: Consumer3<VoiceAgentController, RealtimeVoiceService,
              ConversationController>(
            builder: (context, voice, realtime, conversation, _) {
              return _RealtimeDiagnosticsPanel(
                voiceController: voice,
                realtimeService: realtime,
                conversationController: conversation,
                profile: profile,
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: 'Companion Debug Panel',
          child: Consumer<ConversationController>(
            builder: (context, conversation, _) {
              return CompanionDebugPanel(
                info: conversation.latestCompanionDebugInfo,
              );
            },
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

class _RealtimeDiagnosticsPanel extends StatefulWidget {
  const _RealtimeDiagnosticsPanel({
    required this.voiceController,
    required this.realtimeService,
    required this.conversationController,
    required this.profile,
  });

  final VoiceAgentController voiceController;
  final RealtimeVoiceService realtimeService;
  final ConversationController conversationController;
  final ProfileController profile;

  @override
  State<_RealtimeDiagnosticsPanel> createState() =>
      _RealtimeDiagnosticsPanelState();
}

class _RealtimeDiagnosticsPanelState extends State<_RealtimeDiagnosticsPanel> {
  bool _isChecking = false;
  String _healthMessage = '尚未檢查';

  @override
  Widget build(BuildContext context) {
    final health = widget.realtimeService.lastHealthStatus;
    final lastFailure = widget.realtimeService.lastFailureType;
    final companionContext = widget.voiceController.currentCompanionContext;
    final fusion = companionContext?.fusion;
    final voiceFeatures = companionContext?.voiceFeatures;
    final searchParts = [
      if (widget.conversationController.latestSearchMode.isNotEmpty)
        'mode=${widget.conversationController.latestSearchMode}',
      if (widget.conversationController.latestSearchProvider.isNotEmpty)
        'provider=${widget.conversationController.latestSearchProvider}',
      if (widget.conversationController.latestToolUsed.isNotEmpty)
        'tool=${widget.conversationController.latestToolUsed}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DiagnosticLine(
          label: 'Backend health',
          value: health == null
              ? _healthMessage
              : '${health.ok ? 'OK' : '失敗'} / OpenAI Key: ${health.hasOpenAiKey ? '已設定' : '未設定'}',
        ),
        _DiagnosticLine(
          label: 'Realtime model',
          value: health?.realtimeModel.isNotEmpty == true
              ? health!.realtimeModel
              : '尚未取得',
        ),
        const _DiagnosticLine(
          label: 'Microphone permission',
          value: '啟動語音時由系統確認',
        ),
        _DiagnosticLine(
          label: '最近 ASR strategy',
          value: widget.voiceController.strategyName.isEmpty
              ? '-'
              : widget.voiceController.strategyName,
        ),
        _DiagnosticLine(
          label: '最近 languageHint',
          value: widget.voiceController.languageHint.isEmpty
              ? '-'
              : widget.voiceController.languageHint,
        ),
        _DiagnosticLine(
          label: '最近 routeReason',
          value: widget.voiceController.routeReason.isEmpty
              ? '-'
              : widget.voiceController.routeReason,
        ),
        _DiagnosticLine(
          label: '最近 emotion fusion',
          value: fusion == null
              ? '-'
              : '${fusion.textEmotion} -> ${fusion.finalEmotion}'
                  '${fusion.reason.isEmpty ? '' : ' / ${fusion.reason}'}',
        ),
        _DiagnosticLine(
          label: '最近 voice features',
          value: voiceFeatures == null
              ? '-'
              : 'pauseDensity=${_formatNumber(voiceFeatures.pauseDensity)}, '
                  'speechRate=${_formatNumber(voiceFeatures.estimatedSpeechRate)}',
        ),
        _DiagnosticLine(
          label: '最近 search metadata',
          value: searchParts.isEmpty ? '-' : searchParts.join(' / '),
        ),
        _DiagnosticLine(
          label: '最近錯誤',
          value: lastFailure == RealtimeFailureType.none
              ? '無'
              : '${lastFailure.name}：${widget.realtimeService.lastFailureMessage}',
        ),
        _DiagnosticLine(
          label: 'WebRTC',
          value:
              'peer=${widget.realtimeService.lastConnectionState.isEmpty ? '-' : widget.realtimeService.lastConnectionState}, '
              'ice=${widget.realtimeService.lastIceConnectionState.isEmpty ? '-' : widget.realtimeService.lastIceConnectionState}, '
              'data=${widget.realtimeService.dataChannelState}',
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isChecking ? null : _checkRealtimeHealth,
          icon: _isChecking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check),
          label: const Text('測試 Realtime 連線'),
        ),
      ],
    );
  }

  String _formatNumber(double? value) {
    if (value == null) return '-';
    return value.toStringAsFixed(2);
  }

  Future<void> _checkRealtimeHealth() async {
    setState(() {
      _isChecking = true;
      _healthMessage = '檢查中';
    });
    final health = await widget.realtimeService.checkBackendHealth(
      AppConfig.healthUrlForSttProxy(widget.profile.sttProxyUrl),
    );
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _healthMessage = health.ok ? 'OK' : health.message;
    });
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '$label：$value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PetCommandChip extends StatelessWidget {
  const _PetCommandChip({
    required this.label,
    required this.command,
  });

  final String label;
  final String command;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.pets, size: 18),
      label: Text(label),
      onPressed: () {
        context.read<ConversationController>().quickAction(command);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已請寵物處理：$label')),
        );
      },
    );
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
