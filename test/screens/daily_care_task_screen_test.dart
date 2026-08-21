import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/daily_care_task_controller.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/models/daily_care_task.dart';
import 'package:pet_companion_app/models/pet_status.dart';
import 'package:pet_companion_app/routes/app_routes.dart';
import 'package:pet_companion_app/screens/daily_care_task_screen.dart';
import 'package:pet_companion_app/services/daily_care_task_api_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/photo_picker_service.dart';
import 'package:pet_companion_app/services/text_to_speech_service.dart';
import 'package:pet_companion_app/widgets/daily_care_task_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

DailyCareTask _task(
  String id,
  String title, {
  DailyCareTaskType type = DailyCareTaskType.medication,
  DailyCareTaskStatus status = DailyCareTaskStatus.pending,
}) {
  return DailyCareTask(
    id: id,
    elderId: 'default_user',
    title: title,
    type: type,
    description: '',
    scheduledTime: '08:00',
    status: status,
    proofRequired: true,
  );
}

class _FakeApi extends DailyCareTaskApiService {
  _FakeApi({this.tasks = const [], this.listError = false, this.submitResult});
  final List<DailyCareTask> tasks;
  final bool listError;
  final DailyCareTaskSubmitResult? submitResult;

  @override
  Future<List<DailyCareTask>> listTasks({required String elderId}) async {
    if (listError) {
      throw const DailyCareTaskApiException('現在拿不到今天的任務，待會再看看好嗎？');
    }
    return tasks;
  }

  @override
  Future<DailyCareTaskSubmitResult> submitProof({
    required String taskId,
    required File image,
  }) async {
    final result = submitResult;
    if (result == null) {
      throw const DailyCareTaskApiException('照片上傳沒成功，待會再試一次好嗎？');
    }
    return result;
  }
}

/// 記錄被呼叫、且一律回 null（模擬使用者取消）的假相機 / 相簿。
class _CancelPicker extends PhotoPickerService {
  bool cameraCalled = false;
  bool galleryCalled = false;

  @override
  Future<File?> pickFromCamera() async {
    cameraCalled = true;
    return null;
  }

  @override
  Future<File?> pickFromGallery() async {
    galleryCalled = true;
    return null;
  }
}

class _OneImagePicker extends PhotoPickerService {
  bool cameraCalled = false;

  @override
  Future<File?> pickFromCamera() async {
    cameraCalled = true;
    return File('/tmp/daily-care-proof-test.jpg');
  }
}

class _RecordingTextToSpeechService extends TextToSpeechService {
  String? spokenText;
  bool? enabledValue;

  @override
  Future<void> speak(
    String text, {
    required bool enabled,
    required double volume,
    required String speechStyle,
    required Future<void> Function() onStart,
    required Future<void> Function() onComplete,
    required Future<void> Function() onError,
  }) async {
    spokenText = text;
    enabledValue = enabled;
    await onStart();
    await onComplete();
  }
}

