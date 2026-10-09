import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet_companion_app/models/daily_companion_moment.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/widgets/daily_companion_moment.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStorageService storage;
  late DateTime now;
  int reactions = 0;
  const pat = ValueKey('daily-moment-pat');
  const skip = ValueKey('daily-moment-skip');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    now = DateTime(2026, 10, 9, 12);
    reactions = 0;
  });

  Widget host({String user = 'synthetic-a', Future<bool> Function()? react}) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyCompanionMoment(
              storage: storage,
              userId: user,
              petName: '小伴',
              clock: () => now,
              onPat: react ??
                  () async {
                    reactions++;
                    return true;
                  },
            ),
          ),
        ),
      );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  test('record parser rejects malformed and normalized invalid dates', () {
    for (final raw in [
      null,
      '',
      '2026-10-09|unknown',
      '2026-13-01|skipped',
      '2026-02-30|completed',
      '2026-10-09|completed|extra'
    ]) {
      expect(DailyCompanionMomentRecord.decode(raw), isNull);
    }
  });

  test('bounded explicit-user storage stays separate from care/profile state',
      () async {
    SharedPreferences.setMockInitialValues(
        {'taskCompletionState': '{"water":true}', 'checkInDate': '2026-10-09'});
    const record = DailyCompanionMomentRecord(
        date: '2026-10-09', status: DailyCompanionMomentStatus.completed);
    final saving =
        storage.saveDailyCompanionMoment(userId: 'synthetic-a', record: record);
    storage.setUserId('synthetic-b');
    await saving;
    expect(
        (await storage.loadDailyCompanionMoment(userId: 'synthetic-a'))?.status,
        DailyCompanionMomentStatus.completed);
    expect(
        await storage.loadDailyCompanionMoment(userId: 'synthetic-b'), isNull);
    await storage.saveDailyCompanionMoment(
        userId: 'synthetic-a',
        record: const DailyCompanionMomentRecord(
            date: '2026-10-10', status: DailyCompanionMomentStatus.skipped));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) => key.contains('dailyCompanionMoment')),
        hasLength(1));
    expect(prefs.getString('taskCompletionState'), '{"water":true}');
    expect(prefs.getString('checkInDate'), '2026-10-09');
  });

  testWidgets('completion reacts once and survives widget and storage restart',
      (tester) async {
    final reaction = Completer<bool>();
    await tester.pumpWidget(host(react: () {
      reactions++;
      return reaction.future;
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pump();
    await tester.tap(find.byKey(pat));
    expect(reactions, 1);
    reaction.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsNothing);
    expect(find.textContaining('今天已一起陪伴'), findsOneWidget);
    await dispose(tester);
    storage = LocalStorageService();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsNothing);
    expect(reactions, 1);
    await dispose(tester);
  });

  testWidgets('skip is final for the day and does not react', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(skip));
    await tester.pumpAndSettle();
    expect(find.text('今天先休息也很好，我在這裡陪你。'), findsOneWidget);
    expect(reactions, 0);
    await dispose(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(skip), findsNothing);
    await dispose(tester);
  });

  testWidgets('a suppressed local response leaves the invitation available',
      (tester) async {
    await tester.pumpWidget(host(react: () async => false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    expect(
        await storage.loadDailyCompanionMoment(userId: 'synthetic-a'), isNull);
    await dispose(tester);
  });

  testWidgets('midnight and resume offer a fresh invitation without a streak',
      (tester) async {
    now = DateTime(2026, 10, 9, 23, 59, 59);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(skip));
    await tester.pumpAndSettle();
    now = DateTime(2026, 10, 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    await tester.tap(find.byKey(skip));
    await tester.pumpAndSettle();
    now = DateTime(2026, 10, 12, 12);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    expect(reactions, 0);
    await dispose(tester);
  });

  testWidgets(
      'an account switch during reaction cannot resolve the new account',
      (tester) async {
    final reaction = Completer<bool>();
    await tester.pumpWidget(host(react: () => reaction.future));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pump();
    await tester.pumpWidget(host(user: 'synthetic-b'));
    reaction.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    expect(
        await storage.loadDailyCompanionMoment(userId: 'synthetic-b'), isNull);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('failed persistence retries on resume without another reaction',
      (tester) async {
    final flaky = _FailOnceStorage();
    storage = flaky;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsNothing);
    expect(reactions, 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
        (await storage.loadDailyCompanionMoment(userId: 'synthetic-a'))?.status,
        DailyCompanionMomentStatus.completed);
    expect(reactions, 1);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets(
      'account switching during save preserves only the captured account',
      (tester) async {
    final delayed = _DelayedSaveStorage();
    storage = delayed;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pump();
    await tester.pumpWidget(host(user: 'synthetic-b'));
    delayed.release.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    expect(
        (await storage.loadDailyCompanionMoment(userId: 'synthetic-a'))?.date,
        '2026-10-09');
    expect(
        await storage.loadDailyCompanionMoment(userId: 'synthetic-b'), isNull);
    await dispose(tester);
  });

  testWidgets('midnight during save cannot resolve the next day',
      (tester) async {
    final delayed = _DelayedSaveStorage();
    storage = delayed;
    now = DateTime(2026, 10, 9, 23, 59, 59);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pump();
    now = DateTime(2026, 10, 10);
    await tester.pump(const Duration(seconds: 1));
    delayed.release.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    expect(
        (await storage.loadDailyCompanionMoment(userId: 'synthetic-a'))?.date,
        '2026-10-09');
    expect(reactions, 1);
    await dispose(tester);
  });

  testWidgets(
      'resume loading disables action until the captured record is loaded',
      (tester) async {
    final controlled = _ControlledLoadStorage();
    storage = controlled;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    controlled.delay = Completer<void>();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(pat), findsNothing);
    expect(reactions, 0);
    controlled.delay!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsNothing);
    expect(reactions, 1);
    await dispose(tester);
  });

  testWidgets('failed load at midnight does not retain yesterday completion',
      (tester) async {
    final controlled = _ControlledLoadStorage();
    storage = controlled;
    now = DateTime(2026, 10, 9, 23, 59, 59);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    controlled.fail = true;
    now = DateTime(2026, 10, 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(pat), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-moment-resolved')), findsNothing);
    await dispose(tester);
  });

  testWidgets('midnight retries pending save with its original date',
      (tester) async {
    storage = _FailOnceStorage();
    now = DateTime(2026, 10, 9, 23, 59, 59);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    now = DateTime(2026, 10, 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
        (await storage.loadDailyCompanionMoment(userId: 'synthetic-a'))?.date,
        '2026-10-09');
    expect(find.byKey(pat), findsOneWidget);
    expect(reactions, 1);
    await dispose(tester);
  });

  testWidgets('overlapping refreshes cannot let yesterday overwrite today',
      (tester) async {
    final controlled = _DelayedRetryStorage();
    storage = controlled;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    now = DateTime(2026, 10, 10, 12);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(pat), findsNothing);
    expect(controlled.attempts, 2);
    controlled.release.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(pat));
    await tester.pumpAndSettle();
    expect(
        (await storage.loadDailyCompanionMoment(userId: 'synthetic-a'))?.date,
        '2026-10-10');
    expect(reactions, 2);
    await dispose(tester);
  });

  testWidgets('large text scrolls to both minimum 48px actions',
      (tester) async {
    await binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(4)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: DailyCompanionMoment(
                    storage: storage,
                    userId: 'synthetic-a',
                    petName: '小伴',
                    clock: () => now,
                    onPat: () async => true)))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(skip));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(skip)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(pat)).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(skip));
    await tester.pumpAndSettle();
    expect(find.byKey(skip), findsNothing);
    await dispose(tester);
  });
}

