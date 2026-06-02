import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/daily_care_task_controller.dart';
import 'package:pet_companion_app/models/daily_care_task.dart';
import 'package:pet_companion_app/services/daily_care_task_api_service.dart';

DailyCareTask _task(
  String id, {
  DailyCareTaskType type = DailyCareTaskType.medication,
  DailyCareTaskStatus status = DailyCareTaskStatus.pending,
  String elderId = 'default_user',
}) {
  return DailyCareTask(
    id: id,
    elderId: elderId,
    title: id,
    type: type,
    description: '',
    scheduledTime: '08:00',
    status: status,
    proofRequired: true,
  );
}

DailyCareTaskSubmission _submission(
  DailyCareVerificationStatus status,
) {
  return DailyCareTaskSubmission(
    id: 'sub-1',
    taskId: 't1',
    status: status == DailyCareVerificationStatus.passed
        ? DailyCareTaskStatus.completed
        : DailyCareTaskStatus.needsReview,
    submittedAt: '',
    verification: DailyCareTaskVerification(
      status: status,
      confidence: 0.9,
      reason: '',
      detectedObjects: const [],
      reviewRequired: status != DailyCareVerificationStatus.passed,
    ),
    note: '',
  );
}

/// 假 API service：可注入回傳資料、記錄呼叫次數、模擬錯誤。
class _FakeApi extends DailyCareTaskApiService {
  _FakeApi({
    List<DailyCareTask> initialTasks = const [],
    this.listError = false,
    this.submitResult,
    this.submitError = false,
  }) : _tasks = List.of(initialTasks);

  List<DailyCareTask> _tasks;
  final bool listError;
  final DailyCareTaskSubmitResult? submitResult;
  final bool submitError;

  int listCalls = 0;
  int createCalls = 0;
  int submitCalls = 0;

  @override
  Future<List<DailyCareTask>> listTasks({required String elderId}) async {
    listCalls++;
    if (listError) {
      throw const DailyCareTaskApiException('現在拿不到今天的任務，待會再看看好嗎？');
    }
    return _tasks.where((t) => t.elderId == elderId || elderId == 'default_user').toList();
  }

  @override
  Future<DailyCareTask> createTask({
    required String elderId,
    required String title,
    required DailyCareTaskType type,
    String scheduledTime = '',
    String description = '',
  }) async {
    createCalls++;
    final task = DailyCareTask(
      id: 'seed-$createCalls',
      elderId: elderId,
      title: title,
      type: type,
      description: description,
      scheduledTime: scheduledTime,
      status: DailyCareTaskStatus.pending,
      proofRequired: true,
    );
    _tasks = [..._tasks, task];
    return task;
  }

  @override
  Future<DailyCareTaskSubmitResult> submitProof({
    required String taskId,
    required File image,
  }) async {
    submitCalls++;
    if (submitError) {
      throw const DailyCareTaskApiException('照片上傳沒成功，待會再試一次好嗎？');
    }
    return submitResult!;
  }
}

void main() {
  test('load：已有任務 → 不補種、tasks 設定正確', () async {
    final api = _FakeApi(initialTasks: [_task('t1'), _task('t2')]);
    final controller = DailyCareTaskController(apiService: api);

    await controller.load();

    expect(controller.tasks.length, 2);
    expect(api.createCalls, 0);
    expect(controller.isLoading, false);
    expect(controller.errorMessage, isNull);
  });

  test('load：無任務 → 首次自動補種吃藥/喝水/運動三項', () async {
    final api = _FakeApi(initialTasks: const []);
    final controller = DailyCareTaskController(apiService: api);

    await controller.load();

    expect(api.createCalls, 3);
    expect(controller.tasks.length, 3);
    final types = controller.tasks.map((t) => t.type).toSet();
    expect(types, {
      DailyCareTaskType.medication,
      DailyCareTaskType.hydration,
      DailyCareTaskType.exercise,
    });
  });

  test('load：第二次空清單不重複補種（同一 elderId 只種一次）', () async {
    final api = _FakeApi(initialTasks: const []);
    final controller = DailyCareTaskController(apiService: api);

    await controller.load();
    expect(api.createCalls, 3);
    // 即使再次 load，已標記種過 → 不再補種。
    await controller.load();
    expect(api.createCalls, 3);
  });

  test('load 失敗 → 白話 errorMessage、不 crash', () async {
    final api = _FakeApi(listError: true);
    final controller = DailyCareTaskController(apiService: api);

    await controller.load();

    expect(controller.errorMessage, contains('拿不到今天的任務'));
    expect(controller.tasks, isEmpty);
    expect(controller.isLoading, false);
  });

  test('submitProof passed → 更新任務為 completed、回傳 submission', () async {
    final passed = _submission(DailyCareVerificationStatus.passed);
    final updatedTask = _task('t1', status: DailyCareTaskStatus.completed);
    final api = _FakeApi(
      initialTasks: [_task('t1')],
      submitResult: DailyCareTaskSubmitResult(
        task: updatedTask,
        submission: passed,
      ),
    );
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();

    final result = await controller.submitProof(
      controller.tasks.first,
      File('/tmp/fake.jpg'),
    );

    expect(result, isNotNull);
    expect(result!.verification!.status, DailyCareVerificationStatus.passed);
    expect(controller.tasks.first.status, DailyCareTaskStatus.completed);
  });

  test('submitProof uncertain → 任務變 needs_review（不假裝完成）', () async {
    final uncertain = _submission(DailyCareVerificationStatus.uncertain);
    final updatedTask = _task('t1', status: DailyCareTaskStatus.needsReview);
    final api = _FakeApi(
      initialTasks: [_task('t1')],
      submitResult: DailyCareTaskSubmitResult(
        task: updatedTask,
        submission: uncertain,
      ),
    );
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();

    final result = await controller.submitProof(
      controller.tasks.first,
      File('/tmp/fake.jpg'),
    );

    expect(result!.verification!.status, DailyCareVerificationStatus.uncertain);
    expect(controller.tasks.first.status, DailyCareTaskStatus.needsReview);
    expect(controller.tasks.first.status, isNot(DailyCareTaskStatus.completed));
  });

  test('submitProof 失敗 → 回 null、白話 errorMessage', () async {
    final api = _FakeApi(initialTasks: [_task('t1')], submitError: true);
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();

    final result = await controller.submitProof(
      controller.tasks.first,
      File('/tmp/fake.jpg'),
    );

    expect(result, isNull);
    expect(controller.errorMessage, contains('照片上傳沒成功'));
  });

  test('setElderId 切換會清空目前任務', () async {
    final api = _FakeApi(initialTasks: [_task('t1')]);
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();
    expect(controller.tasks, isNotEmpty);

    controller.setElderId('elder-other');
    expect(controller.tasks, isEmpty);
  });
}
