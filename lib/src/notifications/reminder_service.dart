import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 毎月の入力リマインダー。
///
/// このアプリの価値は「毎月思い出してもらえるか」だけで決まる。
/// 忘れられた瞬間に 1 タップ複製も推移グラフも無価値になるため、
/// 通知はもっとも費用対効果の高い機能として最初に置いている。
///
/// スケジューリングは端末内で完結し、通信は一切発生しない。
class ReminderService {
  ReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int monthlyInputId = 1001;
  static const String _channelId = 'monthly_input';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// タイムゾーンとプラグインを初期化する。複数回呼んでも安全。
  Future<void> initialize() async {
    if (_ready || !isSupported) return;

    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (error) {
      // タイムゾーンが引けなくても UTC で動く。通知が出ないよりはまし。
      debugPrint('ReminderService: timezone lookup failed ($error)');
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // 権限は設定画面でユーザーが有効にしたときに明示的に求める。
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (error, stack) {
      debugPrint('ReminderService.initialize failed: $error\n$stack');
    }
  }

  /// 通知の許可を求める。許可されたら true。
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await initialize();

    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (error) {
      debugPrint('ReminderService.requestPermission failed: $error');
      return false;
    }
  }

  /// 毎月 [day] 日 [hour] 時に通知する。既存の予約は置き換えられる。
  ///
  /// 正確なアラーム権限（SCHEDULE_EXACT_ALARM）は要求しない。月次の
  /// リマインダーに分単位の精度は不要で、権限を増やす方が損だと判断した。
  Future<void> schedule({required int day, required int hour}) async {
    if (!isSupported) return;
    await initialize();
    if (!_ready) return;

    try {
      await _plugin.cancel(id: monthlyInputId);
      await _plugin.zonedSchedule(
        id: monthlyInputId,
        title: '今月の資産を記録しましょう',
        body: '前回のデータを 1 タップで複製できます。変わった金額だけ直せば完了です。',
        scheduledDate: _nextOccurrence(day: day, hour: hour),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '毎月の入力リマインダー',
            channelDescription: '資産を記録する日をお知らせします',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error, stack) {
      debugPrint('ReminderService.schedule failed: $error\n$stack');
    }
  }

  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await _plugin.cancel(id: monthlyInputId);
    } catch (error) {
      debugPrint('ReminderService.cancel failed: $error');
    }
  }

  /// 次に通知すべき日時。今月の指定日を過ぎていれば翌月にずらす。
  static tz.TZDateTime _nextOccurrence({
    required int day,
    required int hour,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    final safeDay = day.clamp(1, 28);
    var next = tz.TZDateTime(tz.local, now.year, now.month, safeDay, hour);
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(tz.local, now.year, now.month + 1, safeDay, hour);
    }
    return next;
  }
}
