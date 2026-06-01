import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/models/check_in_record.dart';
import 'package:pet_companion_app/models/inventory_item.dart';
import 'package:pet_companion_app/models/reminder.dart';
import 'package:pet_companion_app/services/care_alert_storage_service.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CR-0012 Batch A：簽到 / 背包 / 本地 Care Alert / 提醒的本機快取依 elderId 隔離。
// 驗證：A 的資料不會出現在 B；Demo（default_user）沿用原本全域 key 不被破壞。

InventoryItem _item(String id, {int quantity = 1}) {
  return InventoryItem(
    itemId: id,
    name: '蘋果',
    emoji: '🍎',
    quantity: quantity,
    category: 'food',
    intimacyDelta: 1,
    fullnessDelta: 1,
    moodDelta: 1,
    isReviveItem: false,
  );
}

CareAlert _alert(String id) {
  return CareAlert(
    id: id,
    createdAt: DateTime.parse('2026-05-28T16:30:00.000Z'),
    riskLevel: CareAlertRiskLevel.high,
    category: CareAlertCategory.other,
    triggerSummary: '需要關心的狀況',
    transcriptSnippet: '我今天有點不舒服。',
    source: 'companion_analysis',
    isRead: false,
  );
}

Reminder _reminder(String id) {
  return Reminder(
    id: id,
    title: '吃藥',
    hour: 20,
    minute: 0,
    repeatType: 'daily',
    note: '',
    enabled: true,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CheckIn 依帳號隔離：A 的簽到不出現在 B，Demo 沿用全域', () async {
    final storage = CheckInStorageService();

    storage.setUserId('elder-A');
    await storage.save(const CheckInRecord(
      checkInDates: {'2026-06-01'},
      lastCheckInDate: '2026-06-01',
    ));

    // B 第一次 → 空白，看不到 A 的簽到。
    storage.setUserId('elder-B');
    final b = await storage.load();
    expect(b.checkInDates, isEmpty);
    expect(b.lastCheckInDate, isNull);

    // 切回 A → 還在。
    storage.setUserId('elder-A');
    final a = await storage.load();
    expect(a.checkInDates, contains('2026-06-01'));
    expect(a.lastCheckInDate, '2026-06-01');

    // Demo / 未登入（default_user）→ 也是獨立空白。
    storage.setUserId('default_user');
    expect((await storage.load()).checkInDates, isEmpty);
  });

  test('Inventory 依帳號隔離：A 的背包不出現在 B', () async {
    final storage = InventoryStorageService();

    storage.setUserId('elder-A');
    await storage.save([_item('apple', quantity: 3)]);

    storage.setUserId('elder-B');
    expect(await storage.load(), isEmpty);

    storage.setUserId('elder-A');
    final a = await storage.load();
    expect(a, hasLength(1));
    expect(a.first.itemId, 'apple');
    expect(a.first.quantity, 3);

    storage.setUserId(null); // 未登入 → default_user
    expect(await storage.load(), isEmpty);
  });

  test('CareAlert 本地快取依帳號隔離：A 的 alert 不出現在 B', () async {
    final storage = CareAlertStorageService();

    storage.setUserId('elder-A');
    await storage.save([_alert('a1')]);

    storage.setUserId('elder-B');
    expect(await storage.load(), isEmpty);

    storage.setUserId('elder-A');
    final a = await storage.load();
    expect(a, hasLength(1));
    expect(a.first.id, 'a1');
  });

  test('Reminder 依帳號隔離：A 的提醒不出現在 B', () async {
    final storage = ReminderService();

    storage.setUserId('elder-A');
    await storage.save([_reminder('r1')]);

    storage.setUserId('elder-B');
    expect(await storage.load(), isEmpty);

    storage.setUserId('elder-A');
    final a = await storage.load();
    expect(a, hasLength(1));
    expect(a.first.id, 'r1');
  });

  test('Demo default_user 既有全域資料不被正式帳號破壞', () async {
    // 先以 Demo（全域 key）寫入資料。
    final checkIn = CheckInStorageService();
    final inventory = InventoryStorageService();
    final reminder = ReminderService();
    final careAlert = CareAlertStorageService();

    // default 即 default_user。
    await checkIn.save(const CheckInRecord(
      checkInDates: {'2026-05-30'},
      lastCheckInDate: '2026-05-30',
    ));
    await inventory.save([_item('demo-item')]);
    await reminder.save([_reminder('demo-r')]);
    await careAlert.save([_alert('demo-a')]);

    // 正式帳號登入並寫入自己的資料。
    checkIn.setUserId('elder-A');
    inventory.setUserId('elder-A');
    reminder.setUserId('elder-A');
    careAlert.setUserId('elder-A');
    await checkIn.save(const CheckInRecord(
      checkInDates: {'2026-06-01'},
      lastCheckInDate: '2026-06-01',
    ));
    await inventory.save([_item('a-item')]);
    await reminder.save([_reminder('a-r')]);
    await careAlert.save([_alert('a-a')]);

    // 登出回 Demo（default_user）→ 仍是原本的 Demo 資料，沒有被 A 蓋掉、也看不到 A。
    checkIn.setUserId('default_user');
    inventory.setUserId('default_user');
    reminder.setUserId('default_user');
    careAlert.setUserId('default_user');

    expect((await checkIn.load()).checkInDates, contains('2026-05-30'));
    expect((await inventory.load()).first.itemId, 'demo-item');
    expect((await reminder.load()).first.id, 'demo-r');
    expect((await careAlert.load()).first.id, 'demo-a');
  });
}
