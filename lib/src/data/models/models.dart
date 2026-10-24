import 'package:flutter/material.dart';

import '../../core/formatters.dart';

/// 口座区分。税制上の扱いが違うものは別口座として持つ。
enum AccountType {
  specific('特定口座'),
  general('一般口座'),
  nisaGrowth('NISA 成長投資枠'),
  nisaTsumitate('NISA つみたて投資枠'),
  ideco('iDeCo'),
  bank('銀行口座'),
  crypto('暗号資産取引所'),
  other('その他');

  const AccountType(this.label);

  final String label;

  static AccountType fromId(String? id) => AccountType.values.firstWhere(
    (e) => e.name == id,
    orElse: () => AccountType.other,
  );
}

/// 保有口座（SBI証券・楽天銀行など）。
@immutable
class Account {
  const Account({
    this.id,
    required this.name,
    required this.type,
    this.note = '',
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final AccountType type;
  final String note;
  final int sortOrder;

  String get displayName => '$name・${type.label}';

  Account copyWith({
    int? id,
    String? name,
    AccountType? type,
    String? note,
    int? sortOrder,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    note: note ?? this.note,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'account_type': type.name,
    'note': note,
    'sort_order': sortOrder,
  };

  factory Account.fromRow(Map<String, Object?> row) => Account(
    id: row['id'] as int?,
    name: row['name'] as String,
    type: AccountType.fromId(row['account_type'] as String?),
    note: (row['note'] as String?) ?? '',
    sortOrder: (row['sort_order'] as int?) ?? 0,
  );
}

/// 資産カテゴリ（日本株・米国株など）。グラフの色を保持する。
///
/// 色はパレットから自動で割り当てる。ユーザーに色を選ばせても
/// グラフの読みやすさが上がらないため、編集手段は用意していない。
@immutable
class AssetCategory {
  const AssetCategory({
    this.id,
    required this.name,
    required this.color,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final Color color;
  final int sortOrder;

  AssetCategory copyWith({
    int? id,
    String? name,
    Color? color,
    int? sortOrder,
  }) => AssetCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'color': color.toARGB32(),
    'sort_order': sortOrder,
  };

  factory AssetCategory.fromRow(Map<String, Object?> row) => AssetCategory(
    id: row['id'] as int?,
    name: row['name'] as String,
    color: Color(row['color'] as int),
    sortOrder: (row['sort_order'] as int?) ?? 0,
  );
}

/// 記録の入力元。CSV 由来か手入力かを区別してバッジ表示に使う。
enum RecordSource {
  manual('手入力'),
  duplicated('複製'),
  csv('CSV');

  const RecordSource(this.label);

  final String label;

  static RecordSource fromId(String? id) => RecordSource.values.firstWhere(
    (e) => e.name == id,
    orElse: () => RecordSource.manual,
  );
}

/// ある日付・ある口座・あるカテゴリの評価額。
@immutable
class AssetRecord {
  const AssetRecord({
    this.id,
    required this.accountId,
    required this.categoryId,
    required this.recordedOn,
    required this.amount,
    this.source = RecordSource.manual,
  });

  final int? id;
  final int accountId;
  final int categoryId;
  final DateTime recordedOn;
  final int amount;
  final RecordSource source;

  AssetRecord copyWith({
    int? id,
    int? accountId,
    int? categoryId,
    DateTime? recordedOn,
    int? amount,
    RecordSource? source,
  }) => AssetRecord(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    recordedOn: recordedOn ?? this.recordedOn,
    amount: amount ?? this.amount,
    source: source ?? this.source,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'account_id': accountId,
    'category_id': categoryId,
    'recorded_on': Fmt.isoDate(recordedOn),
    'amount': amount,
    'source': source.name,
  };

  factory AssetRecord.fromRow(Map<String, Object?> row) => AssetRecord(
    id: row['id'] as int?,
    accountId: row['account_id'] as int,
    categoryId: row['category_id'] as int,
    recordedOn: Fmt.parseIsoDate(row['recorded_on'] as String),
    amount: (row['amount'] as num).toInt(),
    source: RecordSource.fromId(row['source'] as String?),
  );
}

/// 記録に口座・カテゴリを解決して付与した表示用モデル。
@immutable
class Holding {
  const Holding({
    required this.record,
    required this.account,
    required this.category,
  });

  final AssetRecord record;
  final Account account;
  final AssetCategory category;

  int get amount => record.amount;
}

/// ある日付時点の資産スナップショット。
@immutable
class AssetSnapshot {
  const AssetSnapshot({
    required this.date,
    required this.holdings,
    this.contribution = 0,
  });

  final DateTime date;
  final List<Holding> holdings;

  /// 前回の記録以降に入金した額。運用損益を切り出すために使う。
  final int contribution;

  bool get isEmpty => holdings.isEmpty;

  int get total => holdings.fold(0, (sum, h) => sum + h.amount);

  /// カテゴリ別合計（金額の降順）。
  List<CategorySlice> byCategory() {
    final map = <int, CategorySlice>{};
    for (final h in holdings) {
      final id = h.category.id!;
      final current = map[id];
      map[id] = CategorySlice(
        category: h.category,
        amount: (current?.amount ?? 0) + h.amount,
      );
    }
    final list = map.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  /// 口座別合計（金額の降順）。
  List<AccountSlice> byAccount() {
    final map = <int, AccountSlice>{};
    for (final h in holdings) {
      final id = h.account.id!;
      final current = map[id];
      map[id] = AccountSlice(
        account: h.account,
        amount: (current?.amount ?? 0) + h.amount,
        holdings: [...?current?.holdings, h],
      );
    }
    final list = map.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }
}

@immutable
class CategorySlice {
  const CategorySlice({required this.category, required this.amount});

  final AssetCategory category;
  final int amount;

  double ratioOf(int total) => total == 0 ? 0 : amount / total;
}

@immutable
class AccountSlice {
  const AccountSlice({
    required this.account,
    required this.amount,
    this.holdings = const [],
  });

  final Account account;
  final int amount;
  final List<Holding> holdings;

  double ratioOf(int total) => total == 0 ? 0 : amount / total;
}

/// 推移グラフの 1 点（月次）。
@immutable
class TrendPoint {
  const TrendPoint({
    required this.period,
    required this.total,
    required this.byCategory,
    this.contribution = 0,
    this.principal = 0,
  });

  /// 集計対象の月の 1 日。
  final DateTime period;

  /// その月の評価額合計。
  final int total;

  final Map<int, int> byCategory;

  /// その月に入金した額。
  final int contribution;

  /// 積み上げた元本（初回の評価額 + それ以降の入金累計）。
  final int principal;

  /// 運用によって増えた分。入金を記録していない期間は意味を持たない。
  int get gain => total - principal;
}

/// 各点に元本を積み上げる。
///
/// 最初の記録時点の評価額を元本の出発点とみなし、そこに入金を足していく。
/// アプリを使い始める前の損益は追えないが、使い始めて以降の
/// 「増えたのは入金のおかげか運用のおかげか」は正しく分離できる。
List<TrendPoint> attachPrincipal(List<TrendPoint> points) {
  if (points.isEmpty) return points;

  final result = <TrendPoint>[];
  var principal = points.first.total;

  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    if (i > 0) principal += point.contribution;
    result.add(
      TrendPoint(
        period: point.period,
        total: point.total,
        byCategory: point.byCategory,
        contribution: point.contribution,
        principal: principal,
      ),
    );
  }
  return result;
}

/// 入金を 1 度でも記録していれば元本ラインを表示する価値がある。
bool hasContributionData(List<TrendPoint> points) =>
    points.skip(1).any((p) => p.contribution != 0);
