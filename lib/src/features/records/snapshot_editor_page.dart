import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/asset_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../accounts/account_edit_page.dart';
import '../purchase/paywall_page.dart';

/// 1 日付ぶんの資産をまとめて入力する画面。
///
/// 毎月の更新を数秒で終わらせることが最優先。前回の内訳をそのまま複製し、
/// 変わった金額だけ触れば済むようにしている。
class SnapshotEditorPage extends ConsumerStatefulWidget {
  const SnapshotEditorPage({super.key, this.initialDate});

  /// 既存の記録を開くときの日付。null なら新規作成。
  final DateTime? initialDate;

  @override
  ConsumerState<SnapshotEditorPage> createState() => _SnapshotEditorPageState();
}

class _EditorRow {
  _EditorRow({required this.key, required this.draft});

  final int key;
  final HoldingDraft draft;
}

class _SnapshotEditorPageState extends ConsumerState<SnapshotEditorPage> {
  late DateTime _date = dateOnly(widget.initialDate ?? DateTime.now());
  List<_EditorRow> _rows = [];
  int _contribution = 0;
  int _contributionFieldKey = 0;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _hasPrevious = false;
  int _keySeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int get _total => _rows.fold(0, (sum, row) => sum + row.draft.amount);

  Future<void> _load() async {
    setState(() => _loading = true);
    final repository = await ref.read(repositoryProvider.future);
    final existing = await repository.loadSnapshot(_date);
    final previous = await repository.latestSnapshotBefore(_date);
    if (!mounted) return;

    setState(() {
      _hasPrevious = previous != null;
      _contribution = existing?.contribution ?? 0;
      _contributionFieldKey++;
      _rows = [
        for (final holding in existing?.holdings ?? const <Holding>[])
          _EditorRow(
            key: _keySeq++,
            draft: HoldingDraft(
              recordId: holding.record.id,
              accountId: holding.account.id!,
              categoryId: holding.category.id!,
              amount: holding.amount,
              source: holding.record.source,
            ),
          ),
      ];
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: '記録する日付',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = dateOnly(picked));
    await _load();
  }

  /// 「1 タップ全複製」。直前の記録の内訳をそのまま持ってくる。
  /// 入金額は月ごとに変わるので引き継がない。
  Future<void> _duplicatePrevious() async {
    final repository = await ref.read(repositoryProvider.future);
    final previous = await repository.latestSnapshotBefore(_date);
    if (!mounted) return;

    if (previous == null) {
      showSnack(context, '複製できる過去の記録がありません');
      return;
    }

    setState(() {
      _rows = [
        for (final holding in previous.holdings)
          _EditorRow(
            key: _keySeq++,
            draft: HoldingDraft(
              accountId: holding.account.id!,
              categoryId: holding.category.id!,
              amount: holding.amount,
              source: RecordSource.duplicated,
            ),
          ),
      ];
      _dirty = true;
    });
    showSnack(
      context,
      '${Fmt.displayDate(previous.date)}の内訳を複製しました。変わった金額だけ直してください。',
    );
  }

  Future<void> _addRow() async {
    final accounts = await ref.read(accountsProvider.future);
    final categories = await ref.read(categoriesProvider.future);
    if (!mounted) return;

    if (accounts.isEmpty) {
      await _createFirstAccount();
      return;
    }

    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddRowSheet(accounts: accounts, categories: categories),
    );
    if (result == null || !mounted) return;

    final (accountId, categoryId) = result;
    final duplicate = _rows.any(
      (r) => r.draft.accountId == accountId && r.draft.categoryId == categoryId,
    );
    if (duplicate) {
      showSnack(context, 'その口座とカテゴリの組み合わせは既にあります');
      return;
    }

    setState(() {
      _rows = [
        ..._rows,
        _EditorRow(
          key: _keySeq++,
          draft: HoldingDraft(
            accountId: accountId,
            categoryId: categoryId,
            amount: 0,
          ),
        ),
      ];
      _dirty = true;
    });
  }

