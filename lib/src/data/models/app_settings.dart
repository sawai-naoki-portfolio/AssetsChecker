import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

/// [app_settings] テーブルの内容を型付きで扱うためのラッパー。
@immutable
class AppSettings {
  const AppSettings({
    this.biometricLock = true,
    this.blockScreenshot = true,
    this.reminderEnabled = false,
    this.reminderDay = ReminderDefaults.day,
    this.reminderHour = ReminderDefaults.hour,
    this.goalAmount = 0,
    this.lastBackupAt,
  });

  final bool biometricLock;
  final bool blockScreenshot;

  final bool reminderEnabled;

  /// 1〜28。月末の日数差で通知が飛ばない月が出ないように上限を 28 にしている。
  final int reminderDay;
  final int reminderHour;

  /// 目標資産額（円）。0 なら未設定。
  final int goalAmount;

  final DateTime? lastBackupAt;

  bool get hasGoal => goalAmount > 0;

  factory AppSettings.fromMap(Map<String, String> map) {
    bool flag(String key, {required bool fallback}) {
      final value = map[key];
      if (value == null) return fallback;
      return value != '0';
    }

    int number(String key, int fallback) =>
        int.tryParse(map[key] ?? '') ?? fallback;

    return AppSettings(
      biometricLock: flag(SettingKeys.biometricLock, fallback: true),
      blockScreenshot: flag(SettingKeys.blockScreenshot, fallback: true),
      reminderEnabled: flag(SettingKeys.reminderEnabled, fallback: false),
      reminderDay: number(SettingKeys.reminderDay, ReminderDefaults.day)
          .clamp(1, 28),
      reminderHour: number(SettingKeys.reminderHour, ReminderDefaults.hour)
          .clamp(0, 23),
      goalAmount: number(SettingKeys.goalAmount, 0),
      lastBackupAt: DateTime.tryParse(map[SettingKeys.lastBackupAt] ?? ''),
    );
  }
}

/// バックアップの督促状態。
///
/// 端末内完結のアプリでは、端末を失うことが唯一かつ致命的なデータ喪失経路。
/// 記録があるのにバックアップがない状態は、はっきり警告する。
enum BackupStatus {
  /// 記録がまだないので督促しない。
  notNeeded,

  /// 一度もバックアップしていない。
  never,

  /// 前回から [kBackupReminderDays] 日以上経っている。
  stale,

  ok;

  bool get shouldWarn => this == never || this == stale;
}

BackupStatus evaluateBackupStatus({
  required DateTime? lastBackupAt,
  required bool hasRecords,
  DateTime? now,
}) {
  if (!hasRecords) return BackupStatus.notNeeded;
  if (lastBackupAt == null) return BackupStatus.never;
  final elapsed = (now ?? DateTime.now()).difference(lastBackupAt).inDays;
  return elapsed >= kBackupReminderDays ? BackupStatus.stale : BackupStatus.ok;
}
