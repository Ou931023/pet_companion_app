import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/models/pet_status.dart';

/// CR-0088：PetController 短暫情緒狀態（showTransientState）行為。
void main() {
  test('showTransientState 設定 transientMode，到期後自動清除並通知', () async {
    final controller = PetController();
    var notified = 0;
    controller.addListener(() => notified++);

    expect(controller.transientMode, isNull);
    controller.showTransientState(
      PetMode.happy,
      duration: const Duration(milliseconds: 20),
    );
    expect(controller.transientMode, PetMode.happy);
    expect(notified, greaterThanOrEqualTo(1));

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.transientMode, isNull, reason: '到期應自動清除');
  });

  test('新的 transient 覆蓋舊的（不疊加）', () async {
    final controller = PetController();
    controller.showTransientState(PetMode.sad,
        duration: const Duration(milliseconds: 50));
    controller.showTransientState(PetMode.caring,
        duration: const Duration(milliseconds: 50));
    expect(controller.transientMode, PetMode.caring);
  });
}
