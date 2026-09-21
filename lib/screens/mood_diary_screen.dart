import 'package:flutter/material.dart';

import '../models/mood_diary_entry.dart';
import '../services/mood_diary_service.dart';

class MoodDiaryScreen extends StatefulWidget {
  const MoodDiaryScreen({super.key, required this.createService});
  final MoodDiaryService Function() createService;

  @override
  State<MoodDiaryScreen> createState() => _MoodDiaryScreenState();
}

class _MoodDiaryScreenState extends State<MoodDiaryScreen> {
  late final MoodDiaryService _service = widget.createService();
  final _text = TextEditingController();
  List<MoodDiaryEntry> _entries = [];
  String _mood = 'okay';
  String? _error;
  bool _share = false;
  bool _loading = true;
  bool _busy = false;
  bool _uncertainSave = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _uncertainSave = false;
      });
    } on MoodDiaryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _uncertainSave || _text.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.create(
          mood: _mood, content: _text.text, sharedWithCaregiver: _share);
      if (!mounted) return;
      _text.clear();
      setState(() => _share = false);
      await _load();
    } on MoodDiaryException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _uncertainSave = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(MoodDiaryEntry entry, {required bool delete}) async {
    if (_busy) return;
    final sharing = !entry.sharedWithCaregiver;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(delete
                  ? '刪除這篇日記？'
                  : sharing
                      ? '分享這篇日記？'
                      : '停止分享？'),
              content: Text(delete
                  ? '刪除後就無法找回。'
                  : sharing
                      ? '你授權的照護人員與管理員將能看到這篇日記。'
                      : '照護後台之後將不再提供這篇日記。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('確定')),
              ],
            ));
    if (!mounted || confirmed != true || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (delete) {
        await _service.delete(entry.id);
      } else {
        await _service.setSharing(entry.id, sharing);
      }
      if (mounted) await _load();
    } on MoodDiaryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('心情小日記'), actions: [
          IconButton(
              tooltip: '重新整理',
              onPressed: _busy || _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: _busy ? () async {} : _load,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  const Text('今天的心情',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    for (final mood in MoodDiaryEntry.moods.entries)
                      ChoiceChip(
                          label: Text(mood.value),
                          selected: _mood == mood.key,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _mood = mood.key),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _text,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 1000,
                      enabled: !_busy,
                      style: const TextStyle(fontSize: 20),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: '想記下什麼？', border: OutlineInputBorder())),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _share,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _share = value ?? false),
                      title: const Text('分享給照護人員與管理員'),
                      subtitle: const Text('僅你授權的照護人員與管理員可看；不勾選就只有自己可看。')),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                      onPressed:
                          _busy || _uncertainSave || _text.text.trim().isEmpty
                              ? null
                              : _save,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                      label: Text(_busy ? '處理中…' : '儲存日記')),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 18)))),
                  const SizedBox(height: 24),
                  const Text('我的日記',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (_loading)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()))
                  else if (_entries.isEmpty && _error == null)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('還沒有日記，今天想記下一點什麼呢？')),
                  for (final entry in _entries) ...[
                    const Divider(height: 32),
                    Text(
                        '${_date(entry.createdAt)} · ${MoodDiaryEntry.moods[entry.mood] ?? '心情'}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(entry.content,
                        style: const TextStyle(fontSize: 20, height: 1.5)),
                    Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(entry.sharedWithCaregiver ? '已分享' : '只有自己可看'),
                          TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _change(entry, delete: false),
                              icon: Icon(entry.sharedWithCaregiver
                                  ? Icons.lock_outline
                                  : Icons.share_outlined),
                              label: Text(
                                  entry.sharedWithCaregiver ? '停止分享' : '分享')),
                          IconButton(
                              tooltip: '刪除日記',
                              onPressed: _busy
                                  ? null
                                  : () => _change(entry, delete: true),
                              icon: const Icon(Icons.delete_outline)),
                        ]),
                  ],
                ]))),
      );

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month}/${local.day}';
  }
}
