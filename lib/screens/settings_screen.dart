import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../controllers/auth_controller.dart';
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
                    label: Text('中文即時語音'),
                  ),
                  ButtonSegment(
                    value: VoiceLanguageMode.taigiRealtime,
                    label: Text('台語即時語音'),
                  ),
                ],
                selected: {
                  profile.voiceLanguageMode == VoiceLanguageMode.taigiRealtime
                      ? VoiceLanguageMode.taigiRealtime
                      : VoiceLanguageMode.defaultOpenAiRealtime,
                },
                onSelectionChanged: (values) {
                  context
                      .read<ConversationController>()
                      .clearPendingTaigiAsrTranscript();
                  profile.setVoiceLanguageMode(values.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                switch (profile.voiceLanguageMode) {
                  VoiceLanguageMode.taigiRealtime =>
                    '台語即時語音對話會使用原本即時語音連線，可以直接用台語或台語混中文跟寵物說話。',
                  _ =>
                    '中文即時語音對話會使用原本的 Realtime 連線。',
                },
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoute.careAlerts),
                icon: const Icon(Icons.favorite_outline),
                label: const Text('今日關心紀錄'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: '家人聯絡人',
          child: _FamilyContactsEditor(profile: profile),
        ),
        if (AppConfig.showDevPanels) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                title: const Text(
                  '進階診斷（開發人員）',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  '開發人員診斷資訊，僅在啟用 SHOW_DEV_PANELS 時顯示',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  const Text(
                    'Realtime Diagnostics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Consumer3<VoiceAgentController, RealtimeVoiceService,
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
                  const SizedBox(height: 18),
                  const Text(
                    'Companion Debug Panel',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Consumer<ConversationController>(
                    builder: (context, conversation, _) {
                      return CompanionDebugPanel(
                        info: conversation.latestCompanionDebugInfo,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SettingsSection(
          title: '帳號',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '登出後會回到一開始的畫面，下次再進來就好。',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout, size: 26),
                  label: const Text(
                    '登出',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: const Color(0xFFC2410C),
                    side: const BorderSide(color: Color(0xFFC2410C), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '要登出嗎？',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '登出後會回到一開始的登入畫面，你的紀錄都還在，隨時可以再進來。',
            style: TextStyle(fontSize: 18, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('先不要', style: TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '登出',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC2410C),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;
    // 只要把狀態切成未登入，app.dart 的 AuthGate 會自動回到 LoginScreen，
    // 不需要在這裡手動導航。
    await context.read<AuthController>().logout();
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

class _FamilyContactsEditor extends StatefulWidget {
  const _FamilyContactsEditor({required this.profile});

  final ProfileController profile;

  @override
  State<_FamilyContactsEditor> createState() => _FamilyContactsEditorState();
}

class _ContactDraft {
  _ContactDraft({String alias = '', String phone = '', String email = ''})
      : alias = TextEditingController(text: alias),
        phone = TextEditingController(text: phone),
        email = TextEditingController(text: email),
        aliasFocus = FocusNode(),
        phoneFocus = FocusNode(),
        emailFocus = FocusNode();

  final TextEditingController alias;
  final TextEditingController phone;
  final TextEditingController email;
  final FocusNode aliasFocus;
  final FocusNode phoneFocus;
  final FocusNode emailFocus;

  Map<String, String> toMap() => {
        'alias': alias.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
      };

  bool get hasFocus =>
      aliasFocus.hasFocus || phoneFocus.hasFocus || emailFocus.hasFocus;

  void dispose() {
    alias.dispose();
    phone.dispose();
    email.dispose();
    aliasFocus.dispose();
    phoneFocus.dispose();
    emailFocus.dispose();
  }
}

class _FamilyContactsEditorState extends State<_FamilyContactsEditor> {
  late final List<_ContactDraft> _drafts;

  @override
  void initState() {
    super.initState();
    final saved = widget.profile.familyContacts;
    if (saved.isEmpty) {
      _drafts = [_attachListeners(_ContactDraft())];
    } else {
      _drafts = saved
          .map((c) => _attachListeners(_ContactDraft(
                alias: c['alias'] ?? '',
                phone: c['phone'] ?? '',
                email: c['email'] ?? '',
              )))
          .toList();
    }
  }

  _ContactDraft _attachListeners(_ContactDraft draft) {
    draft.aliasFocus.addListener(_persistOnAnyBlur);
    draft.phoneFocus.addListener(_persistOnAnyBlur);
    draft.emailFocus.addListener(_persistOnAnyBlur);
    return draft;
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _persistOnAnyBlur() {
    if (_drafts.any((d) => d.hasFocus)) return;
    _save();
  }

  Future<void> _save() async {
    await widget.profile
        .setFamilyContacts(_drafts.map((d) => d.toMap()).toList());
  }

  void _addRow() {
    setState(() => _drafts.add(_attachListeners(_ContactDraft())));
  }

  Future<void> _removeRow(int index) async {
    setState(() {
      _drafts[index].dispose();
      _drafts.removeAt(index);
      if (_drafts.isEmpty) _drafts.add(_attachListeners(_ContactDraft()));
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _drafts.length; i++) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _drafts[i].alias,
                  focusNode: _drafts[i].aliasFocus,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '暱稱（例：女兒、王醫師）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: '刪除',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeRow(i),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _drafts[i].phone,
            focusNode: _drafts[i].phoneFocus,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '電話',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _drafts[i].email,
            focusNode: _drafts[i].emailFocus,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          if (i < _drafts.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            )
          else
            const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add),
          label: const Text('新增聯絡人'),
        ),
      ],
    );
  }
}

