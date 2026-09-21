import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/mood_diary_entry.dart';
import 'package:pet_companion_app/screens/mood_diary_screen.dart';
import 'package:pet_companion_app/services/mood_diary_service.dart';

class _Diary extends MoodDiaryService {
  _Diary()
      : super(
            ownerId: 'fixture',
            currentUserId: () => 'fixture',
            authTokenProvider: () async => null);
  final entries = <MoodDiaryEntry>[];
  bool failSave = false;
  int saves = 0;
  bool? savedSharing;
  @override
  Future<List<MoodDiaryEntry>> list() async => List.of(entries);
  @override
  Future<void> create(
      {required String mood,
      required String content,
      required bool sharedWithCaregiver}) async {
    saves++;
    if (failSave) throw const MoodDiaryException('請先重新整理日記');
    savedSharing = sharedWithCaregiver;
    entries.add(MoodDiaryEntry(
        id: 'entry',
        mood: mood,
        content: content,
        createdAt: DateTime(2026, 9, 21),
        sharedWithCaregiver: sharedWithCaregiver));
  }
}

Future<void> _pump(WidgetTester tester, _Diary service) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MoodDiaryScreen(createService: () => service))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'small screen readable, private by default, save remains deliberate',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Diary();
    await _pump(tester, service);
    expect(tester.takeException(), isNull);
    expect(service.saves, 0);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
    await tester.enterText(find.byType(TextField), '今天和家人散步，很開心');
    await tester.pump();
    await tester.ensureVisible(find.text('儲存日記'));
    await tester.tap(find.text('儲存日記'));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(service.savedSharing, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save keeps draft and blocks resend until refresh',
      (tester) async {
    final service = _Diary()..failSave = true;
    await _pump(tester, service);
    await tester.enterText(find.byType(TextField), '想念家人');
    await tester.pump();
    await tester.ensureVisible(find.text('儲存日記'));
    await tester.tap(find.text('儲存日記'));
    await tester.pumpAndSettle();
    expect(find.text('想念家人'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, '儲存日記');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(service.saves, 1);
    await tester.tap(find.byTooltip('重新整理'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });
}
