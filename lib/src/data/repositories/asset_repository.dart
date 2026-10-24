import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/formatters.dart';
import '../models/models.dart';

/// スナップショット編集中の 1 行。まだ DB に確定していない状態を表す。
class HoldingDraft {
  HoldingDraft({
    this.recordId,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    this.source = RecordSource.manual,
  });

  int? recordId;
  int accountId;
  int categoryId;
  int amount;
  RecordSource source;

  HoldingDraft copy() => HoldingDraft(
    recordId: recordId,
    accountId: accountId,
    categoryId: categoryId,
    amount: amount,
    source: source,
  );
}

/// 資産データへのすべてのアクセス経路。
class AssetRepository {
  AssetRepository(this._db);

  final Database _db;

  // ---------------------------------------------------------------- カテゴリ

  Future<List<AssetCategory>> listCategories() async {
    final rows = await _db.query('categories', orderBy: 'sort_order, id');
    return rows.map(AssetCategory.fromRow).toList();
  }

  Future<int> upsertCategory(AssetCategory category) async {
    if (category.id == null) {
      final maxOrder =
          Sqflite.firstIntValue(
            await _db.rawQuery('SELECT MAX(sort_order) FROM categories'),
          ) ??
          0;
      return _db.insert('categories', {
        ...category.toRow(),
        'sort_order': maxOrder + 1,
      });
    }
    await _db.update(
      'categories',
      category.toRow(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    return category.id!;
  }

  /// 使用中のカテゴリは削除できない（記録の孤児化を防ぐ）。
  Future<bool> deleteCategory(int id) async {
    final used =
        Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM asset_records WHERE category_id = ?',
            [id],
          ),
        ) ??
        0;
    if (used > 0) return false;
    await _db.delete('categories', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  // ------------------------------------------------------------------ 口座

  Future<List<Account>> listAccounts() async {
    final rows = await _db.query('accounts', orderBy: 'sort_order, id');
    return rows.map(Account.fromRow).toList();
  }

  Future<int> countAccounts() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM accounts'),
      ) ??
      0;

  Future<int> upsertAccount(Account account) async {
    if (account.id == null) {
      final maxOrder =
          Sqflite.firstIntValue(
            await _db.rawQuery('SELECT MAX(sort_order) FROM accounts'),
          ) ??
          0;
      return _db.insert('accounts', {
        ...account.toRow(),
        'sort_order': maxOrder + 1,
      });
    }
    await _db.update(
      'accounts',
      account.toRow(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
    return account.id!;
  }

  /// 口座を削除すると、その口座の記録もすべて削除される（ON DELETE CASCADE）。
  Future<void> deleteAccount(int id) async {
    await _db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countRecordsForAccount(int accountId) async =>
      Sqflite.firstIntValue(
        await _db.rawQuery(
          'SELECT COUNT(*) FROM asset_records WHERE account_id = ?',
          [accountId],
        ),
      ) ??
      0;

  // ------------------------------------------------------------ スナップショット

  /// 記録が存在する日付を新しい順に返す。
  Future<List<DateTime>> listSnapshotDates() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT recorded_on FROM asset_records ORDER BY recorded_on DESC',
    );
    return rows
        .map((r) => Fmt.parseIsoDate(r['recorded_on'] as String))
        .toList();
  }

  Future<AssetSnapshot?> loadSnapshot(DateTime date) async {
    final rows = await _db.query(
      'asset_records',
      where: 'recorded_on = ?',
      whereArgs: [Fmt.isoDate(date)],
    );
    if (rows.isEmpty) return null;
    return _hydrate(dateOnly(date), rows, await loadContribution(date));
  }

  Future<AssetSnapshot?> latestSnapshot() async {
    final dates = await listSnapshotDates();
    if (dates.isEmpty) return null;
    return loadSnapshot(dates.first);
  }

  /// [before] より前で最も新しいスナップショット。「前回データを複製」の元になる。
  Future<AssetSnapshot?> latestSnapshotBefore(DateTime before) async {
    final rows = await _db.rawQuery(
      'SELECT recorded_on FROM asset_records WHERE recorded_on < ? '
      'ORDER BY recorded_on DESC LIMIT 1',
      [Fmt.isoDate(before)],
    );
    if (rows.isEmpty) return null;
    return loadSnapshot(Fmt.parseIsoDate(rows.first['recorded_on'] as String));
  }

  /// その日付の入金額。未登録なら 0。
  Future<int> loadContribution(DateTime date) async {
    final rows = await _db.query(
      'snapshot_meta',
      where: 'recorded_on = ?',
      whereArgs: [Fmt.isoDate(date)],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['contribution'] as num?)?.toInt() ?? 0;
  }

  /// その日付の記録をまとめて置き換える。金額 0 の行は保存しない。
  Future<void> saveSnapshot(
    DateTime date,
    List<HoldingDraft> drafts, {
    int contribution = 0,
  }) async {
    final iso = Fmt.isoDate(date);
    await _db.transaction((txn) async {
      await txn.delete(
        'asset_records',
        where: 'recorded_on = ?',
        whereArgs: [iso],
      );
      for (final draft in drafts) {
        if (draft.amount == 0) continue;
        await txn.insert('asset_records', {
          'account_id': draft.accountId,
          'category_id': draft.categoryId,
          'recorded_on': iso,
          'amount': draft.amount,
          'source': draft.source.name,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      if (contribution == 0) {
        await txn.delete(
          'snapshot_meta',
          where: 'recorded_on = ?',
          whereArgs: [iso],
        );
      } else {
        await txn.insert('snapshot_meta', {
          'recorded_on': iso,
          'contribution': contribution,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteSnapshot(DateTime date) async {
    final iso = Fmt.isoDate(date);
    await _db.transaction((txn) async {
      await txn.delete(
        'asset_records',
        where: 'recorded_on = ?',
        whereArgs: [iso],
      );
      await txn.delete(
        'snapshot_meta',
        where: 'recorded_on = ?',
        whereArgs: [iso],
      );
    });
  }

  // ------------------------------------------------------------------ 推移

  /// 月別の推移。各月で「その月の最新の記録日」を代表値に採用する。
  ///
  /// 年別集計は 3 年目まで月別と同じ形にしかならないため用意していない。
  Future<List<TrendPoint>> trend() async {
    final rows = await _db.rawQuery(
      'SELECT recorded_on, category_id, SUM(amount) AS total '
      'FROM asset_records GROUP BY recorded_on, category_id '
      'ORDER BY recorded_on',
    );
    if (rows.isEmpty) return const [];

    // 月キー -> 採用する記録日
    final representative = <DateTime, DateTime>{};
    for (final row in rows) {
      final date = Fmt.parseIsoDate(row['recorded_on'] as String);
      final key = monthStart(date);
      final current = representative[key];
      if (current == null || date.isAfter(current)) {
        representative[key] = date;
      }
    }

    final byPeriod = <DateTime, Map<int, int>>{};
    for (final row in rows) {
      final date = Fmt.parseIsoDate(row['recorded_on'] as String);
      final key = monthStart(date);
      if (representative[key] != date) continue;
      final bucket = byPeriod.putIfAbsent(key, () => <int, int>{});
      final categoryId = row['category_id'] as int;
      bucket[categoryId] =
          (bucket[categoryId] ?? 0) + (row['total'] as num).toInt();
    }

    // 入金額は月内のすべての記録日ぶんを合算する
    // （月に複数回記録していても入金は取りこぼさない）。
    final contributions = <DateTime, int>{};
    for (final row in await _db.query('snapshot_meta')) {
      final date = Fmt.parseIsoDate(row['recorded_on'] as String);
      final key = monthStart(date);
      contributions[key] =
          (contributions[key] ?? 0) +
          ((row['contribution'] as num?)?.toInt() ?? 0);
    }

    final periods = byPeriod.keys.toList()..sort();
    return attachPrincipal([
      for (final period in periods)
        TrendPoint(
          period: period,
          total: byPeriod[period]!.values.fold(0, (a, b) => a + b),
          byCategory: Map.unmodifiable(byPeriod[period]!),
          contribution: contributions[period] ?? 0,
        ),
    ]);
  }

  // ------------------------------------------------------------------ 設定

  Future<Map<String, String>> loadSettings() async {
    final rows = await _db.query('app_settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------- バックアップ / 全削除

  /// バックアップ用のフルダンプ。
  Future<Map<String, List<Map<String, Object?>>>> exportAll() async => {
    'categories': await _db.query('categories', orderBy: 'id'),
    'accounts': await _db.query('accounts', orderBy: 'id'),
    'asset_records': await _db.query('asset_records', orderBy: 'id'),
    'snapshot_meta': await _db.query('snapshot_meta', orderBy: 'recorded_on'),
    'app_settings': await _db.query('app_settings'),
  };

  /// 復元。既存データをすべて置き換える。
  Future<void> importAll(Map<String, List<Map<String, Object?>>> data) async {
    await _db.transaction((txn) async {
      await txn.delete('asset_records');
      await txn.delete('snapshot_meta');
      await txn.delete('accounts');
      await txn.delete('categories');
      await txn.delete('app_settings');

      for (final table in const [
        'categories',
        'accounts',
        'asset_records',
        'snapshot_meta',
        'app_settings',
      ]) {
        for (final row in data[table] ?? const <Map<String, Object?>>[]) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> deleteEverything() async {
    await _db.transaction((txn) async {
      await txn.delete('asset_records');
      await txn.delete('snapshot_meta');
      await txn.delete('accounts');
      await txn.delete('app_settings');
    });
  }

  // ---------------------------------------------------------------- internal

  Future<AssetSnapshot> _hydrate(
    DateTime date,
    List<Map<String, Object?>> rows,
    int contribution,
  ) async {
    final accounts = {for (final a in await listAccounts()) a.id!: a};
    final categories = {for (final c in await listCategories()) c.id!: c};

    final holdings = <Holding>[];
    for (final row in rows) {
      final record = AssetRecord.fromRow(row);
      final account = accounts[record.accountId];
      final category = categories[record.categoryId];
      if (account == null || category == null) continue;
      holdings.add(
        Holding(record: record, account: account, category: category),
      );
    }
    holdings.sort((a, b) => b.amount.compareTo(a.amount));
    return AssetSnapshot(
      date: date,
      holdings: holdings,
      contribution: contribution,
    );
  }
}
