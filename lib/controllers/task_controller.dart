import 'package:flutter/material.dart';

import '../models/care_task.dart';
import 'profile_controller.dart';

class TaskController extends ChangeNotifier {
  TaskController(this.profileController) {
    _syncFromProfile();
    profileController.addListener(_onProfileChanged);
  }

  final ProfileController profileController;
  List<CareTask> _tasks = const [];

  List<CareTask> get tasks => _tasks;
  int get completedCount => _tasks.where((t) => t.completed).length;
  bool get hasCheckedInToday =>
      _tasks.firstWhere((task) => task.id == 'dailyCheckIn').completed;

  void _syncFromProfile() {
    final state = profileController.taskState;
    _tasks = [
      CareTask(
        id: 'dailyCheckIn',
        title: '每日簽到',
        rewardCoins: 10,
        rewardBond: 3,
        completed: state['dailyCheckIn'] ?? false,
      ),
      CareTask(
        id: 'drinkWater',
        title: '喝水任務',
        rewardCoins: 5,
        rewardBond: 2,
        completed: state['drinkWater'] ?? false,
      ),
      CareTask(
        id: 'eatMeal',
        title: '吃飯任務',
        rewardCoins: 6,
        rewardBond: 2,
        completed: state['eatMeal'] ?? false,
      ),
      CareTask(
        id: 'moodReport',
        title: '心情回報',
        rewardCoins: 5,
        rewardBond: 2,
        completed: state['moodReport'] ?? false,
      ),
      CareTask(
        id: 'restReminder',
        title: '休息提醒',
        rewardCoins: 4,
        rewardBond: 1,
        completed: state['restReminder'] ?? false,
      ),
    ];
  }

  void _onProfileChanged() {
    _syncFromProfile();
    notifyListeners();
  }

  Future<bool> completeTaskById(String taskId) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return false;
    if (_tasks[index].completed) return false;
    _tasks = [..._tasks]..[index] = _tasks[index].copyWith(completed: true);
    final taskMap = {for (final task in _tasks) task.id: task.completed};
    await profileController.updateStats(
      coins: profileController.coins + _tasks[index].rewardCoins,
      bond: profileController.bond + _tasks[index].rewardBond,
      taskCompletionState: taskMap,
      checkInDate: taskId == 'dailyCheckIn'
          ? DateTime.now().toIso8601String().split('T').first
          : profileController.checkInDate,
    );
    notifyListeners();
    return true;
  }

  bool isTaskCompleted(String taskId) {
    final task = _tasks.where((task) => task.id == taskId);
    return task.isNotEmpty && task.first.completed;
  }

  @override
  void dispose() {
    profileController.removeListener(_onProfileChanged);
    super.dispose();
  }
}
