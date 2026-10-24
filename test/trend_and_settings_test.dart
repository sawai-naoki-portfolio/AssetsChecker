import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_asset_checker/src/core/constants.dart';
import 'package:privacy_asset_checker/src/data/models/app_settings.dart';
import 'package:privacy_asset_checker/src/data/models/models.dart';
import 'package:privacy_asset_checker/src/features/trend/trend_page.dart';

TrendPoint _point(int month, int total, {int contribution = 0}) => TrendPoint(
  period: DateTime(2026, month),
  total: total,
  byCategory: const {},
  contribution: contribution,
);

void main() {
  group('attachPrincipal', () {
    test('初回の評価額を元本の出発点にする', () {
      final points = attachPrincipal([_point(1, 1000000)]);
      expect(points.single.principal, 1000000);
      expect(points.single.gain, 0);
    });

    test('入金を積み上げ、残りを運用損益として切り出す', () {
      final points = attachPrincipal([
        _point(1, 1000000),
        _point(2, 1200000, contribution: 100000),
        _point(3, 1450000, contribution: 100000),
      ]);

      expect(points.map((p) => p.principal), [1000000, 1100000, 1200000]);
      // 2 月は入金 10 万に対して 20 万増えたので、運用で 10 万
      expect(points[1].gain, 100000);
      // 3 月は累計入金 20 万に対して 45 万増えたので、運用で 25 万
      expect(points[2].gain, 250000);
    });

    test('相場が下がれば運用損益はマイナスになる', () {
      final points = attachPrincipal([
        _point(1, 1000000),
        _point(2, 1050000, contribution: 100000),
      ]);
      expect(points.last.gain, -50000);
    });

    test('初回月の入金は元本に二重計上しない', () {
      final points = attachPrincipal([
        _point(1, 1000000, contribution: 500000),
        _point(2, 1000000),
      ]);
      expect(points.first.principal, 1000000);
      expect(points.last.principal, 1000000);
    });

    test('空のリストはそのまま返す', () {
      expect(attachPrincipal(const []), isEmpty);
    });
  });

  group('hasContributionData', () {
    test('2 件目以降に入金があれば true', () {
      expect(
        hasContributionData([
          _point(1, 100),
          _point(2, 200, contribution: 50),
        ]),
        isTrue,
      );
    });

    test('初回の入金だけでは元本ラインを描く意味がない', () {
      expect(
        hasContributionData([
          _point(1, 100, contribution: 50),
          _point(2, 200),
        ]),
        isFalse,
      );
    });
  });

  group('applyFreeTrendLimit', () {
    final points = [
      for (var m = 1; m <= 8; m++) _point(m, m * 100000),
    ];

    test('Pro は全期間を返す', () {
      expect(applyFreeTrendLimit(points, isPro: true).length, 8);
    });

    test('Free は直近 3 ヶ月に絞る', () {
      final limited = applyFreeTrendLimit(points, isPro: false);
      expect(limited.length, FreePlanLimits.trendMonths);
      expect(limited.last.period, DateTime(2026, 8));
      expect(limited.first.period, DateTime(2026, 6));
    });

    test('データが少ないときは全部残す', () {
      final few = [_point(7, 100), _point(8, 200)];
      expect(applyFreeTrendLimit(few, isPro: false).length, 2);
    });
  });

  group('evaluateBackupStatus', () {
    final now = DateTime(2026, 7, 28);

    test('記録がなければ督促しない', () {
      expect(
        evaluateBackupStatus(
          lastBackupAt: null,
          hasRecords: false,
          now: now,
        ),
        BackupStatus.notNeeded,
      );
    });

    test('記録があるのにバックアップがなければ警告する', () {
      final status = evaluateBackupStatus(
        lastBackupAt: null,
        hasRecords: true,
        now: now,
      );
      expect(status, BackupStatus.never);
      expect(status.shouldWarn, isTrue);
    });

    test('$kBackupReminderDays 日以上経つと警告する', () {
      expect(
        evaluateBackupStatus(
          lastBackupAt: now.subtract(const Duration(days: 31)),
          hasRecords: true,
          now: now,
        ),
        BackupStatus.stale,
      );
    });

    test('最近取っていれば警告しない', () {
      final status = evaluateBackupStatus(
        lastBackupAt: now.subtract(const Duration(days: 3)),
        hasRecords: true,
        now: now,
      );
      expect(status, BackupStatus.ok);
      expect(status.shouldWarn, isFalse);
    });
  });

  group('AppSettings', () {
    test('未設定なら安全側の既定値になる', () {
      const settings = AppSettings();
      expect(settings.biometricLock, isTrue);
      expect(settings.blockScreenshot, isTrue);
      expect(settings.reminderEnabled, isFalse);
      expect(settings.hasGoal, isFalse);
    });

    test('空のマップから既定値を組み立てる', () {
      final settings = AppSettings.fromMap(const {});
      expect(settings.biometricLock, isTrue);
      expect(settings.reminderDay, ReminderDefaults.day);
      expect(settings.reminderHour, ReminderDefaults.hour);
    });

    test('保存済みの値を読み取る', () {
      final settings = AppSettings.fromMap({
        SettingKeys.biometricLock: '0',
        SettingKeys.reminderEnabled: '1',
        SettingKeys.reminderDay: '5',
        SettingKeys.reminderHour: '9',
        SettingKeys.goalAmount: '30000000',
        SettingKeys.lastBackupAt: '2026-07-01T00:00:00.000',
      });

      expect(settings.biometricLock, isFalse);
      expect(settings.reminderEnabled, isTrue);
      expect(settings.reminderDay, 5);
      expect(settings.reminderHour, 9);
      expect(settings.goalAmount, 30000000);
      expect(settings.hasGoal, isTrue);
      expect(settings.lastBackupAt, DateTime(2026, 7));
    });

    test('通知日は 1〜28 に丸める', () {
      expect(
        AppSettings.fromMap({SettingKeys.reminderDay: '31'}).reminderDay,
        28,
      );
      expect(
        AppSettings.fromMap({SettingKeys.reminderDay: '0'}).reminderDay,
        1,
      );
    });

    test('壊れた値は既定値に落とす', () {
      final settings = AppSettings.fromMap({
        SettingKeys.reminderHour: 'not-a-number',
        SettingKeys.lastBackupAt: 'broken',
      });
      expect(settings.reminderHour, ReminderDefaults.hour);
      expect(settings.lastBackupAt, isNull);
    });
  });
}
