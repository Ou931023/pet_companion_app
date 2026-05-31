import 'package:flutter/material.dart';

import 'app.dart';
import 'services/auth/firebase_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // CR-0006 Batch 4a：嘗試初始化 Firebase，但**初始化失敗不可 crash**。
  // 缺 GoogleService-Info.plist / google-services.json 或原生設定未完成時，
  // 這個呼叫只會把 Firebase 標記為不可用，App 照常啟動並可用 Demo 登入。
  //
  // 另加 3 秒 timeout：萬一原生初始化在某些裝置/設定下卡住，也**保證不會卡住
  // 啟動而白屏**——時間到就先進畫面，Firebase 之後完成不影響 UI（登入是使用者
  // 互動後才用到，屆時多半已就緒）。
  await FirebaseInitializer.instance
      .ensureInitialized()
      .timeout(const Duration(seconds: 3), onTimeout: () => false);
  runApp(const PetCompanionApp());
}