  Future<void> _createFirstAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountEditPage()),
    );
    if (mounted) setState(() {});
  }

  /// 「ざっくり入力」。口座もカテゴリも決めずに総額だけで始められるようにする。
  ///
  /// 最初の 1 回の心理的コストが、このアプリを使い続けてもらえるかの分かれ目
  /// なので、内訳を作らずに 1 行だけ用意する道を残している。
  Future<void> _startWithTotalOnly() async {
    final repository = await ref.read(repositoryProvider.future);
    final categories = await ref.read(categoriesProvider.future);
    if (categories.isEmpty) return;

    final accountId = await repository.upsertAccount(
      const Account(
        name: '資産全体',
        type: AccountType.other,
        note: 'あとから口座ごとに分けられます',
      ),
    );
    final categoryId = categories
        .firstWhere(
          (c) => c.name == 'その他',
          orElse: () => categories.last,
        )
        .id!;
    invalidateDataFrom(ref);
    if (!mounted) return;

    setState(() {
      _rows = [
        _EditorRow(
          key: _keySeq++,
          draft: HoldingDraft(
            accountId: accountId,
            categoryId: categoryId,
            amount: 0,
          ),
        ),
      ];
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) {
      showSnack(context, '金額を 1 件以上入力してください');
      return;
    }
    setState(() => _saving = true);
    final repository = await ref.read(repositoryProvider.future);
    await repository.saveSnapshot(
      _date,
      _rows.map((row) => row.draft).toList(),
      contribution: _contribution,
    );
    invalidateDataFrom(ref);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    Navigator.of(context).pop();
    showSnack(context, '${Fmt.displayDate(_date)}の記録を保存しました');
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirmDialog(
      context,
      title: '保存せずに戻りますか？',
      message: '入力した内容は保存されません。',
      confirmLabel: '破棄する',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final accountsById = {for (final a in accounts) a.id!: a};
    final categoriesById = {for (final c in categories) c.id!: c};

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (!discard) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('資産を記録'),
          actions: [
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('保存'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _EditorHeader(
                    date: _date,
                    total: _total,
                    rowCount: _rows.length,
                    onPickDate: _pickDate,
                  ),
                  Expanded(
                    child: accounts.isEmpty && _rows.isEmpty
                        ? _FirstRunChoices(
                            onAddAccount: _createFirstAccount,
                            onTotalOnly: _startWithTotalOnly,
                          )
                        : _buildRows(accountsById, categoriesById),
                  ),
                ],
              ),
        floatingActionButton: _loading || (accounts.isEmpty && _rows.isEmpty)
            ? null
            : FloatingActionButton.extended(
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: const Text('項目を追加'),
              ),
      ),
    );
  }

  Widget _buildRows(
    Map<int, Account> accountsById,
    Map<int, AssetCategory> categoriesById,
  ) {
    // 口座ごとにまとめる。表示順は口座一覧の並び順に合わせる。
    final grouped = <int, List<_EditorRow>>{};
    for (final row in _rows) {
      grouped.putIfAbsent(row.draft.accountId, () => []).add(row);
    }
    final orderedAccountIds = [
      for (final id in accountsById.keys)
        if (grouped.containsKey(id)) id,
      for (final id in grouped.keys)
        if (!accountsById.containsKey(id)) id,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        if (_rows.isEmpty) ...[
          if (_hasPrevious)
            _DuplicateCard(onTap: _duplicatePrevious)
          else
            const SectionCard(
              child: Text(
                '口座とカテゴリの組み合わせごとに評価額を入力します。'
                '来月からは前回のデータを 1 タップで複製できます。',
              ),
            ),
          const SizedBox(height: 12),
        ] else if (_hasPrevious) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _duplicatePrevious,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('前回データで置き換える'),
            ),
          ),
          const SizedBox(height: 4),
        ],
        for (final accountId in orderedAccountIds) ...[
          _AccountGroup(
            account: accountsById[accountId],
            rows: grouped[accountId]!,
            categoriesById: categoriesById,
            onChanged: (row, amount) {
              row.draft.amount = amount;
              _dirty = true;
              setState(() {});
            },
            onRemove: (row) => setState(() {
              _rows = _rows.where((r) => r.key != row.key).toList();
              _dirty = true;
            }),
          ),
          const SizedBox(height: 12),
        ],
        if (_rows.isNotEmpty) _buildContributionCard(),
      ],
    );
  }

  Widget _buildContributionCard() {
    final isPro = ref.watch(isProProvider);
    final theme = Theme.of(context);

    if (!isPro) {
      return ProUpsellBanner(
        title: '入金額を記録する',
        message: '増えた分を「入金」と「運用損益」に分けて見られるようになります。',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PaywallPage()),
        ),
      );
    }

    return SectionCard(
      title: '今月の入金額（任意）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '前回の記録以降に入金・積立した合計です。入れておくと、'
            '推移グラフに元本ラインが重なります。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          AmountField(
            key: ValueKey('contribution-$_contributionFieldKey'),
            initialValue: _contribution,
            onChanged: (value) {
              _contribution = value;
              _dirty = true;
            },
          ),
        ],
      ),
    );
  }
}

