import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../data/db/db_key_store.dart';
import '../data/models/models.dart';
import '../data/repositories/asset_repository.dart';

/// ドキュメント用のスクリーンショットを撮るためのデモデータ投入。
///
/// `kDebugMode` と `--dart-define=DEMO_MODE=true` の両方が揃ったときだけ動くため、
/// リリースビルドに混入することはない。
///
/// ```
/// flutter build apk --debug --dart-define=DEMO_MODE=true
/// flutter build apk --debug --dart-define=DEMO_MODE=true --dart-define=DEMO_PRO=true
/// ```
class DemoSeed {
  const DemoSeed._();

  static const bool _enabled = bool.fromEnvironment('DEMO_MODE');
  static const bool _pro = bool.fromEnvironment('DEMO_PRO');

  static bool get isActive => kDebugMode && _enabled;

  /// 空の DB のときだけデモデータを入れる。
  static Future<void> maybeSeed(
    AssetRepository repository,
    DbKeyStore keyStore,
  ) async {
    if (!isActive) return;

    await keyStore.setProUnlocked(_pro);

    if (await repository.countAccounts() > 0) return;

    final categories = {
      for (final c in await repository.listCategories()) c.name: c.id!,
    };

    final sbi = await repository.upsertAccount(
      const Account(name: 'SBI証券', type: AccountType.specific),
    );
    final rakuten = await repository.upsertAccount(
      const Account(name: '楽天証券', type: AccountType.nisaGrowth),
    );
    final bank = await repository.upsertAccount(
      const Account(name: '住信SBIネット銀行', type: AccountType.bank),
    );

    // 2025-12 から 2026-07 までの月末残高と、その月の入金額。
    // 相場の上下と積立を混ぜて、元本ラインが意味を持つ形にしている。
    const months = [
      (2025, 12, 1820000, 2240000, 1450000, 380000, 920000, 0),
      (2026, 1, 1795000, 2395000, 1512000, 380000, 880000, 100000),
      (2026, 2, 1910000, 2468000, 1558000, 382000, 940000, 100000),
      (2026, 3, 1868000, 2302000, 1495000, 382000, 1010000, 100000),
      (2026, 4, 1952000, 2540000, 1601000, 385000, 975000, 100000),
      (2026, 5, 2015000, 2712000, 1664000, 385000, 1040000, 150000),
      (2026, 6, 1988000, 2845000, 1702000, 388000, 1115000, 100000),
      (2026, 7, 2104000, 3012000, 1776000, 388000, 1180000, 100000),
    ];

    for (final (year, month, jp, us, fund, bond, cash, contribution)
        in months) {
      final date = dateOnly(DateTime(year, month, 28));
      await repository.saveSnapshot(
        date,
        [
          HoldingDraft(
            accountId: sbi,
            categoryId: categories['日本株']!,
            amount: jp,
          ),
          HoldingDraft(
            accountId: sbi,
            categoryId: categories['米国株']!,
            amount: us,
          ),
          HoldingDraft(
            accountId: rakuten,
            categoryId: categories['投資信託']!,
            amount: fund,
          ),
          HoldingDraft(
            accountId: rakuten,
            categoryId: categories['債券']!,
            amount: bond,
          ),
          HoldingDraft(
            accountId: bank,
            categoryId: categories['現金・預金']!,
            amount: cash,
          ),
        ],
        contribution: contribution,
      );
    }

    // 目標は Pro 機能なので、Pro のデモのときだけ設定する。
    if (_pro) {
      await repository.setSetting(SettingKeys.goalAmount, '30000000');
    }
    await repository.setSetting(SettingKeys.reminderEnabled, '1');
  }
}
