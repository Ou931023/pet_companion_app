import 'dart:async';

import 'package:flutter/material.dart';

import '../models/daily_companion_moment.dart';
import '../services/local_storage_service.dart';

/// A small invitation; choosing rest is as final as choosing companionship.
class DailyCompanionMoment extends StatefulWidget {
  const DailyCompanionMoment({
    super.key,
    required this.storage,
    required this.userId,
    required this.petName,
    required this.onPat,
    this.clock = DateTime.now,
  });

  final LocalStorageService storage;
  final String userId;
  final String petName;
  final Future<bool> Function() onPat;
  final DateTime Function() clock;

  @override
  State<DailyCompanionMoment> createState() => _DailyCompanionMomentState();
}

class _DailyCompanionMomentState extends State<DailyCompanionMoment>
    with WidgetsBindingObserver {
  Timer? _midnight;
  int _generation = 0;
  String? _date;
  DailyCompanionMomentStatus? _status;
  DailyCompanionMomentRecord? _pending;
  bool _loading = true;
  bool _acting = false;
  bool _refreshing = false;
  bool _refreshAfterAction = false;

  String get _today => DailyCompanionMomentRecord.localDate(widget.clock());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(DailyCompanionMoment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.storage != widget.storage) {
      _generation++;
      _pending = null;
      _status = null;
      _date = null;
      _loading = true;
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = widget.clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () => unawaited(_refresh()));
  }

  bool _current(int generation, String userId, String date) =>
      mounted &&
      generation == _generation &&
      userId == widget.userId &&
      date == _today;

  Future<void> _refresh() async {
    if (_acting || _refreshing) {
      _refreshAfterAction = true;
      return;
    }
    _refreshing = true;
    final generation = ++_generation;
    final user = widget.userId;
    final date = _today;
    final storage = widget.storage;
    final pending = _pending;
    final previousDate = _date;
    final previousStatus = _status;
    setState(() => _loading = true);
    _scheduleMidnight();
    try {
      if (pending != null) {
        await storage.saveDailyCompanionMoment(userId: user, record: pending);
      }
      final record = await storage.loadDailyCompanionMoment(userId: user);
      if (!_current(generation, user, date)) return;
      setState(() {
        _date = date;
        _status = record?.date == date ? record?.status : null;
        _pending = null;
        _loading = false;
      });
    } catch (_) {
      if (!_current(generation, user, date)) return;
      setState(() {
        _date = date;
        _status = pending?.date == date
            ? pending?.status
            : previousDate == date
                ? previousStatus
                : null;
        _pending = pending;
        _loading = false;
      });
    } finally {
      _refreshing = false;
      if (mounted && _refreshAfterAction) {
        _refreshAfterAction = false;
        unawaited(_refresh());
      }
    }
  }

  Future<void> _choose(DailyCompanionMomentStatus status) async {
    if (_acting || _loading || _status != null) return;
    if (_date != _today) {
      await _refresh();
      return;
    }
    final generation = _generation;
    final user = widget.userId;
    final date = _date!;
    final storage = widget.storage;
    setState(() => _acting = true);
    try {
      if (status == DailyCompanionMomentStatus.completed &&
          !await widget.onPat()) {
        return;
      }
      if (!_current(generation, user, date)) return;
      final record = DailyCompanionMomentRecord(date: date, status: status);
      setState(() {
        _status = status;
        _pending = record;
      });
      // If saving fails, keep this visit resolved and retry on resume without
      // replaying the pet reaction. The pending record always retains its day.
      await storage.saveDailyCompanionMoment(userId: user, record: record);
      if (_current(generation, user, date)) _pending = null;
    } catch (_) {
      // Optional companionship must not interrupt the rest of the home screen.
    } finally {
      if (mounted) {
        setState(() => _acting = false);
        if (_refreshAfterAction || !_current(generation, user, date)) {
          _refreshAfterAction = false;
          unawaited(_refresh());
        }
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_status != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(
          liveRegion: true,
          child: Text(
            _status == DailyCompanionMomentStatus.completed
                ? '今天已一起陪伴。想再摸摸我，隨時都可以。'
                : '今天先休息也很好，我在這裡陪你。',
            key: const ValueKey('daily-moment-resolved'),
            style: const TextStyle(fontSize: 17, height: 1.3),
          ),
        ),
      );
    }
    final name = widget.petName.trim().isEmpty ? '小伴' : widget.petName;
    return Card(
      key: const ValueKey('daily-moment-invitation'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('今天的小陪伴',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('摸摸$name，一起放鬆一下。',
                style: const TextStyle(fontSize: 17, height: 1.3)),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('daily-moment-pat'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _acting
                  ? null
                  : () =>
                      unawaited(_choose(DailyCompanionMomentStatus.completed)),
              child: const Text('摸摸我', style: TextStyle(fontSize: 17)),
            ),
            TextButton(
              key: const ValueKey('daily-moment-skip'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _acting
                  ? null
                  : () =>
                      unawaited(_choose(DailyCompanionMomentStatus.skipped)),
              child: const Text('今天先休息', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
      ),
    );
  }
}
