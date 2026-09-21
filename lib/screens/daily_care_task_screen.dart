import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/daily_care_task_controller.dart';
import '../controllers/pet_controller.dart';
import '../controllers/profile_controller.dart';
import '../models/daily_care_task.dart';
import '../models/pet_status.dart';
import '../routes/app_routes.dart';
import '../services/photo_picker_service.dart';
import '../services/text_to_speech_service.dart';
import '../widgets/daily_care_task_card.dart';
import '../widgets/ui/elder_feedback.dart';

/// CR-0025 長者端「今日任務」頁：吃藥 / 喝水 / 運動，拍照完成 → AI 確認 → 更新狀態。
class DailyCareTaskScreen extends StatefulWidget {
  const DailyCareTaskScreen({super.key, this.photoPicker});

  /// 可注入（測試用）；預設用真的相機 / 相簿。
  final PhotoPickerService? photoPicker;

  @override
  State<DailyCareTaskScreen> createState() => _DailyCareTaskScreenState();
}

class _DailyCareTaskScreenState extends State<DailyCareTaskScreen> {
  late final PhotoPickerService _picker =
      widget.photoPicker ?? PhotoPickerService();
  DailyCareTaskRouteArgs? _voiceArgs;
  bool _routeArgsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DailyCareTaskController>().load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeArgsLoaded) return;
    _routeArgsLoaded = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is DailyCareTaskRouteArgs && args.launchedFromVoice) {
      _voiceArgs = args;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DailyCareTaskController>();
    return Scaffold(
      appBar: AppBar(title: const Text('今日任務')),
      body: RefreshIndicator(
        onRefresh: () => controller.load(),
        child: _buildBody(context, controller),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DailyCareTaskController controller) {
    if (controller.isLoading && controller.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '今日任務',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          '完成吃藥、喝水、運動後拍張照，我幫你記錄下來。',
          style: TextStyle(fontSize: 17, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (_voiceArgs != null) ...[
          _VoiceGuidanceBanner(
            taskLabel: _voiceArgs!.requestedTaskLabel,
          ),
          const SizedBox(height: 12),
        ],
        if (controller.errorMessage != null)
          _ErrorBanner(
            message: controller.errorMessage!,
            onRetry: () => controller.load(),
          ),
        if (controller.tasks.isEmpty && controller.errorMessage == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '今天還沒有任務，下拉可以重新整理。',
                style: TextStyle(fontSize: 18, color: Colors.black54),
              ),
            ),
          ),
        for (final task in controller.tasks) ...[
          DailyCareTaskCard(
            task: task,
            isSubmitting: controller.isSubmitting(task.id),
            isHighlighted: _isVoiceTarget(task),
            onComplete: () {
              if (!controller.isUpdating(task.id)) _handleComplete(task);
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: '修改${task.title}的內容與時間',
              icon: const Icon(Icons.edit_outlined),
              onPressed: task.status != DailyCareTaskStatus.pending ||
                      task.latestSubmission != null ||
                      controller.isSubmitting(task.id) ||
                      controller.isUpdating(task.id)
                  ? null
                  : () => _editTask(task),
            ),
          ),
        ],
      ],
    );
  }

  bool _isVoiceTarget(DailyCareTask task) {
    final requestedType = _voiceArgs?.requestedTaskType;
    if (requestedType == null || requestedType.isEmpty) return false;
    return dailyCareTaskTypeToString(task.type) == requestedType;
  }

  Future<void> _editTask(DailyCareTask task) async {
    final controller = context.read<DailyCareTaskController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TaskEditor(task: task, controller: controller),
    );
  }

  /// 使用 State 自身的 `context`（不接收 context 參數），讓 `mounted` 能正確守衛
  /// 跨 async gap 的 context 使用。
  Future<void> _handleComplete(DailyCareTask task) async {
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;

    File? image;
    try {
      image = source == _PickSource.camera
          ? await _picker.pickFromCamera()
          : await _picker.pickFromGallery();
    } on PlatformException {
      if (!mounted) return;
      _showSnack('需要相機或照片權限，才能上傳完成照片。');
      return;
    } catch (_) {
      if (!mounted) return;
      _showSnack('開啟相機或相簿時出了點問題，待會再試一次好嗎？');
      return;
    }
    // 使用者取消選圖：安靜返回，不 crash。
    if (image == null || !mounted) return;

    final confirmed = await _confirmPreview(context, image);
    if (confirmed != true || !mounted) return;

    final controller = context.read<DailyCareTaskController>();
    final submission = await controller.submitProof(task, image);
    if (!mounted) return;
    if (submission == null) {
      _showSnack(controller.errorMessage ?? '照片上傳沒成功，待會再試一次好嗎？');
      return;
    }
    await _deliverSubmissionVoiceFeedback(task, submission);
    if (!mounted) return;
    await _showAiResult(context, submission);
  }

  Future<void> _deliverSubmissionVoiceFeedback(
    DailyCareTask task,
    DailyCareTaskSubmission submission,
  ) async {
    final message = _submissionVoiceMessage(task, submission);
    final petMode = _petModeForSubmission(submission);
    final petController = _maybeRead<PetController>();
    final profileController = _maybeRead<ProfileController>();
    final ttsService = _maybeRead<TextToSpeechService>();
    petController?.setModeAndMessage(petMode, message);
    if (profileController == null || ttsService == null) return;

    await ttsService.speak(
      message,
      enabled: profileController.ttsEnabled,
      volume: profileController.petVolume,
      speechStyle: profileController.speechStyle,
      onStart: () async {
        petController?.setMode(PetMode.talking, isSpeaking: true);
      },
      onComplete: () async {
        petController?.setMode(petMode, isSpeaking: false);
      },
      onError: () async {
        petController?.setMode(petMode, isSpeaking: false);
      },
    );
  }

  String _submissionVoiceMessage(
    DailyCareTask task,
    DailyCareTaskSubmission submission,
  ) {
    final taskLabel = task.title.isEmpty ? task.typeLabel : task.title;
    final status = submission.verification?.status;
    return switch (status) {
      DailyCareVerificationStatus.passed =>
        '$taskLabel 的照片已經送出，也確認完成了。做得很好，我幫你記錄下來。',
      DailyCareVerificationStatus.failed =>
        '$taskLabel 的照片已經送出，但看起來不太清楚。我們再拍一次，或請照護人員幫你確認。',
      _ => '$taskLabel 的照片已經送出。我先幫你交給照護人員確認，你不用擔心。',
    };
  }

  PetMode _petModeForSubmission(DailyCareTaskSubmission submission) {
    return switch (submission.verification?.status) {
      DailyCareVerificationStatus.passed => PetMode.happy,
      DailyCareVerificationStatus.failed => PetMode.caring,
      _ => PetMode.listening,
    };
  }

  T? _maybeRead<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<_PickSource?> _chooseSource(BuildContext context) {
    return showModalBottomSheet<_PickSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '要怎麼上傳這項任務的照片？',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, size: 30),
                title: const Text('拍照', style: TextStyle(fontSize: 20)),
                onTap: () => Navigator.of(sheetContext).pop(_PickSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, size: 30),
                title: const Text('從相簿選', style: TextStyle(fontSize: 20)),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_PickSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmPreview(BuildContext context, File image) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '確認照片',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  image,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 220,
                    child: Center(child: Icon(Icons.image, size: 48)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '這張照片可以嗎？確定後我幫你送出。',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('重拍', style: TextStyle(fontSize: 18)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('送出', style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAiResult(
    BuildContext context,
    DailyCareTaskSubmission submission,
  ) {
    final status = submission.verification?.status;
    final (title, message) = switch (status) {
      DailyCareVerificationStatus.passed => (
          '完成囉！',
          '做得很好，我幫你記錄完成了。',
        ),
      DailyCareVerificationStatus.failed => (
          '再確認一下',
          '這張照片好像不太符合任務，我們再確認一下。',
        ),
      _ => (
          '先幫你送出',
          '這張照片我看不太清楚，先送給照護人員確認。',
        ),
    };
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          content:
              Text(message, style: const TextStyle(fontSize: 18, height: 1.4)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('好', style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    ElderFeedback.showImportant(context, message);
  }
}

enum _PickSource { camera, gallery }

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({required this.task, required this.controller});
  final DailyCareTask task;
  final DailyCareTaskController controller;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _description =
      TextEditingController(text: widget.task.description);
  final _form = GlobalKey<FormState>();
  TimeOfDay? _time;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$')
        .firstMatch(widget.task.scheduledTime);
    if (match != null) {
      _time =
          TimeOfDay(hour: int.parse(match[1]!), minute: int.parse(match[2]!));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_time == null) {
      setState(() => _error = '請選擇任務時間。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.updateTask(
      taskId: widget.task.id,
      title: _title.text,
      description: _description.text,
      scheduledTime:
          '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.errorMessage ?? '任務還沒儲存成功，請稍後再試一次。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('修改今日任務',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  maxLength: 200,
                  decoration: const InputDecoration(
                      labelText: '任務內容', border: OutlineInputBorder()),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '請填寫任務內容。' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  enabled: !_saving,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: '備註', border: OutlineInputBorder()),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(_time?.format(context) ?? '選擇時間'),
                  onPressed: _saving
                      ? null
                      : () async {
                          final time = await showTimePicker(
                              context: context,
                              initialTime:
                                  _time ?? const TimeOfDay(hour: 9, minute: 0));
                          if (mounted && time != null) {
                            setState(() => _time = time);
                          }
                        },
                ),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 18)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '正在儲存' : '儲存任務')),
                TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceGuidanceBanner extends StatelessWidget {
  const _VoiceGuidanceBanner({this.taskLabel});

  final String? taskLabel;

  @override
  Widget build(BuildContext context) {
    final label = taskLabel == null || taskLabel!.isEmpty ? '這項任務' : taskLabel!;
    return Semantics(
      label: '語音任務引導',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFDBEAFE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2563EB), width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.record_voice_over,
                color: Color(0xFF1D4ED8), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '我聽到你完成$label。請按下方「$label」的拍照完成，再拍一張照片，我會幫你送出確認。',
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('再試一次', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }
}
