import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../models/inventory_item.dart';
import '../models/language_route.dart';
import '../models/pet_skin.dart';
import '../models/pet_status.dart';
import '../models/pet_stats.dart';
import '../models/source_reference.dart';
import '../models/voice_agent_state.dart';
import '../routes/app_routes.dart';
import '../widgets/bag_icon_button.dart';
import '../widgets/coin_badge.dart';
import '../widgets/conversation_bubble_stack.dart';
import '../widgets/feature_tour.dart';
import '../widgets/home_date_checkin_card.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/pet_skin_picker.dart';
import '../widgets/pet_status_panel.dart';
import '../widgets/source_reference_list.dart';
import '../widgets/text_conversation_bar.dart';

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

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didWelcome) return;
    _didWelcome = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final petController = context.read<PetController>();
      final conversationController = context.read<ConversationController>();
      final voiceAgentController = context.read<VoiceAgentController>();
      final memoryController = context.read<MemoryController>();
      final petName = context.read<ProfileController>().petName;
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
        : switch (voiceAgentController.state) {
            VoiceAgentState.connecting => '正在連線，馬上就好',
            VoiceAgentState.ready ||
            VoiceAgentState.listening =>
              '我在聽，你說',
            VoiceAgentState.recovering => '正在重新連線',
            VoiceAgentState.error => '連線怪怪的，點我再試一次',
            VoiceAgentState.transcribing => '正在聽你說',
            VoiceAgentState.thinking => '正在想怎麼回你',
            VoiceAgentState.speaking => '正在跟你說話',
            VoiceAgentState.idle =>
              useTaigiRealtime ? '用台語跟我聊聊' : '想聊天就點我',
          };
    final companionSources = _companionSourceReferences(
      voiceAgentController.currentCompanionContext?.sourceReferences,
    );

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
                      onHelpTap: () => showFeatureTour(context),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, contentConstraints) {
                          final detailsMaxHeight =
                              (contentConstraints.maxHeight *
                                      (compact ? 0.36 : 0.32))
                                  .clamp(86.0, compact ? 170.0 : 230.0);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                    petText: _resolvePetText(
                                      conversationController,
                                      petController.message,
                                    ),
                                    petName: profileController.petName,
                                    compact: compact,
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 8),
                              Expanded(
                                child: _PetStage(
                                  isDead: isDead,
                                  isPetDragHovering: _isPetDragHovering,
                                  showVoiceAura: showVoiceAura,
                                  petMode: petController.mode,
                                  skin: petController.currentSkin,
                                  onChangeSkin: () => _openSkinPicker(context),
                                  onPetTap: () {
                                    if (isDead) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('寵物需要復活後才能一起玩'),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.of(context)
                                        .pushNamed(AppRoute.puzzle);
                                  },
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
                                      inventoryController: inventoryController,
                                      petStatsController: petStatsController,
                                    );
                                  },
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 8),
                              PetStatusPanel(
                                intimacy: petStatsController.intimacy,
                                fullness: petStatsController.fullness,
                                moodValue: petStatsController.moodValue,
                                isDead: isDead,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 10),
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
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: isDead
                            ? null
                            : () async {
                                if (useTaigiShortRecording) {
                                  if (voiceAgentController.state !=
                                          VoiceAgentState.idle &&
                                      voiceAgentController.state !=
                                          VoiceAgentState.error) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('請先結束目前語音對話。'),
                                      ),
                                    );
                                    return;
                                  }
                                  if (conversationController
                                      .isTaigiAsrRecording) {
                                    await conversationController
                                        .stopTaigiShortRecordingAndTranscribe();
                                  } else {
                                    conversationController.startNewSession();
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('請先完成台語短錄音。'),
                                    ),
                                  );
                                  return;
                                }
                                if (voiceAgentController.state ==
                                        VoiceAgentState.idle ||
                                    voiceAgentController.state ==
                                        VoiceAgentState.error) {
                                  conversationController.startNewSession();
                                  await voiceAgentController
                                      .startRealtimeConversation();
                                } else {
                                  await voiceAgentController
                                      .stopRealtimeConversation();
                                }
                              },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(voiceIcon, size: 26),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                voiceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    if (useTaigiRealtime) ...[
                      const SizedBox(height: 6),
                      Text(
                        '台語 Realtime 對話，可以直接用台語跟寵物說話',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.56),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final startWeekday = first.weekday;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${now.year}年${now.month}月簽到'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 320,
              height: 320,
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: daysInMonth + startWeekday - 1,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7),
                itemBuilder: (_, index) {
                  if (index < startWeekday - 1) return const SizedBox.shrink();
                  final day = index - startWeekday + 2;
                  final key =
                      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                  final checked = checkInController.checkInDates.contains(key);
                  return Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: checked
                          ? Colors.green.shade200
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text('$day'),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (!checkInController.hasCheckedInToday)
              FilledButton(
                onPressed: () async {
                  final ok = await checkInController.checkIn(
                    walletController: context.read<WalletController>(),
                    petStatsController: context.read<PetStatsController>(),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '簽到成功，獲得 10 金幣' : '今天已簽到')),
                  );
                  Navigator.pop(context);
                },
                child: const Text('今日簽到'),
              )
            else
              const Text('今日已簽到',
                  style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  void _openSkinPicker(BuildContext context) {
    // 帶著現有的 PetController 進 bottom sheet，確保彈窗內也能即時切換 / 顯示「使用中」。
    final petController = context.read<PetController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider<PetController>.value(
        value: petController,
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
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.petName,
    required this.totalItems,
    required this.coins,
    required this.hasCheckedInToday,
    required this.onBagTap,
    required this.onOpenCalendarTap,
    required this.onHelpTap,
  });

  final String petName;
  final int totalItems;
  final int coins;
  final bool hasCheckedInToday;
  final VoidCallback onBagTap;
  final VoidCallback onOpenCalendarTap;
  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    // CR-0010：頂部列為次要 chrome（名稱 + 工具按鈕）。多了「？」說明鈕後，
    // 在極小寬度 + 大字級下會擠不下，因此把這一列的文字放大上限夾住，讓按鈕排得下；
    // 主要內容（寵物 / 對話）仍維持完整字級，不影響長者閱讀。
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
              const SizedBox(height: 2),
              Text(
                '今天想跟$petName聊聊嗎？我都在這裡陪你',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        _HelpIconButton(onTap: onHelpTap),
        const SizedBox(width: 6),
        BagIconButton(
          totalItems: totalItems,
          onTap: onBagTap,
        ),
        const SizedBox(width: 8),
        CoinBadge(coins: coins),
        const SizedBox(width: 8),
        HomeDateCheckinCard(
          hasCheckedInToday: hasCheckedInToday,
          onOpenCalendarTap: onOpenCalendarTap,
        ),
      ],
      ),
    );
  }
}

