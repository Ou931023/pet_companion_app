import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/memory_controller.dart';
import '../widgets/memory_card.dart';

class MemoryManagementScreen extends StatefulWidget {
  const MemoryManagementScreen({super.key});

  @override
  State<MemoryManagementScreen> createState() => _MemoryManagementScreenState();
}

class _MemoryManagementScreenState extends State<MemoryManagementScreen> {
  final Set<String> _forgettingIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MemoryController>().loadMemories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final memoryController = context.watch<MemoryController>();
    final memories = memoryController.memories;

    return Scaffold(
      appBar: AppBar(title: const Text('長期記憶')),
      body: RefreshIndicator(
        onRefresh: memoryController.loadMemories,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _PrivacyNote(),
            const SizedBox(height: 14),
            if (memoryController.memoryErrorMessage.isNotEmpty)
              _ErrorBanner(message: memoryController.memoryErrorMessage),
            if (memoryController.isLoadingMemories)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (memories.isEmpty)
              const _EmptyState()
            else
              for (final memory in memories)
                MemoryCard(
                  memory: memory,
                  isForgetting:
                      _forgettingIds.contains(memory['id'].toString()),
                  onForget: () => _forgetMemory(memory),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _forgetMemory(Map<String, dynamic> memory) async {
    final id = memory['id'];
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('忘記這筆記憶？'),
        content: const Text('寵物之後就不會再主動使用這筆記憶。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先不要'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('忘記'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _forgettingIds.add(id.toString()));
    final ok = await context.read<MemoryController>().archiveMemory(id);
    if (!mounted) return;
    setState(() => _forgettingIds.remove(id.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已忘記這筆記憶' : '暫時無法忘記這筆記憶')),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: const Text(
        '長期記憶會保存你在對話中明確提到、且有助於陪伴的內容，例如興趣、生活習慣或提醒事項。你可以隨時讓寵物忘記某筆記憶。',
        style: TextStyle(fontSize: 16, height: 1.4),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Text(
        '目前還沒有長期記憶，和寵物多聊聊後，牠會慢慢更了解你。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, height: 1.4),
      ),
    );
  }
}