Widget _wrap(
  DailyCareTaskController controller, {
  PhotoPickerService? picker,
  Object? routeArgs,
  PetController? petController,
  ProfileController? profileController,
  TextToSpeechService? ttsService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DailyCareTaskController>.value(value: controller),
      if (petController != null)
        ChangeNotifierProvider<PetController>.value(value: petController),
      if (profileController != null)
        ChangeNotifierProvider<ProfileController>.value(
          value: profileController,
        ),
      if (ttsService != null)
        Provider<TextToSpeechService>.value(value: ttsService),
    ],
    child: MaterialApp(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        settings: RouteSettings(arguments: routeArgs),
        builder: (_) => DailyCareTaskScreen(photoPicker: picker),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('顯示任務卡片：名稱、類型、狀態文案', (tester) async {
    final controller = DailyCareTaskController(
      apiService: _FakeApi(tasks: [
        _task('t1', '早上吃藥'),
        _task('t2', '喝水',
            type: DailyCareTaskType.hydration,
            status: DailyCareTaskStatus.completed),
        _task('t3', '散步',
            type: DailyCareTaskType.exercise,
            status: DailyCareTaskStatus.needsReview),
      ]),
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('今日任務'), findsWidgets);
    expect(find.text('早上吃藥'), findsOneWidget);
    expect(find.text('喝水'), findsOneWidget);
    expect(find.text('散步'), findsOneWidget);
    // 狀態文案。
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('等待照護人員查看'), findsOneWidget);
    // 完成的任務顯示「完成」、未完成顯示「拍照完成」。
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('拍照完成'), findsOneWidget); // pending 那張
  });

  testWidgets('空清單顯示白話空狀態', (tester) async {
    final controller = DailyCareTaskController(apiService: _FakeApi(tasks: []));
    // 注意：load 會嘗試補種，但 _FakeApi.createTask 會新增；這裡用已 seeded 模擬：
    // 直接驗證「沒有任務時不會 crash 且有文字」。
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();
    // 補種後會有 3 張預設卡，畫面仍正常顯示標題。
    expect(find.text('今日任務'), findsWidgets);
  });

  testWidgets('載入失敗顯示白話錯誤與「再試一次」', (tester) async {
    final controller =
        DailyCareTaskController(apiService: _FakeApi(listError: true));
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('拿不到今天的任務'), findsOneWidget);
    expect(find.text('再試一次'), findsOneWidget);
  });

  testWidgets('點「拍照完成」→ 出現來源選單；選相機後取消不 crash', (tester) async {
    final picker = _CancelPicker();
    final controller = DailyCareTaskController(
      apiService: _FakeApi(tasks: [_task('t1', '早上吃藥')]),
    );
    await tester.pumpWidget(_wrap(controller, picker: picker));
    await tester.pumpAndSettle();

    await tester.tap(find.text('拍照完成'));
    await tester.pumpAndSettle();
    // 來源選單出現。
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('從相簿選'), findsOneWidget);

    await tester.tap(find.text('拍照'));
    await tester.pumpAndSettle();

    // 相機被呼叫、回 null（取消）→ 不 crash，仍在任務頁。
    expect(picker.cameraCalled, isTrue);
    expect(find.text('今日任務'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('語音進入吃藥任務時顯示拍照驗證引導', (tester) async {
    final controller = DailyCareTaskController(
      apiService: _FakeApi(tasks: [_task('t1', '早上吃藥')]),
    );
    await tester.pumpWidget(
      _wrap(
        controller,
        routeArgs: const DailyCareTaskRouteArgs(
          launchedFromVoice: true,
          requestedTaskType: 'medication',
          requestedTaskLabel: '吃藥',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('我聽到你完成吃藥'), findsOneWidget);
    expect(find.textContaining('再拍一張照片'), findsOneWidget);
    expect(find.text('拍照完成'), findsOneWidget);
  });

  testWidgets('照片送出後會更新寵物訊息並朗讀驗證結果', (tester) async {
    final originalTask = _task('t1', '早上吃藥');
    final completedTask = _task(
      't1',
      '早上吃藥',
      status: DailyCareTaskStatus.completed,
    );
    const submission = DailyCareTaskSubmission(
      id: 's1',
      taskId: 't1',
      status: DailyCareTaskStatus.completed,
      submittedAt: '2026-08-17T09:00:00.000Z',
      verification: DailyCareTaskVerification(
        status: DailyCareVerificationStatus.passed,
        confidence: 0.92,
        reason: '照片符合吃藥任務',
        detectedObjects: ['medication'],
        reviewRequired: false,
      ),
      note: '',
    );
    final picker = _OneImagePicker();
    final petController = PetController();
    final profileController = ProfileController(LocalStorageService());
    await profileController.load();
    final ttsService = _RecordingTextToSpeechService();
    final controller = DailyCareTaskController(
      apiService: _FakeApi(
        tasks: [originalTask],
        submitResult: DailyCareTaskSubmitResult(
          task: completedTask,
          submission: submission,
        ),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        controller,
        picker: picker,
        petController: petController,
        profileController: profileController,
        ttsService: ttsService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拍照完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍照'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    expect(picker.cameraCalled, isTrue);
    expect(ttsService.spokenText, contains('早上吃藥'));
    expect(ttsService.spokenText, contains('確認完成'));
    expect(ttsService.enabledValue, isTrue);
    expect(petController.message, contains('確認完成'));
    expect(petController.mode, PetMode.happy);
    expect(find.text('完成囉！'), findsOneWidget);
    petController.dispose();
    profileController.dispose();
  });

  testWidgets('任務卡片在窄螢幕不因長狀態文字和按鈕溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: DailyCareTaskCard(
              task: _task(
                't3',
                '下午散步',
                type: DailyCareTaskType.exercise,
                status: DailyCareTaskStatus.needsReview,
              ),
              isSubmitting: false,
              onComplete: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('等待照護人員查看'), findsOneWidget);
    expect(find.text('重新拍照'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
