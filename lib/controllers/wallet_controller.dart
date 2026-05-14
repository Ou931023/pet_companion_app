import 'package:flutter/material.dart';

import 'profile_controller.dart';

class WalletController extends ChangeNotifier {
  WalletController(this.profileController);

  final ProfileController profileController;

  int get coins => profileController.coins;

  Future<bool> spendCoins(int amount) async {
    if (coins < amount) return false;
    await profileController.updateStats(coins: coins - amount);
    notifyListeners();
    return true;
  }

  Future<void> addCoins(int amount) async {
    await profileController.updateStats(coins: coins + amount);
    notifyListeners();
  }
}
