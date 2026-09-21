import 'dart:async';
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
  bool editError = false;
  int editCalls = 0;
  final List<Completer<DailyCareTask>> editRequests = [];
  bool delayEdits = false;

  @override
  Future<DailyCareTask> updateTask({
    required String taskId,
    required String title,
    required String description,
    required String scheduledTime,
  }) async {
    editCalls++;
    if (delayEdits) {
      final request = Completer<DailyCareTask>();
      editRequests.add(request);
      return request.future;
    }
    if (editError) {
      throw const DailyCareTaskApiException('請重新查看任務。', requiresRefresh: true);
    }
    final previous = _tasks.firstWhere((t) => t.id == taskId);
    return DailyCareTask(
      id: taskId,
      elderId: previous.elderId,
      title: title,
      type: previous.type,
      description: description,
      scheduledTime: scheduledTime,
      status: previous.status,
      proofRequired: previous.proofRequired,
    );
  }

  @override
  Future<List<DailyCareTask>> listTasks({required String elderId}) async {
    listCalls++;
    if (listError) {
      throw const DailyCareTaskApiException('現在拿不到今天的任務，待會再看看好嗎？');
    }
    return _tasks
        .where((t) => t.elderId == elderId || elderId == 'default_user')
        .toList();
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
  test('edit completion after dispose is ignored without notification',
      () async {
    final api = _FakeApi(initialTasks: [_task('t1')])..delayEdits = true;
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();
    final pending = controller.updateTask(
        taskId: 't1', title: '散步', description: '', scheduledTime: '16:30');
    controller.dispose();
    api.editRequests.single.complete(_task('t1'));
    expect(await pending, false);
  });

  test('old account edit cannot clear new account saving state', () async {
    final api = _FakeApi(initialTasks: [_task('t1')])..delayEdits = true;
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();
    final oldEdit = controller.updateTask(
        taskId: 't1', title: '舊內容', description: '', scheduledTime: '16:30');
    controller.setElderId('other');
    api._tasks = [_task('t1', elderId: 'other')];
    await controller.load();
    final newEdit = controller.updateTask(
        taskId: 't1', title: '新內容', description: '', scheduledTime: '17:30');
    var notifications = 0;
    controller.addListener(() => notifications++);
    api.editRequests.first.complete(_task('t1'));
    expect(await oldEdit, false);
    expect(controller.isUpdating('t1'), true);
    expect(controller.tasks.first.elderId, 'other');
    expect(notifications, 0);
    api.editRequests.last.complete(_task('t1', elderId: 'other'));
    expect(await newEdit, true);
    expect(controller.isUpdating('t1'), false);
    controller.dispose();
  });

  test('edit applies server task without changing completion status', () async {
    final api = _FakeApi(initialTasks: [_task('t1')]);
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();
    expect(
        await controller.updateTask(
            taskId: 't1',
            title: '散步',
            description: '慢慢走',
            scheduledTime: '16:30'),
        true);
    expect(controller.tasks.first.title, '散步');
    expect(controller.tasks.first.scheduledTime, '16:30');
    expect(controller.tasks.first.status, DailyCareTaskStatus.pending);
    expect(controller.isUpdating('t1'), false);
  });

  test('edit rejects blank content and completed history before HTTP',
      () async {
    final api = _FakeApi(initialTasks: [
      _task('t1'),
      _task('t2', status: DailyCareTaskStatus.completed)
    ]);
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();
    expect(
        await controller.updateTask(
            taskId: 't1', title: ' ', description: '', scheduledTime: '16:30'),
        false);
    expect(
        await controller.updateTask(
            taskId: 't2', title: '散步', description: '', scheduledTime: '16:30'),
        false);
    expect(api.editCalls, 0);
  });

  test('edit conflict refreshes list and preserves old task', () async {
    final api = _FakeApi(initialTasks: [_task('t1')])..editError = true;
    final controller = DailyCareTaskController(apiService: api);
    await controller.load();
    expect(
        await controller.updateTask(
            taskId: 't1', title: '散步', description: '', scheduledTime: '16:30'),
        false);
    expect(controller.tasks.first.title, 't1');
    expect(api.listCalls, 2);
    expect(controller.errorMessage, '請重新查看任務。');
    expect(controller.isUpdating('t1'), false);
  });

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