class _FailOnceStorage extends LocalStorageService {
  bool fail = true;
  @override
  Future<void> saveDailyCompanionMoment(
      {required String userId,
      required DailyCompanionMomentRecord record}) async {
    if (fail) {
      fail = false;
      throw StateError('synthetic save failure');
    }
    await super.saveDailyCompanionMoment(userId: userId, record: record);
  }
}

class _DelayedSaveStorage extends LocalStorageService {
  final release = Completer<void>();
  @override
  Future<void> saveDailyCompanionMoment(
      {required String userId,
      required DailyCompanionMomentRecord record}) async {
    await release.future;
    await super.saveDailyCompanionMoment(userId: userId, record: record);
  }
}

class _ControlledLoadStorage extends LocalStorageService {
  Completer<void>? delay;
  bool fail = false;
  @override
  Future<DailyCompanionMomentRecord?> loadDailyCompanionMoment(
      {required String userId}) async {
    if (delay != null) await delay!.future;
    if (fail) throw StateError('synthetic load failure');
    return super.loadDailyCompanionMoment(userId: userId);
  }
}

class _DelayedRetryStorage extends LocalStorageService {
  final release = Completer<void>();
  int attempts = 0;
  @override
  Future<void> saveDailyCompanionMoment(
      {required String userId,
      required DailyCompanionMomentRecord record}) async {
    attempts++;
    if (attempts == 1) throw StateError('synthetic first save failure');
    if (attempts == 2) await release.future;
    await super.saveDailyCompanionMoment(userId: userId, record: record);
  }
}
