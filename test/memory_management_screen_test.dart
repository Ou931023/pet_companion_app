import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/screens/memory_management_screen.dart';
import 'package:pet_companion_app/services/memory_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows empty state when there are no memories', (tester) async {
    await tester.pumpWidget(_host(_FakeMemoryService(memories: const [])));
    await tester.pumpAndSettle();

    expect(find.text('目前還沒有長期記憶，和寵物多聊聊後，牠會慢慢更了解你。'), findsOneWidget);
  });

  testWidgets('lists memories and archives one after confirmation',
      (tester) async {
    final service = _FakeMemoryService(memories: [
      {
        'id': 1,
        'memorySummary': '使用者喜歡聽台灣地方故事。',
        'memoryType': 'story_preference',
        'importance': 4,
        'createdAt': '2026-05-14T00:00:00.000Z',
        'useCount': 2,
      },
    ]);

    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    expect(find.text('使用者喜歡聽台灣地方故事。'), findsOneWidget);
    expect(find.text('故事偏好'), findsOneWidget);

    await tester.tap(find.text('忘記這筆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('忘記').last);
    await tester.pumpAndSettle();

    expect(service.archivedIds, contains(1));
    expect(find.text('使用者喜歡聽台灣地方故事。'), findsNothing);
  });

  testWidgets('shows an error when backend is unavailable', (tester) async {
    await tester.pumpWidget(_host(_FakeMemoryService(shouldThrow: true)));
    await tester.pumpAndSettle();

    expect(find.text('暫時無法讀取長期記憶，請稍後再試。'), findsOneWidget);
  });
}

Widget _host(MemoryService service) {
  return MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) => MemoryController(service),
      child: const MemoryManagementScreen(),
    ),
  );
}

class _FakeMemoryService extends MemoryService {
  _FakeMemoryService({
    this.memories = const [],
    this.shouldThrow = false,
  });

  List<Map<String, dynamic>> memories;
  final bool shouldThrow;
  final List<Object> archivedIds = [];

  @override
  Future<List<Map<String, dynamic>>> listMemories({
    required String userId,
  }) async {
    if (shouldThrow) throw Exception('offline');
    return List<Map<String, dynamic>>.from(memories);
  }

  @override
  Future<bool> archiveMemory({
    required String userId,
    required Object memoryId,
  }) async {
    archivedIds.add(memoryId);
    memories.removeWhere(
        (memory) => memory['id'].toString() == memoryId.toString());
    return true;
  }
}
