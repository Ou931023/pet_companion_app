import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../models/conversation_session_summary.dart';
import '../routes/app_routes.dart';
import '../utils/conversation_history_display.dart';
import '../widgets/conversation_session_tile.dart';
import '../widgets/ui/empty_state.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // CR-0091：對話搜尋（本地、即時過濾）。
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // 進到對話紀錄頁時，為還沒有標題的對話補上 ChatGPT 風格的簡短標題。
    // fire-and-forget：失敗就維持本地 fallback 標題，不卡畫面。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ConversationController>().ensureSessionTitles();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConversationController>();
    final sessions = controller.sessionSummaries;
    final filtered = filterConversationSessions(
      sessions: sessions,
      allTurns: controller.history,
      query: _query,
    );
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const Text('對話紀錄',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '這裡會留著你和寵物聊過的話。長按一則可以刪掉那則紀錄。',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // 沒有任何紀錄：只顯示空狀態，不顯示搜尋框。
          if (sessions.isEmpty)
            const EmptyState(
              icon: Icons.chat_bubble_outline,
              message: '還沒有對話紀錄',
              hint: '之後和寵物聊天，內容會出現在這裡。',
            )
          else ...[
            _buildSearchBar(),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              const EmptyState(
                icon: Icons.search_off,
                message: '找不到相關對話',
                hint: '換個關鍵字試試看。',
              )
            else
              for (final s in filtered)
                ConversationSessionTile(
                  summary: s,
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      AppRoute.conversationDetail,
                      arguments: ConversationDetailArgs(
                        sessionId: s.sessionId,
                        title: s.title,
                      ),
                    );
                  },
                  onLongPress: () => _confirmDeleteSession(context, s),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      style: const TextStyle(fontSize: 18),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜尋和寵物聊過的內容',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: '清除搜尋',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// 長按某一則對話卡片 → 確認後只刪除「該則」紀錄；不影響長期記憶。
  Future<void> _confirmDeleteSession(
    BuildContext context,
    ConversationSessionSummary summary,
  ) async {
    final controller = context.read<ConversationController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '刪除這則對話？',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '刪除後，這則對話紀錄會從列表中移除，但不會影響寵物記得你的事。',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '刪除',
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
    final ok = await controller.deleteConversationSession(summary.sessionId);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('沒辦法刪除這則，請再試一次。')),
    );
  }
}