/// 初回だけ出る 2 択。空の画面に放り出さない。
class _FirstRunChoices extends StatelessWidget {
  const _FirstRunChoices({
    required this.onAddAccount,
    required this.onTotalOnly,
  });

  final VoidCallback onAddAccount;
  final VoidCallback onTotalOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Icon(
          Icons.savings_outlined,
          size: 44,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'どちらから始めますか？',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ざっくり総額だけ',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'まずは資産の合計だけを入れて始めます。'
                '口座やカテゴリはあとから分けられます。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onTotalOnly,
                child: const Text('総額だけで始める'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '口座ごとに分けて管理',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'SBI証券・楽天銀行などを登録して、'
                'はじめから内訳つきで記録します。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onAddAccount,
                child: const Text('口座を追加する'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.date,
    required this.total,
    required this.rowCount,
    required this.onPickDate,
  });

  final DateTime date;
  final int total;
  final int rowCount;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$rowCount 件の合計',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.yen(total),
                    style: theme.textTheme.headlineMedium?.tabular.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(Fmt.displayDate(date)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
          ),
        ],
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: scheme.primary.withValues(alpha: 0.10),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.copy_all_outlined, color: scheme.primary, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '前回のデータを 1 タップで複製',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '口座とカテゴリの構成をそのまま引き継ぎます。'
                    'あとは変わった金額だけ直せば完了です。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({
    required this.account,
    required this.rows,
    required this.categoriesById,
    required this.onChanged,
    required this.onRemove,
  });

  final Account? account;
  final List<_EditorRow> rows;
  final Map<int, AssetCategory> categoriesById;
  final void Function(_EditorRow row, int amount) onChanged;
  final void Function(_EditorRow row) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = rows.fold(0, (sum, row) => sum + row.draft.amount);

    return SectionCard(
      title: account?.name ?? '（削除された口座）',
      trailing: Text(
        Fmt.yen(subtotal),
        style: theme.textTheme.bodyMedium?.tabular.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _AmountRow(
              row: rows[i],
              category: categoriesById[rows[i].draft.categoryId],
              onChanged: (value) => onChanged(rows[i], value),
              onRemove: () => onRemove(rows[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.row,
    required this.category,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditorRow row;
  final AssetCategory? category;
  final ValueChanged<int> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ColorDot(color: category?.color ?? theme.colorScheme.outline),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category?.name ?? '不明なカテゴリ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (row.draft.source == RecordSource.csv)
                Text(
                  'CSV 取り込み',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: AmountField(
            key: ValueKey(row.key),
            initialValue: row.draft.amount,
            onChanged: onChanged,
          ),
        ),
        IconButton(
          tooltip: 'この項目を削除',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

/// 口座とカテゴリを選んで行を追加するシート。
class _AddRowSheet extends StatefulWidget {
  const _AddRowSheet({required this.accounts, required this.categories});

  final List<Account> accounts;
  final List<AssetCategory> categories;

  @override
  State<_AddRowSheet> createState() => _AddRowSheetState();
}

class _AddRowSheetState extends State<_AddRowSheet> {
  late int _accountId = widget.accounts.first.id!;
  int? _categoryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('項目を追加', style: theme.textTheme.titleMedium),
            const SizedBox(height: 18),
            Text('口座', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final account in widget.accounts)
                  ChoiceChip(
                    label: Text(account.displayName),
                    selected: _accountId == account.id,
                    onSelected: (_) => setState(() => _accountId = account.id!),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('カテゴリ', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in widget.categories)
                  ChoiceChip(
                    avatar: ColorDot(color: category.color, size: 8),
                    label: Text(category.name),
                    selected: _categoryId == category.id,
                    onSelected: (_) =>
                        setState(() => _categoryId = category.id!),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _categoryId == null
                    ? null
                    : () =>
                          Navigator.of(context).pop((_accountId, _categoryId!)),
                child: const Text('追加'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
