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
import '../models/voice_agent_state.dart';
import '../routes/app_routes.dart';
import '../widgets/bag_icon_button.dart';
import '../widgets/coin_badge.dart';
import '../widgets/home_date_checkin_card.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/pet_status_panel.dart';
import '../widgets/source_reference_list.dart';
import '../widgets/speech_bubble.dart';

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
      VoiceAgentState.connected ||
      VoiceAgentState.listening ||
      VoiceAgentState.thinking =>
        true,
      _ => false,
    };
    final voiceIcon = switch (voiceAgentController.state) {
      VoiceAgentState.speaking => Icons.volume_up,
      VoiceAgentState.listening => Icons.graphic_eq,
      _ => Icons.mic,
    };

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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profileController.petName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        BagIconButton(
                          totalItems: inventoryController.totalQuantity,
                          onTap: () => setState(() {
                            _showInventoryPanel = !_showInventoryPanel;
                            _inventoryTrayLowered = false;
                          }),
                        ),
                        const SizedBox(width: 8),
                        CoinBadge(coins: walletController.coins),
                        const SizedBox(width: 8),
                        HomeDateCheckinCard(
                          hasCheckedInToday:
                              checkInController.hasCheckedInToday,
                          onOpenCalendarTap: () =>
                              _openCalendarDialog(context, checkInController),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    if (conversationController.latestUserText
                        .trim()
                        .isNotEmpty) ...[
                      _UserMessageBubble(
                        text: conversationController.latestUserText,
                      ),
                      SizedBox(height: compact ? 6 : 8),
                    ],
                    SpeechBubble(text: petController.message),
                    if (conversationController.latestReplyIsSearch) ...[
                      const SizedBox(height: 8),
                      _SearchMetaLine(
                        mode: conversationController.latestSearchMode,
                        provider: conversationController.latestSearchProvider,
                        toolUsed: conversationController.latestToolUsed,
                      ),
                      if (conversationController.latestSources.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SourceReferenceList(
                          sources: conversationController.latestSources,
                        ),
                      ],
                    ],
                    SizedBox(height: compact ? 8 : 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, petConstraints) {
                          final avatarSize =
                              (petConstraints.biggest.shortestSide *
                                      (compact ? 0.96 : 1.0))
                                  .clamp(188.0, 430.0);
                          final auraSize =
                              (avatarSize - 54).clamp(150.0, avatarSize);

                          return Center(
                            child: DragTarget<InventoryItem>(
                              onWillAcceptWithDetails: (_) {
                                setState(() => _isPetDragHovering = true);
                                return true;
                              },
                              onLeave: (_) =>
                                  setState(() => _isPetDragHovering = false),
                              onAcceptWithDetails: (details) async {
                                setState(() => _isPetDragHovering = false);
                                await _applyInventoryItem(
                                  context: context,
                                  item: details.data,
                                  inventoryController: inventoryController,
                                  petStatsController: petStatsController,
                                );
                              },
                              builder: (_, __, ___) => GestureDetector(
                                onTap: () {
                                  if (isDead) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('寵物需要復活後才能一起玩'),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.of(context)
                                      .pushNamed(AppRoute.puzzle);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: petConstraints.maxWidth,
                                  height: petConstraints.maxHeight,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: _isPetDragHovering
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
                                      clipBehavior: Clip.none,
                                      children: [
                                        if (showVoiceAura)
                                          _VoiceListeningBubbles(
                                            size: auraSize,
                                          ),
                                        PetAvatar(
                                          mode: petController.mode,
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
                      ),
                    ),
                    PetStatusPanel(
                      intimacy: petStatsController.intimacy,
                      fullness: petStatsController.fullness,
                      moodValue: petStatsController.moodValue,
                      isDead: isDead,
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    _TextConversationBar(
                      controller: _messageController,
                      enabled: !isDead && !conversationController.isBusy,
                      isBusy: conversationController.isBusy,
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
                        child: Icon(voiceIcon, size: 30),
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

class _TextConversationBar extends StatelessWidget {
  const _TextConversationBar({
    required this.controller,
    required this.enabled,
    required this.isBusy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isBusy;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: '跟寵物說一句話',
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: enabled ? onSend : null,
            ),
          ),
          IconButton.filled(
            tooltip: '送出',
            onPressed: enabled ? () => onSend(controller.text) : null,
            icon: isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _SearchMetaLine extends StatelessWidget {
  const _SearchMetaLine({
    required this.mode,
    required this.provider,
    required this.toolUsed,
  });

  final String mode;
  final String provider;
  final String toolUsed;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (mode.isNotEmpty) 'mode: $mode',
      if (provider.isNotEmpty) 'provider: $provider',
      if (toolUsed.isNotEmpty) 'toolUsed: $toolUsed',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('  |  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.48),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.indigo,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 7,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.person_outline,
                color: Colors.white,
                size: 19,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
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
        width: widget.size + 54,
        height: widget.size + 54,
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
                  bottom: 10,
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