/// 首頁「？」功能說明按鈕（放在背包旁；長者忘記怎麼用可隨時再看一次）。
class _HelpIconButton extends StatelessWidget {
  const _HelpIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '功能說明',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1.5,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            child: Icon(
              Icons.help_outline,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

String _resolvePetText(
  ConversationController conversation,
  String petControllerMessage,
) {
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
  });

  final ConversationController conversationController;
  final AgentToolController? agentToolController;
  final List<SourceReference> companionSources;
  final String petText;
  final String petName;
  final bool compact;

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

class _PetStage extends StatelessWidget {
  const _PetStage({
    required this.isDead,
    required this.isPetDragHovering,
    required this.showVoiceAura,
    required this.petMode,
    required this.skin,
    required this.onChangeSkin,
    required this.onPetTap,
    required this.onDragHoverChanged,
    required this.onAcceptItem,
  });

  final bool isDead;
  final bool isPetDragHovering;
  final bool showVoiceAura;
  final PetMode petMode;
  final PetSkin skin;
  final VoidCallback onChangeSkin;
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
            Positioned(
              top: 0,
              right: 0,
              child: _ChangeSkinButton(onTap: onChangeSkin),
            ),
          ],
        );
      },
    );
  }
}

/// 首頁右上角「更換外觀」入口（疊在寵物舞台角落，不擋住寵物主體）。
class _ChangeSkinButton extends StatelessWidget {
  const _ChangeSkinButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '更換外觀',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        elevation: 1.5,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pets,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  '更換外觀',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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

/// 首頁「更換外觀」彈出視窗內容（標題 + 外觀選擇器 + 完成）。
class _SkinPickerSheet extends StatelessWidget {
  const _SkinPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
            const SizedBox(height: 16),
            const PetSkinPicker(),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
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
