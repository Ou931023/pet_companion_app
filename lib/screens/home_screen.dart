import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/daily_reward.dart';
import '../onboarding/coach_mark_controller.dart';
import '../onboarding/coach_mark_keys.dart';
import '../controllers/check_in_controller.dart';
import '../controllers/agent_tool_controller.dart';
import '../controllers/conversation_controller.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/memory_controller.dart';
import '../controllers/pet_controller.dart';
import '../controllers/pet_stats_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/voice_agent_controller.dart';
import '../controllers/wallet_controller.dart';
import '../services/app_usage_tracking_service.dart';
import '../services/notification_service.dart';
import '../models/inventory_item.dart';
import '../models/language_route.dart';
import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../utils/pet_state_selector.dart';
import '../models/pet_stats.dart';
import '../models/source_reference.dart';
import '../models/voice_agent_state.dart';
import '../utils/voice_button_presentation.dart';
import '../routes/app_routes.dart';
import '../widgets/agent/agent_confirmation_sheet.dart';
import '../widgets/coin_badge.dart';
import '../widgets/conversation_bubble_stack.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/pet_skin_picker.dart';
import '../widgets/pet_status_panel.dart';
import '../widgets/source_reference_list.dart';
import '../widgets/text_conversation_bar.dart';
import '../widgets/ui/primary_action_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _messageController = TextEditingController();
  bool _didWelcome = false;
  bool _isPetDragHovering = false;
  bool _showInventoryPanel = false;
  bool _inventoryTrayLowered = false;
  bool _didCheckTaigiAsrStatus = false;
  bool _didTrackAppOpen = false;
  bool _showTextInput = false;
  // CR-0088：對話結束後短暫顯示情緒狀態。記住已處理過的最新一則對話，避免重複觸發。
  ConversationController? _conversationForTransient;
  String? _lastTransientTurnKey;
  // 已對哪個 pendingIntent 顯示過確認 sheet（避免 rebuild 重複彈出）。
  String? _shownConfirmIntentId;

  @override
  void dispose() {
    _conversationForTransient?.removeListener(_maybeFireTransientState);
    _messageController.dispose();
    super.dispose();
  }

  /// 對話新增一則（含情緒）時，讓寵物短暫顯示對應情緒狀態（happy / caring / sad…）。
  /// 首頁狀態選擇器會在非收音 / 非播放時顯示它，到期自動退回 rest / care state。
  void _maybeFireTransientState() {
    if (!mounted) return;
    final history = _conversationForTransient?.history ?? const [];
    if (history.isEmpty) return;
    final latest = history.first; // 最新在前
    final key = '${latest.timestamp.toIso8601String()}|${latest.emotionTag}';
    if (key == _lastTransientTurnKey) return;
    _lastTransientTurnKey = key;
    final mode = PetStateSelector.transientModeForEmotion(latest.emotionTag);
    if (mode == null) return;
    context.read<PetController>().showTransientState(mode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didWelcome) return;
    _didWelcome = true;
    // CR-0088：監聽對話，新一則情緒對話結束後讓寵物短暫顯示對應情緒狀態。
    _conversationForTransient = context.read<ConversationController>();
    _conversationForTransient!.addListener(_maybeFireTransientState);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final petController = context.read<PetController>();
      final conversationController = context.read<ConversationController>();
      final voiceAgentController = context.read<VoiceAgentController>();
      final memoryController = context.read<MemoryController>();
      final petName = context.read<ProfileController>().petName;
      if (!_didTrackAppOpen) {
        _didTrackAppOpen = true;
        _trackUsage('app_open');
      }
      await petController.enterInitialRestThenListen();
      if (!mounted) return;
      if (voiceAgentController.state != VoiceAgentState.idle &&
          voiceAgentController.state != VoiceAgentState.error) {
        return;
      }
      final greeting = await memoryController.getGreeting(
        petName: petName,
        isRealtimeActive: voiceAgentController.state != VoiceAgentState.idle,
      );
      if (greeting != null && mounted) {
        await conversationController.playGreeting(greeting);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileController = context.watch<ProfileController>();
    final petController = context.watch<PetController>();
    final conversationController = context.watch<ConversationController>();
    final voiceAgentController = context.watch<VoiceAgentController>();
    final checkInController = context.watch<CheckInController>();
    final walletController = context.watch<WalletController>();
    final inventoryController = context.watch<InventoryController>();
    final petStatsController = context.watch<PetStatsController>();
    final agentToolController = _maybeWatchAgentToolController(context);
    if (agentToolController != null) {
      // 高風險工具（撥號 / 寄信 / 傳訊息…）會把 pendingIntent 設成需確認，
      // 在這裡跳出確認 sheet，使用者按「確認執行」才真的執行（不會自動撥 / 寄）。
      _maybeShowAgentConfirmation(context, agentToolController);
    }
    final coachKeys = context.read<CoachMarkKeys>();
    final useTaigiShortRecording =
        profileController.voiceLanguageMode == VoiceLanguageMode.taigiPreferred;
    final useTaigiRealtime =
        profileController.voiceLanguageMode == VoiceLanguageMode.taigiRealtime;
    if (useTaigiShortRecording && !_didCheckTaigiAsrStatus) {
      _didCheckTaigiAsrStatus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ConversationController>().refreshTaigiAsrStatus();
      });
    } else if (!useTaigiShortRecording && _didCheckTaigiAsrStatus) {
      _didCheckTaigiAsrStatus = false;
    }
    final isDead = petStatsController.lifeState == PetLifeState.dead;
    // CR-0088：集中決定要顯示哪個寵物狀態圖（避免長時間卡在 talk / listening，
    // 讓 happy / sad / caring / hungry / rest 等狀態都有機會出現）。純函式，
    // 只消費既有訊號，不改 Realtime 主流程。
    final displayPetMode = PetStateSelector.select(
      isMicCapturing: voiceAgentController.state == VoiceAgentState.listening ||
          voiceAgentController.state == VoiceAgentState.transcribing,
      isPetSpeaking: voiceAgentController.state == VoiceAgentState.speaking ||
          petController.mode == PetMode.talking,
      transientMode: petController.transientMode,
      satiety: petStatsController.fullness,
      mood: petStatsController.moodValue,
      intimacy: petStatsController.intimacy,
    );
    final showVoiceAura = switch (voiceAgentController.state) {
      VoiceAgentState.connecting ||
      VoiceAgentState.ready ||
      VoiceAgentState.listening ||
      VoiceAgentState.transcribing ||
      VoiceAgentState.thinking =>
        true,
      _ => false,
    };
    final voiceIcon = useTaigiShortRecording
        ? conversationController.isTaigiAsrRecording
            ? Icons.stop_circle
            : Icons.mic
        : switch (voiceAgentController.state) {
            VoiceAgentState.speaking => Icons.volume_up,
            VoiceAgentState.recovering => Icons.sync,
            VoiceAgentState.listening => Icons.graphic_eq,
            _ => Icons.mic,
          };
    final voiceLabel = useTaigiShortRecording
        ? conversationController.isTaigiAsrRecording
            ? '結束台語錄音'
            : conversationController.isTaigiAsrProcessing
                ? '台語辨識中'
                : '開始台語短錄音'
        : realtimeVoiceButtonLabel(
            voiceAgentController.state,
            petName: profileController.petName,
            taigiRealtime: useTaigiRealtime,
          );
    final companionSources = _companionSourceReferences(
      voiceAgentController.currentCompanionContext?.sourceReferences,
    );
    void openPetPlay(String source) {
      if (isDead) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('寵物需要復活後才能一起玩')),
        );
        return;
      }
      _trackUsage(
        'pet_interaction',
        sessionId: conversationController.activeSessionId,
        metadata: {
          'source': source,
          'petType': petController.currentSkin.storageId,
          'mood': displayPetMode.name,
          'satiety': petStatsController.fullness,
          'intimacy': petStatsController.intimacy,
        },
      );
      Navigator.of(context).pushNamed(AppRoute.puzzle);
    }

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 690;
          return Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, compact ? 10 : 16, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HomeHeader(
                      petName: profileController.petName,
                      totalItems: inventoryController.totalQuantity,
                      coins: walletController.coins,
                      hasCheckedInToday: checkInController.hasCheckedInToday,
                      onBagTap: () => setState(() {
                        _showInventoryPanel = !_showInventoryPanel;
                        _inventoryTrayLowered = false;
                      }),
                      onOpenCalendarTap: () =>
                          _openCalendarDialog(context, checkInController),
                      onPlayTap: () => openPetPlay('more_menu'),
                      onChangeSkinTap: () => _openSkinPicker(context),
                      // 首頁「？」改為觸發 Spotlight 新手導覽（與首次進場相同）。
                      // 已在首頁，requestReplay 後 CoachMarkHost 會立即開始導覽。
                      onHelpTap: () =>
                          context.read<CoachMarkController>().requestReplay(),
                      moreButtonKey: coachKeys.moreButtonKey,
                      reminderKey: coachKeys.reminderKey,
                      // 更多功能 sheet 內仍保留 key，供未來分段導覽或測試使用。
                      dailyCheckInKey: coachKeys.dailyCheckInKey,
                      coinKey: coachKeys.coinKey,
                      onReminderTap: () =>
                          Navigator.of(context).pushNamed(AppRoute.reminders),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, contentConstraints) {
                          final detailsMaxHeight =
                              (contentConstraints.maxHeight *
                                      (compact ? 0.36 : 0.32))
                                  .clamp(86.0, compact ? 170.0 : 230.0);
                          final petText = _resolvePetText(
                            conversationController,
                            petController.message,
                          );
                          final showConversationDetail =
                              _shouldShowConversationDetail(
                            conversationController: conversationController,
                            agentToolController: agentToolController,
                            companionSources: companionSources,
                            petText: petText,
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showConversationDetail) ...[
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: detailsMaxHeight,
                                  ),
                                  child: SingleChildScrollView(
                                    key: const ValueKey(
                                      'home-conversation-detail-scroll',
                                    ),
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: _ConversationDetailPanel(
                                      conversationController:
                                          conversationController,
                                      agentToolController: agentToolController,
                                      companionSources: companionSources,
                                      petText: petText,
                                      petName: profileController.petName,
                                      compact: compact,
                                      streaming: conversationController
                                          .isRealtimeStreaming,
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 6 : 8),
                              ],
                              Expanded(
                                child: KeyedSubtree(
                                  key: coachKeys.petKey,
                                  child: _PetStage(
                                    isDead: isDead,
                                    isPetDragHovering: _isPetDragHovering,
                                    showVoiceAura: showVoiceAura,
                                    petMode: displayPetMode,
                                    skin: petController.currentSkin,
                                    onPetTap: () => openPetPlay('pet_tap'),
                                    onDragHoverChanged: (hovering) => setState(
                                      () => _isPetDragHovering = hovering,
                                    ),
                                    onAcceptItem: (item) async {
                                      setState(
                                        () => _isPetDragHovering = false,
                                      );
                                      await _applyInventoryItem(
                                        context: context,
                                        item: item,
                                        inventoryController:
                                            inventoryController,
                                        petStatsController: petStatsController,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 8),
                              KeyedSubtree(
                                key: coachKeys.statusKey,
                                child: PetStatusPanel(
                                  petName: profileController.petName,
                                  intimacy: petStatsController.intimacy,
                                  fullness: petStatsController.fullness,
                                  moodValue: petStatsController.moodValue,
                                  isDead: isDead,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    if (_showTextInput) ...[
                      TextConversationBar(
                        controller: _messageController,
                        enabled: !isDead && !conversationController.isBusy,
                        isBusy: conversationController.isBusy,
                        onChanged: conversationController.updateDraftText,
                        onSend: (text) => _sendTextMessage(
                          text,
                          conversationController,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: KeyedSubtree(
                            key: coachKeys.voiceButtonKey,
                            child: PrimaryActionButton(
                              icon: voiceIcon,
                              label: voiceLabel,
                              active: showVoiceAura,
                              onPressed: isDead
                                  ? null
                                  : () async {
                                      if (useTaigiShortRecording) {
                                        if (voiceAgentController.state !=
                                                VoiceAgentState.idle &&
                                            voiceAgentController.state !=
                                                VoiceAgentState.error) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text('請先結束目前語音對話。'),
                                            ),
                                          );
                                          return;
                                        }
                                        if (conversationController
                                            .isTaigiAsrRecording) {
                                          _trackUsage(
                                            'voice_interaction_end',
                                            sessionId: conversationController
                                                .activeSessionId,
                                            metadata: const {
                                              'mode': 'taigi_short'
                                            },
                                          );
                                          await conversationController
                                              .stopTaigiShortRecordingAndTranscribe();
                                        } else {
                                          conversationController
                                              .startNewSession();
                                          _trackUsage(
                                            'voice_interaction_start',
                                            sessionId: conversationController
                                                .activeSessionId,
                                            metadata: const {
                                              'mode': 'taigi_short'
                                            },
                                          );
                                          await conversationController
                                              .startTaigiShortRecording(
                                            realtimeBusy: voiceAgentController
                                                        .state !=
                                                    VoiceAgentState.idle &&
                                                voiceAgentController.state !=
                                                    VoiceAgentState.error,
                                          );
                                        }
                                        return;
                                      }
                                      if (conversationController
                                              .isTaigiAsrRecording ||
                                          conversationController
                                              .isTaigiAsrProcessing) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('請先完成台語短錄音。'),
                                          ),
                                        );
                                        return;
                                      }
                                      // 連續 Realtime session 的語音輪次控制：
                                      // - idle / error：開始 / 重試一段新的語音對話。
                                      // - 寵物回覆中（thinking / speaking）：按鈕＝換我先講，
                                      //   打斷寵物、把話語權交回使用者（barge-in）。
                                      // - 待命聆聽中（ready / listening）：按鈕＝結束這段語音對話。
                                      // - connecting / transcribing / recovering：連線或辨識中，
                                      //   稍候，不重複觸發避免混亂。
                                      // Turn-based「一人一句」：
                                      // - idle/error 可開始：全新對話才開 session，
                                      //   同一條連線的下一句沿用既有 session、不重連。
                                      // - 寵物回覆中（thinking/speaking）：不打斷，
                                      //   提醒使用者先聽完。
                                      // - 正在聽這一句（listening/ready）：再按一次＝結束。
                                      if (voiceAgentController
                                          .canStartVoiceInput) {
                                        if (!voiceAgentController
                                            .hasOpenRealtimeSession) {
                                          conversationController
                                              .startNewSession();
                                        }
                                        _trackUsage(
                                          'voice_interaction_start',
                                          sessionId: conversationController
                                              .activeSessionId,
                                          metadata: {
                                            'mode': useTaigiRealtime
                                                ? 'taigi_realtime'
                                                : 'realtime',
                                          },
                                        );
                                        await voiceAgentController
                                            .startRealtimeConversation();
                                      } else if (voiceAgentController
                                          .isPetResponding) {
                                        final name = profileController.petName
                                                .trim()
                                                .isEmpty
                                            ? '咕咕'
                                            : profileController.petName.trim();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text('先聽$name說完，再換你說～'),
                                          ),
                                        );
                                      } else if (voiceAgentController
                                          .isCapturingUserSpeech) {
                                        // CR-0096：聆聽 / 轉錄中按一下＝「停止收音並送出本輪語音」，
                                        // 不是取消、不斷線（吵雜環境也能手動結束說話並得到回覆）。
                                        _trackUsage(
                                          'voice_interaction_end',
                                          sessionId: conversationController
                                              .activeSessionId,
                                          metadata: {
                                            'mode': useTaigiRealtime
                                                ? 'taigi_realtime'
                                                : 'realtime',
                                          },
                                        );
                                        await voiceAgentController
                                            .stopListeningAndSubmit();
                                      }
                                    },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _KeyboardToggleButton(
                          expanded: _showTextInput,
                          enabled: !isDead,
                          onTap: () => setState(
                            () => _showTextInput = !_showTextInput,
                          ),
                        ),
                      ],
                    ),
                    if (useTaigiShortRecording &&
                        conversationController
                            .taigiAsrStatusMessage.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        conversationController.taigiAsrStatusMessage,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.56),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    // CR-0023：移除語音按鈕下方「換你說囉，按住再跟…說話」輔助提示字，
                    // 讓首頁更乾淨；按鈕本身與按鈕文字、speaking 時的 toast 不受影響。
                  ],
                ),
              ),
              if (_showInventoryPanel)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 8,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    offset: _inventoryTrayLowered
                        ? const Offset(0, 1.18)
                        : Offset.zero,
                    child: _InventoryTray(
                      items: inventoryController.items,
                      onClose: () => setState(() {
                        _showInventoryPanel = false;
                        _inventoryTrayLowered = false;
                      }),
                      onItemDragStarted: () => setState(
                        () => _inventoryTrayLowered = true,
                      ),
                      onItemDragEnded: () => setState(
                        () => _inventoryTrayLowered = false,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openCalendarDialog(
      BuildContext context, CheckInController checkInController) {
    showDialog<void>(
      context: context,
      builder: (_) => _CheckInCalendarDialog(controller: checkInController),
    );
  }

  void _openSkinPicker(BuildContext context) {
    // 帶著現有的 PetController / WalletController 進 bottom sheet，確保彈窗內也能
    // 即時切換 / 顯示「使用中」，以及未擁有外觀的購買 / 解鎖（沿用既有 wallet）。
    final petController = context.read<PetController>();
    final walletController = context.read<WalletController>();
    showModalBottomSheet<void>(
      context: context,
      // 內容可能比預設 sheet 高（三張卡片 + 完成按鈕，且字體可放大）：開啟
      // scroll 控制讓 sheet 自行決定高度，內容過高時可捲動、完成按鈕不被切掉。
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<PetController>.value(value: petController),
          ChangeNotifierProvider<WalletController>.value(
            value: walletController,
          ),
        ],
        child: const _SkinPickerSheet(),
      ),
    );
  }

  List<SourceReference> _companionSourceReferences(
    List<Map<String, dynamic>>? references,
  ) {
    if (references == null || references.isEmpty) return const [];
    return references
        .map(SourceReference.fromJson)
        .where((source) => source.title.isNotEmpty && source.url.isNotEmpty)
        .toList(growable: false);
  }

  void _trackUsage(
    String eventType, {
    String? sessionId,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) {
    try {
      unawaited(
        context.read<AppUsageTrackingService>().track(
              eventType,
              sessionId: sessionId,
              durationMs: durationMs,
              metadata: metadata,
            ),
      );
    } on ProviderNotFoundException {
      // Isolated widget tests may omit analytics. The production app injects it.
    }
  }

  Future<void> _applyInventoryItem({
    required BuildContext context,
    required InventoryItem item,
    required InventoryController inventoryController,
    required PetStatsController petStatsController,
  }) async {
    if (item.isReviveItem) {
      if (!petStatsController.isDead) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現在還不需要使用復活藥水')),
        );
        return;
      }
      final consumed = await inventoryController.consume(item.itemId);
      if (!consumed) return;
      await petStatsController.revive();
      if (!context.mounted) return;
      _showItemUsedSnackBar(context, item);
      return;
    }

    final consumed = await inventoryController.consume(item.itemId);
    if (!consumed) return;
    await petStatsController.applyShopEffects(
      intimacyDelta: item.intimacyDelta,
      fullnessDelta: item.fullnessDelta,
      moodDelta: item.moodDelta,
    );
    if (!context.mounted) return;
    context.read<PetController>().setModeAndMessage(
          PetMode.happy,
          '謝謝你餵我，我覺得有精神多了！',
        );
    _trackUsage(
      'pet_interaction',
      metadata: {
        'source': 'inventory_item',
        'itemId': item.itemId,
        'satiety': petStatsController.fullness,
        'intimacy': petStatsController.intimacy,
      },
    );
    _showItemUsedSnackBar(context, item);
  }

  Future<void> _sendTextMessage(
    String text,
    ConversationController conversationController,
  ) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    FocusScope.of(context).unfocus();
    _messageController.clear();
    conversationController.clearDraftText();
    _trackUsage(
      'typed_chat_sent',
      sessionId: conversationController.activeSessionId,
      metadata: const {'source': 'home_text_bar'},
    );
    // 若語音 Realtime 正在連線中，打字直接注入同一個 live 對話（寵物用語音回覆）；
    // 沒在語音中（回傳 false）才走原本的打字回覆路徑，兩者共用同一份對話紀錄。
    final voiceAgentController = context.read<VoiceAgentController>();
    if (await voiceAgentController.sendTextDuringRealtime(normalized)) {
      return;
    }
    await conversationController.quickAction(normalized);
  }

  void _showItemUsedSnackBar(BuildContext context, InventoryItem item) {
    final petName = context.read<ProfileController>().petName;
    final effects = <String>[
      if (item.intimacyDelta != 0) '親密 +${item.intimacyDelta}',
      if (item.fullnessDelta != 0) '飽足 +${item.fullnessDelta}',
      if (item.moodDelta != 0) '心情 +${item.moodDelta}',
      if (item.isReviveItem) '復活',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$petName 使用了 ${item.name}${effects.isEmpty ? '' : '（${effects.join('、')}）'}',
        ),
      ),
    );
  }

  AgentToolController? _maybeWatchAgentToolController(BuildContext context) {
    try {
      return context.watch<AgentToolController>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 高風險工具（撥號 / 寄信 / 傳訊息…）需要使用者明確確認才執行。
  /// 偵測到需確認的 pendingIntent 時跳出一次確認 sheet：
  /// 按「確認執行」→ confirmAndExecute；按「取消」或滑掉 → cancelIntent。
  /// 低風險工具（播音樂 / 查資訊…）不會進這裡（已自動執行）。
  void _maybeShowAgentConfirmation(
    BuildContext context,
    AgentToolController controller,
  ) {
    final intent = controller.pendingIntent;
    if (intent == null) {
      _shownConfirmIntentId = null;
      return;
    }
    if (!intent.requiresConfirmation) return;
    if (_shownConfirmIntentId == intent.id) return;
    _shownConfirmIntentId = intent.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var handled = false;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => AgentConfirmationSheet(
          intent: intent,
          onConfirm: () {
            handled = true;
            Navigator.of(sheetContext).pop();
            controller.confirmAndExecute();
          },
          onCancel: () {
            handled = true;
            Navigator.of(sheetContext).pop();
            controller.cancelIntent();
          },
        ),
      ).then((_) {
        // 使用者沒按任何鈕、直接把 sheet 滑掉 → 視為取消，清掉 pending 不卡住。
        if (!handled && controller.pendingIntent?.id == intent.id) {
          controller.cancelIntent();
        }
      });
    });
  }
}

