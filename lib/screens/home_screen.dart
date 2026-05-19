import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/check_in_controller.dart';
import '../controllers/conversation_controller.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/memory_controller.dart';
import '../controllers/pet_controller.dart';
import '../controllers/pet_stats_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/voice_agent_controller.dart';
import '../controllers/wallet_controller.dart';
import '../models/inventory_item.dart';
import '../models/pet_status.dart';
import '../models/pet_stats.dart';
import '../models/source_reference.dart';
import '../models/voice_agent_state.dart';
import '../routes/app_routes.dart';
import '../widgets/bag_icon_button.dart';
import '../widgets/coin_badge.dart';
import '../widgets/conversation_bubble_stack.dart';
import '../widgets/home_date_checkin_card.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/pet_avatar.dart';
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
    final voiceIcon = switch (voiceAgentController.state) {
      VoiceAgentState.speaking => Icons.volume_up,
      VoiceAgentState.recovering => Icons.sync,
      VoiceAgentState.listening => Icons.graphic_eq,
      _ => Icons.mic,
    };
    final voiceLabel = switch (voiceAgentController.state) {
      VoiceAgentState.connecting => '正在連線陪伴寵物',
      VoiceAgentState.ready || VoiceAgentState.listening => '可以開始說話',
      VoiceAgentState.recovering => '重新連線中',
      VoiceAgentState.error => '連線失敗，點我重試',
      VoiceAgentState.transcribing => '正在聽你說話',
      VoiceAgentState.thinking => '正在想回應',
      VoiceAgentState.speaking => '正在陪你說話',
      VoiceAgentState.idle => '開始語音陪伴',
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
                                    companionSources: companionSources,
                                    petText: conversationController
                                            .latestReply.isNotEmpty
                                        ? conversationController.latestReply
                                        : petController.message,
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
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.petName,
    required this.totalItems,
    required this.coins,
    required this.hasCheckedInToday,
    required this.onBagTap,
    required this.onOpenCalendarTap,
  });

  final String petName;
  final int totalItems;
  final int coins;
  final bool hasCheckedInToday;
  final VoidCallback onBagTap;
  final VoidCallback onOpenCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            petName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
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
    );
  }
}

class _ConversationDetailPanel extends StatelessWidget {
  const _ConversationDetailPanel({
    required this.conversationController,
    required this.companionSources,
    required this.petText,
    required this.petName,
    required this.compact,
  });

  final ConversationController conversationController;
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

class _PetStage extends StatelessWidget {
  const _PetStage({
    required this.isDead,
    required this.isPetDragHovering,
    required this.showVoiceAura,
    required this.petMode,
    required this.onPetTap,
    required this.onDragHoverChanged,
    required this.onAcceptItem,
  });

  final bool isDead;
  final bool isPetDragHovering;
  final bool showVoiceAura;
  final PetMode petMode;
  final VoidCallback onPetTap;
  final ValueChanged<bool> onDragHoverChanged;
  final ValueChanged<InventoryItem> onAcceptItem;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, petConstraints) {
        final maxAvailable = petConstraints.biggest.shortestSide;
        if (maxAvailable <= 0) return const SizedBox.shrink();
        final maxAvatarSize = maxAvailable.clamp(0.0, 430.0);
        final avatarSize = maxAvailable < 72
            ? maxAvailable
            : (maxAvailable * 0.92).clamp(72.0, maxAvatarSize);
        final auraSize = maxAvailable.clamp(0.0, avatarSize + 54);

        return Center(
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
                        size: avatarSize,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
