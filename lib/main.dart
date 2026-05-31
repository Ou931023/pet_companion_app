import 'package:flutter/material.dart';

import 'app.dart';
import 'services/auth/firebase_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // CR-0006 Batch 4a：嘗試初始化 Firebase，但**初始化失敗不可 crash**。
  // 缺 GoogleService-Info.plist / google-services.json 或原生設定未完成時，
  // 這個呼叫只會把 Firebase 標記為不可用，App 照常啟動並可用 Demo 登入。
  await FirebaseInitializer.instance.ensureInitialized();
  runApp(const PetCompanionApp());
}
