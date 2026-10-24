import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:privacy_asset_checker/src/core/formatters.dart';
import 'package:privacy_asset_checker/src/data/models/models.dart';

AssetCategory _category(int id, String name) =>
    AssetCategory(id: id, name: name, color: Color(0xFF000000 + id));

Account _account(int id, String name) =>
    Account(id: id, name: name, type: AccountType.specific);

Holding _holding({
  required Account account,
  required AssetCategory category,
  required int amount,
}) => Holding(
  record: AssetRecord(
    accountId: account.id!,
    categoryId: category.id!,
    recordedOn: DateTime(2026, 7, 28),
    amount: amount,
  ),
  account: account,
  category: category,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja_JP');
  });

  group('Fmt', () {
    test('円は 3 桁区切りで表示する', () {
      expect(Fmt.yen(1234567), '¥1,234,567');
      expect(Fmt.yen(0), '¥0');
    });

    test('符号付き差分', () {
      expect(Fmt.signedYen(12300), '+¥12,300');
      expect(Fmt.signedYen(-4500), '-¥4,500');
      expect(Fmt.signedYen(0), '±¥0');
    });

    test('軸ラベル向けの短縮表記', () {
      expect(Fmt.compactYen(5000), '5,000');
      expect(Fmt.compactYen(3400000), '340万');
      expect(Fmt.compactYen(120000000), '1.2億');
      expect(Fmt.compactYen(-3400000), '-340万');
    });

    test('構成比', () {
      expect(Fmt.percent(0.1234), '12.3%');
    });

    test('ISO8601 日付で保存し、そのまま読み戻せる', () {
      final date = DateTime(2026, 7, 28);
      expect(Fmt.isoDate(date), '2026-07-28');
      expect(Fmt.parseIsoDate('2026-07-28'), date);
    });
  });

  group('dateOnly / monthStart / yearStart', () {
    test('時刻成分を落とす', () {
      expect(dateOnly(DateTime(2026, 7, 28, 13, 45)), DateTime(2026, 7, 28));
      expect(monthStart(DateTime(2026, 7, 28)), DateTime(2026, 7));
      expect(yearStart(DateTime(2026, 7, 28)), DateTime(2026));
    });
  });

  group('AssetSnapshot', () {
    final sbi = _account(1, 'SBI証券');
    final rakuten = _account(2, '楽天証券');
    final jp = _category(1, '日本株');
    final us = _category(2, '米国株');

    final snapshot = AssetSnapshot(
      date: DateTime(2026, 7, 28),
      holdings: [
        _holding(account: sbi, category: jp, amount: 300000),
        _holding(account: sbi, category: us, amount: 700000),
        _holding(account: rakuten, category: jp, amount: 200000),
      ],
    );

    test('総額を合計する', () {
      expect(snapshot.total, 1200000);
    });

    test('カテゴリ別に合算し、金額の降順で返す', () {
      final byCategory = snapshot.byCategory();
      expect(byCategory.map((s) => s.category.name), ['米国株', '日本株']);
      expect(byCategory.first.amount, 700000);
      expect(byCategory.last.amount, 500000);
    });

    test('カテゴリ構成比', () {
      final us = snapshot.byCategory().first;
      expect(us.ratioOf(snapshot.total), closeTo(0.5833, 0.0001));
    });

    test('口座別に合算し、内訳を保持する', () {
      final byAccount = snapshot.byAccount();
      expect(byAccount.map((s) => s.account.name), ['SBI証券', '楽天証券']);
      expect(byAccount.first.amount, 1000000);
      expect(byAccount.first.holdings.length, 2);
      expect(byAccount.last.holdings.length, 1);
    });

    test('記録がなければ空とみなす', () {
      final empty = AssetSnapshot(date: DateTime(2026, 7, 28), holdings: const []);
      expect(empty.isEmpty, isTrue);
      expect(empty.total, 0);
      expect(empty.byCategory(), isEmpty);
    });
  });

  group('モデルの行変換', () {
    test('Account は往復できる', () {
      const account = Account(
        id: 7,
        name: 'SBI証券',
        type: AccountType.nisaGrowth,
        note: 'メモ',
        sortOrder: 3,
      );
      final restored = Account.fromRow(account.toRow());

      expect(restored.id, 7);
      expect(restored.name, 'SBI証券');
      expect(restored.type, AccountType.nisaGrowth);
      expect(restored.note, 'メモ');
      expect(restored.sortOrder, 3);
    });

    test('AssetRecord は ISO8601 日付で保存される', () {
      final record = AssetRecord(
        id: 3,
        accountId: 1,
        categoryId: 2,
        recordedOn: DateTime(2026, 7, 28),
        amount: 500,
        source: RecordSource.csv,
      );
      final row = record.toRow();

      expect(row['recorded_on'], '2026-07-28');
      expect(row['source'], 'csv');
      expect(AssetRecord.fromRow(row).recordedOn, DateTime(2026, 7, 28));
      expect(AssetRecord.fromRow(row).source, RecordSource.csv);
    });

    test('未知の区分は「その他」に丸める', () {
      expect(AccountType.fromId('unknown-type'), AccountType.other);
      expect(RecordSource.fromId(null), RecordSource.manual);
    });
  });
}
