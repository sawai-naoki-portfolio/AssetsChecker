import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app.dart';
import 'src/security/screen_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 端末ローカルで完結するアプリのため、ネットワーク初期化は一切行わない。
  await initializeDateFormatting('ja_JP');
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // タスク切り替え時の遮蔽はできる限り早い段階で有効化する。
  await ScreenGuard.enable();

  runApp(const ProviderScope(child: PrivacyAssetCheckerApp()));
}