/// 每日簽到彈窗（乾淨版）。
///
/// 月曆格子只放日期；點選某天後，下方顯示「第 X 天獎勵：金幣 N」。
/// 只負責畫面呈現，簽到 / 獎勵邏輯仍走 [CheckInController]（不改邏輯）。
class _CheckInCalendarDialog extends StatefulWidget {
  const _CheckInCalendarDialog({required this.controller});

  final CheckInController controller;

  @override
  State<_CheckInCalendarDialog> createState() => _CheckInCalendarDialogState();
}

class _CheckInCalendarDialogState extends State<_CheckInCalendarDialog> {
  final DateTime _now = DateTime.now();
  late int _selectedDay = _now.day;

  String _dayKey(int day) =>
      '${_now.year.toString().padLeft(4, '0')}-${_now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final first = DateTime(_now.year, _now.month, 1);
        final startWeekday = first.weekday;
        final daysInMonth = DateTime(_now.year, _now.month + 1, 0).day;
        final dialogWidth = MediaQuery.sizeOf(context).width * 0.9;
        final selectedReward = controller.rewardForDay(_selectedDay);

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_now.year}年${_now.month}月　每日簽到',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '點選日期可以看看那天的獎勵。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: daysInMonth + startWeekday - 1,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1, // 近正方形，避免文字互相壓住
                    ),
                    itemBuilder: (_, index) {
                      if (index < startWeekday - 1) {
                        return const SizedBox.shrink();
                      }
                      final day = index - startWeekday + 2;
                      final reward = controller.rewardForDay(day);
                      return _CalendarDayCell(
                        day: day,
                        hasGift: reward?.hasGift ?? false,
                        checked: controller.checkInDates.contains(_dayKey(day)),
                        isToday: day == _now.day,
                        isSelected: day == _selectedDay,
                        onTap: () => setState(() => _selectedDay = day),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _RewardSummary(day: _selectedDay, reward: selectedReward),
                  const SizedBox(height: 24),
                  if (!controller.hasCheckedInToday)
                    SizedBox(
                      height: 64,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                        onPressed: () => _handleCheckIn(context, controller),
                        child: const Text(
                          '今天簽到',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  else
                    const Text(
                      '今天已經簽到完成，明天再來喔！',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCheckIn(
    BuildContext context,
    CheckInController controller,
  ) async {
    final notificationService = context.read<NotificationService>();
    final ok = await controller.checkIn(
      walletController: context.read<WalletController>(),
      petStatsController: context.read<PetStatsController>(),
      inventoryController: context.read<InventoryController>(),
    );
    // CR-0031：只有簽到成功才取消今天的提醒並排下一次（通常是明天 10:00）。
    // 失敗 / 重複簽到不動通知排程，避免排錯。
    if (ok) {
      await notificationService.syncCheckInReminder(hasCheckedInToday: true);
    }
    if (!context.mounted) return;
    // 簽到後把選取日跳回今天，下方獎勵列同步顯示今天領到的內容。
    setState(() => _selectedDay = _now.day);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? _successMessage(controller.lastClaim) : '今天已經簽到過囉。',
        ),
      ),
    );
  }

  String _successMessage(CheckInClaim? claim) {
    if (claim == null) return '簽到成功！';
    final gift = claim.gift;
    if (gift != null) {
      return '簽到成功！得到 ${claim.coins} 個金幣，還有一份小禮物：${gift.emoji} ${gift.name}';
    }
    return '簽到成功！得到 ${claim.coins} 個金幣';
  }
}

/// 月曆下方的獎勵摘要列：「第 X 天獎勵：金幣 N（＋小禮物）」。
class _RewardSummary extends StatelessWidget {
  const _RewardSummary({required this.day, required this.reward});

  final int day;
  final DailyReward? reward;

  @override
  Widget build(BuildContext context) {
    final coinsText = reward != null ? '金幣 ${reward!.coins}' : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.monetization_on, color: Colors.amber.shade700, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '第 $day 天獎勵：$coinsText',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          if (reward?.hasGift ?? false) ...[
            const SizedBox(width: 8),
            const Text('🎁', style: TextStyle(fontSize: 22)),
          ],
        ],
      ),
    );
  }
}

