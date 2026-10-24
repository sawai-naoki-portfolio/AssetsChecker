import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// マルチタスク画面・スクリーンショットからの情報漏えいを防ぐ。
///
/// 外部プラグインに頼らず、アプリ自身のネイティブコードで実装している
/// （`MainActivity.kt` / `AppDelegate.swift`）。
///
/// - Android: `FLAG_SECURE` でスクリーンショットと最近のタスクのプレビューを封じる。
///   スクリーンショット防止を切っても、API 33 以降では
///   `setRecentsScreenshotEnabled(false)` でタスク切り替え時の遮蔽だけは維持する。
/// - iOS: スクリーンショットを禁止する公式 API はないため、
///   アプリ切り替え時にブラーを重ねる遮蔽のみを行う。
class ScreenGuard {
  const ScreenGuard._();

  static const MethodChannel _channel = MethodChannel(
    'jp.privacyasset/screen_guard',
  );

  static bool _blockScreenshot = true;
  static bool _screenshotBlockSupported = false;

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// この OS でスクリーンショット防止まで行えるか（Android のみ true）。
  static bool get screenshotBlockSupported => _screenshotBlockSupported;

  static bool get blockScreenshot => _blockScreenshot;

  /// 遮蔽を有効化する。
  ///
  /// [blockScreenshot] が false でも、タスク切り替え時の遮蔽は維持される。
  static Future<void> enable({bool blockScreenshot = true}) async {
    _blockScreenshot = blockScreenshot;
    if (!isSupported) return;

    try {
      await _channel.invokeMethod<bool>('setObscureOnSwitch', true);
      final applied = await _channel.invokeMethod<bool>(
        'setSecure',
        blockScreenshot,
      );
      _screenshotBlockSupported = applied ?? false;
    } catch (error, stack) {
      // 遮蔽に失敗してもアプリは使えるべきなので、握りつぶしてログのみ残す。
      debugPrint('ScreenGuard failed: $error\n$stack');
    }
  }

  /// スクリーンショット防止のみを切り替える。
  static Future<void> setBlockScreenshot(bool value) =>
      enable(blockScreenshot: value);
}