/// 簽到日曆的單一日期格（乾淨版）：只顯示日期；禮物日右上角小 icon、
/// 已簽到淡綠底＋勾、今天橘色外框、目前選取日淡橘底。
class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.hasGift,
    required this.checked,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final int day;
  final bool hasGift;
  final bool checked;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = checked
        ? Colors.green.shade100
        : (isSelected ? Colors.orange.shade100 : Colors.grey.shade100);
    final Border border = isToday
        ? Border.all(color: Colors.orange.shade600, width: 2.5)
        : (isSelected
            ? Border.all(color: Colors.orange.shade300, width: 2)
            : Border.all(color: Colors.grey.shade200, width: 1));

    return GestureDetector(
      key: ValueKey('calendar-day-$day'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Stack(
          children: [
            // 日期置中（格子裡只有日期，保持乾淨）。
            Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: checked ? Colors.green.shade900 : Colors.black87,
                ),
              ),
            ),
            // 禮物日：右上角小 icon。
            if (hasGift)
              const Positioned(
                top: 2,
                right: 3,
                child: Text('🎁', style: TextStyle(fontSize: 11)),
              ),
            // 已簽到：右下角勾勾。
            if (checked)
              Positioned(
                bottom: 1,
                right: 2,
                child: Icon(
                  Icons.check_circle,
                  size: 13,
                  color: Colors.green.shade700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.petName,
    required this.totalItems,
    required this.coins,
    required this.hasCheckedInToday,
    required this.onBagTap,
    required this.onOpenCalendarTap,
    required this.onPlayTap,
    required this.onChangeSkinTap,
    required this.onHelpTap,
    required this.moreButtonKey,
    required this.reminderKey,
    required this.dailyCheckInKey,
    required this.coinKey,
    required this.onReminderTap,
  });

  final String petName;
  final int totalItems;
  final int coins;
  final bool hasCheckedInToday;
  final VoidCallback onBagTap;
  final VoidCallback onOpenCalendarTap;
  final VoidCallback onPlayTap;
  final VoidCallback onChangeSkinTap;
  final VoidCallback onHelpTap;
  final Key moreButtonKey;
  final Key reminderKey;
  final Key dailyCheckInKey;
  final Key coinKey;
  final VoidCallback onReminderTap;

  void _openQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _HomeQuickActionsSheet(
        petName: petName,
        totalItems: totalItems,
        coins: coins,
        hasCheckedInToday: hasCheckedInToday,
        reminderKey: reminderKey,
        dailyCheckInKey: dailyCheckInKey,
        coinKey: coinKey,
        onReminderTap: () {
          Navigator.of(sheetContext).pop();
          Future<void>.delayed(Duration.zero, onReminderTap);
        },
        onBagTap: () {
          Navigator.of(sheetContext).pop();
          Future<void>.delayed(Duration.zero, onBagTap);
        },
        onPlayTap: () {
          Navigator.of(sheetContext).pop();
          Future<void>.delayed(Duration.zero, onPlayTap);
        },
        onChangeSkinTap: () {
          Navigator.of(sheetContext).pop();
          Future<void>.delayed(Duration.zero, onChangeSkinTap);
        },
        onOpenCalendarTap: () {
          Navigator.of(sheetContext).pop();
          Future<void>.delayed(Duration.zero, onOpenCalendarTap);
        },
        onHelpTap: () {
          Navigator.of(sheetContext).pop();
          Future<void>.delayed(Duration.zero, onHelpTap);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 頂部列只保留寵物名稱與一個次要入口，讓首頁重心回到寵物和語音。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  petName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          KeyedSubtree(
            key: moreButtonKey,
            child: Tooltip(
              message: '更多功能',
              child: Semantics(
                button: true,
                label: '更多功能',
                child: IconButton.filledTonal(
                  onPressed: () => _openQuickActions(context),
                  icon: const Icon(Icons.more_horiz),
                  iconSize: 30,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(56, 56),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeQuickActionsSheet extends StatelessWidget {
  const _HomeQuickActionsSheet({
    required this.petName,
    required this.totalItems,
    required this.coins,
    required this.hasCheckedInToday,
    required this.reminderKey,
    required this.dailyCheckInKey,
    required this.coinKey,
    required this.onReminderTap,
    required this.onBagTap,
    required this.onPlayTap,
    required this.onChangeSkinTap,
    required this.onOpenCalendarTap,
    required this.onHelpTap,
  });

  final String petName;
  final int totalItems;
  final int coins;
  final bool hasCheckedInToday;
  final Key reminderKey;
  final Key dailyCheckInKey;
  final Key coinKey;
  final VoidCallback onReminderTap;
  final VoidCallback onBagTap;
  final VoidCallback onPlayTap;
  final VoidCallback onChangeSkinTap;
  final VoidCallback onOpenCalendarTap;
  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '還想幫$petName做什麼？',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '平常只要按麥克風跟寵物說話，其他功能都先放在這裡。',
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              const _HomeQuickActionSectionTitle('常用功能'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: dailyCheckInKey,
                      child: _HomeQuickActionTile(
                        icon: Icons.calendar_month,
                        title: '每日簽到',
                        subtitle: hasCheckedInToday ? '今天已完成' : '今天可領獎勵',
                        onTap: onOpenCalendarTap,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KeyedSubtree(
                      key: reminderKey,
                      child: _HomeQuickActionTile(
                        icon: Icons.alarm,
                        title: '提醒',
                        subtitle: '喝水、吃藥、回診',
                        onTap: onReminderTap,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _HomeQuickActionSectionTitle('照顧寵物'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _HomeQuickActionTile(
                      icon: Icons.extension_outlined,
                      title: '陪寵物玩',
                      subtitle: '玩拼圖動動腦',
                      onTap: onPlayTap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HomeQuickActionTile(
                      icon: Icons.pets,
                      title: '更換外觀',
                      subtitle: '選喜歡的樣子',
                      onTap: onChangeSkinTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _HomeQuickActionSectionTitle('其他'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _HomeQuickActionTile(
                      icon: Icons.inventory_2_outlined,
                      title: '背包',
                      subtitle: totalItems > 0 ? '$totalItems 件物品' : '寵物的小物品',
                      onTap: onBagTap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HomeQuickActionTile(
                      icon: Icons.help_outline,
                      title: '使用教學',
                      subtitle: '再看一次導覽',
                      onTap: onHelpTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              KeyedSubtree(
                key: coinKey,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '目前金幣',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      CoinBadge(coins: coins),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeQuickActionSectionTitle extends StatelessWidget {
  const _HomeQuickActionSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: Colors.black.withValues(alpha: 0.62),
      ),
    );
  }
}

class _HomeQuickActionTile extends StatelessWidget {
  const _HomeQuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 118),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _shouldShowConversationDetail({
  required ConversationController conversationController,
  required AgentToolController? agentToolController,
  required List<SourceReference> companionSources,
  required String petText,
}) {
  final hasVisibleConversationText =
      conversationController.latestUserText.trim().isNotEmpty ||
          conversationController.temporaryUserBubbleText.trim().isNotEmpty ||
          conversationController.liveRealtimeReply.trim().isNotEmpty ||
          conversationController.latestReply.trim().isNotEmpty;
  return hasVisibleConversationText ||
      conversationController.hasTemporaryUserBubble ||
      conversationController.isAwaitingPetReply ||
      conversationController.hasPendingTaigiAsrTranscript ||
      conversationController.latestSources.isNotEmpty ||
      companionSources.isNotEmpty ||
      agentToolController?.pendingIntent != null ||
      petText.trim().isNotEmpty && petText.trim() != '準備好開始今天的陪伴了嗎？';
}

String _resolvePetText(
  ConversationController conversation,
  String petControllerMessage,
) {
  // CR-0084：寵物說話中時，優先顯示「即時逐字字幕」，讓字幕跟著聲音走。
  // （此時 latestReply 尚未落地、且使用者氣泡可能還在，故須最先判斷。）
  if (conversation.liveRealtimeReply.trim().isNotEmpty) {
    return conversation.liveRealtimeReply;
  }
  if (conversation.latestReply.trim().isNotEmpty) {
    return conversation.latestReply;
  }
  final userActive = conversation.latestUserText.trim().isNotEmpty ||
      conversation.temporaryUserBubbleText.trim().isNotEmpty ||
      conversation.hasTemporaryUserBubble;
  if (userActive) return '';
  return petControllerMessage;
}

class _ConversationDetailPanel extends StatelessWidget {
  const _ConversationDetailPanel({
    required this.conversationController,
    required this.agentToolController,
    required this.companionSources,
    required this.petText,
    required this.petName,
    required this.compact,
    this.streaming = false,
  });

  final ConversationController conversationController;
  final AgentToolController? agentToolController;
  final List<SourceReference> companionSources;
  final String petText;
  final String petName;
  final bool compact;

  /// CR-0084：寵物字幕是否為「即時逐字串流中」（跟著語音走）。
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConversationBubbleStack(
          userText: conversationController.latestUserText,
          temporaryUserText: conversationController.temporaryUserBubbleText,
          temporaryUserStatus: conversationController.temporaryUserBubbleStatus,
          petText: petText,
          petName: petName,
          isWaiting: conversationController.isAwaitingPetReply,
          compact: compact,
          streaming: streaming,
        ),
        if (conversationController.latestLanguageContextLabel.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _LanguageContextChip(
              label: conversationController.latestLanguageContextLabel,
            ),
          ),
        ],
        if (conversationController.hasPendingTaigiAsrTranscript) ...[
          const SizedBox(height: 8),
          _TaigiAsrConfirmationCard(
            transcript: conversationController.pendingTaigiAsrTranscript,
            isBusy: conversationController.isBusy,
            onSend: conversationController.confirmPendingTaigiAsrTranscript,
            onRetry: conversationController.clearPendingTaigiAsrTranscript,
          ),
        ],
        if (conversationController.latestReplyIsSearch) ...[
          if (conversationController.latestSources.isNotEmpty) ...[
            const SizedBox(height: 8),
            SourceReferenceList(
              sources: conversationController.latestSources,
            ),
          ],
        ],
        if (!conversationController.latestReplyIsSearch &&
            companionSources.isNotEmpty) ...[
          const SizedBox(height: 8),
          SourceReferenceList(sources: companionSources),
        ],
      ],
    );
  }
}

class _TaigiAsrConfirmationCard extends StatelessWidget {
  const _TaigiAsrConfirmationCard({
    required this.transcript,
    required this.isBusy,
    required this.onSend,
    required this.onRetry,
  });

  final String transcript;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D8B8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '我聽到的是：',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.6),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '「$transcript」',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy ? null : onRetry,
                    child: const Text('重新錄音'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: isBusy ? null : onSend,
                    child: const Text('送出'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageContextChip extends StatelessWidget {
  const _LanguageContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.56),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _KeyboardToggleButton extends StatelessWidget {
  const _KeyboardToggleButton({
    required this.expanded,
    required this.enabled,
    required this.onTap,
  });

  final bool expanded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final label = expanded ? '收起' : '打字';
    return Semantics(
      button: true,
      label: expanded ? '收起打字' : '打字',
      child: Tooltip(
        message: expanded ? '收起打字' : '打字',
        child: Material(
          color: enabled
              ? primary.withValues(alpha: expanded ? 0.18 : 0.10)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(29),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 88,
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    expanded ? Icons.keyboard_hide : Icons.keyboard,
                    color: enabled
                        ? primary
                        : Colors.black.withValues(alpha: 0.28),
                    size: 25,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? primary
                            : colorScheme.onSurface.withValues(alpha: 0.32),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PetStage extends StatelessWidget {
  const _PetStage({
    required this.isDead,
    required this.isPetDragHovering,
    required this.showVoiceAura,
    required this.petMode,
    required this.skin,
    required this.onPetTap,
    required this.onDragHoverChanged,
    required this.onAcceptItem,
  });

  final bool isDead;
  final bool isPetDragHovering;
  final bool showVoiceAura;
  final PetMode petMode;
  final PetSkin skin;
  final VoidCallback onPetTap;
  final ValueChanged<bool> onDragHoverChanged;
  final ValueChanged<InventoryItem> onAcceptItem;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, petConstraints) {
        final maxAvailable = petConstraints.biggest.shortestSide;
        if (maxAvailable <= 0) return const SizedBox.shrink();
        // CR-0011：寵物放大、減少留白。素材本身四周留白較多，直接吃滿可用的
        // 最短邊（上限放寬到 520），讓寵物主體看起來更大；clamp 同時確保小螢幕
        // 不會超出可用空間造成 overflow。
        final maxAvatarSize = maxAvailable.clamp(0.0, 520.0);
        final avatarSize = maxAvailable < 72
            ? maxAvailable
            : maxAvailable.clamp(72.0, maxAvatarSize);
        final auraSize = maxAvailable.clamp(0.0, avatarSize + 54);

        return Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: DragTarget<InventoryItem>(
                  onWillAcceptWithDetails: (_) {
                    onDragHoverChanged(true);
                    return true;
                  },
                  onLeave: (_) => onDragHoverChanged(false),
                  onAcceptWithDetails: (details) => onAcceptItem(details.data),
                  builder: (_, __, ___) => GestureDetector(
                    onTap: onPetTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: petConstraints.maxWidth,
                      height: petConstraints.maxHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: isPetDragHovering
                            ? Border.all(
                                color: Colors.green,
                                width: 3,
                              )
                            : null,
                      ),
                      child: ColorFiltered(
                        colorFilter: isDead
                            ? const ColorFilter.mode(
                                Colors.grey,
                                BlendMode.saturation,
                              )
                            : const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.srcOver,
                              ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (showVoiceAura)
                              _VoiceListeningBubbles(
                                size: auraSize,
                              ),
                            PetAvatar(
                              mode: petMode,
                              skin: skin,
                              size: avatarSize,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 首頁「更換外觀」彈出視窗內容（標題 + 外觀選擇器 + 完成）。
class _SkinPickerSheet extends StatelessWidget {
  const _SkinPickerSheet();

  @override
  Widget build(BuildContext context) {
    // sheet 最高約佔螢幕 88%：內容夠短就貼合內容、過高則由中段列表捲動，
    // 標題與底部「完成」按鈕固定不被捲走。
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題區（固定）。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '想換一隻夥伴嗎？',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '選好就會馬上換成牠陪你。',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 卡片列表（可捲動）：內容過高時在這裡捲，不會把完成按鈕擠出畫面。
          const Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: PetSkinPicker(compact: true),
            ),
          ),
          // 完成按鈕（固定在底部，並避開 home indicator）。
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceListeningBubbles extends StatefulWidget {
  const _VoiceListeningBubbles({
    required this.size,
  });

  final double size;

  @override
  State<_VoiceListeningBubbles> createState() => _VoiceListeningBubblesState();
}

class _VoiceListeningBubblesState extends State<_VoiceListeningBubbles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  _PulseRing(
                    progress: (_controller.value + i * 0.24) % 1,
                    color: Colors.indigo,
                    size: widget.size,
                  ),
                Positioned(
                  bottom: (widget.size * 0.08).clamp(2.0, 10.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 5; i++)
                        _AudioDot(
                          height: 10 +
                              (((_controller.value * 2 + i * 0.28) % 1) * 18),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.progress,
    required this.color,
    required this.size,
  });

  final double progress;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ringSize = size * (0.86 + progress * 0.34);
    final opacity = (1 - progress).clamp(0.0, 1.0) * 0.22;
    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 4,
        ),
      ),
    );
  }
}

class _AudioDot extends StatelessWidget {
  const _AudioDot({
    required this.height,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _InventoryTray extends StatelessWidget {
  const _InventoryTray({
    required this.items,
    required this.onClose,
    required this.onItemDragStarted,
    required this.onItemDragEnded,
  });

  final List<InventoryItem> items;
  final VoidCallback onClose;
  final VoidCallback onItemDragStarted;
  final VoidCallback onItemDragEnded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9D8A6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '背包',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '收起背包',
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('背包現在是空的'),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in items)
                  InventoryItemCard(
                    item: item,
                    draggable: true,
                    onDragStarted: onItemDragStarted,
                    onDragEnded: onItemDragEnded,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
