import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/csv/brokerage_csv_parser.dart';
import '../../data/models/models.dart';
import '../../data/repositories/asset_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// 証券会社の CSV を端末内で解析して取り込む画面。
///
/// ファイルは一切外部へ送らず、Dart 側で文字コード判定・集計まで完結する。
class CsvImportPage extends ConsumerStatefulWidget {
  const CsvImportPage({super.key});

  @override
  ConsumerState<CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends ConsumerState<CsvImportPage> {
  CsvParseResult? _result;
  String _fileName = '';
  String _encoding = '';
  bool _busy = false;
  String? _error;

  /// 解析結果の行 index -> 割り当てたカテゴリ ID
  final Map<int, int> _assignment = {};
  int? _accountId;
  DateTime _date = dateOnly(DateTime.now());

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
        withData: true,
        dialogTitle: '取り込む CSV を選択',
      );
      final files = picked?.files ?? const <PlatformFile>[];
      final file = files.isEmpty ? null : files.first;
      final bytes = file?.bytes;
      if (file == null || bytes == null) {
        setState(() => _busy = false);
        return;
      }

      final decoded = await ref
          .read(csvDecoderProvider)
          .decode(Uint8List.fromList(bytes));
      final parsed = const BrokerageCsvParser().parse(decoded.text);
      final categories = await ref.read(categoriesProvider.future);
      if (!mounted) return;

      setState(() {
        _fileName = file.name;
        _encoding = decoded.encoding;
        _result = parsed;
        _assignment
          ..clear()
          ..addAll(_autoAssign(parsed.holdings, categories));
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'CSV を読み込めませんでした: $error';
      });
    }
  }

  /// 推定カテゴリ名を既存カテゴリに突き合わせる。該当なしは末尾のカテゴリへ。
  Map<int, int> _autoAssign(
    List<ParsedHolding> holdings,
    List<AssetCategory> categories,
  ) {
    if (categories.isEmpty) return const {};
    final byName = {for (final c in categories) c.name: c.id!};
    final fallback = byName['その他'] ?? categories.last.id!;
    return {
      for (var i = 0; i < holdings.length; i++)
        i: byName[holdings[i].categoryGuess] ?? fallback,
    };
  }

  Future<void> _import() async {
    final result = _result;
    final accountId = _accountId;
    if (result == null || accountId == null) return;

    setState(() => _busy = true);
    final repository = await ref.read(repositoryProvider.future);

    // カテゴリごとに合算する。
    final totals = <int, int>{};
    for (var i = 0; i < result.holdings.length; i++) {
      final categoryId = _assignment[i];
      if (categoryId == null) continue;
      totals[categoryId] = (totals[categoryId] ?? 0) + result.holdings[i].amount;
    }

    // 同じ日付の他口座の記録は残したまま、対象口座ぶんだけ置き換える。
    final existing = await repository.loadSnapshot(_date);
    final drafts = <HoldingDraft>[
      for (final holding in existing?.holdings ?? const <Holding>[])
        if (holding.account.id != accountId)
          HoldingDraft(
            accountId: holding.account.id!,
            categoryId: holding.category.id!,
            amount: holding.amount,
            source: holding.record.source,
          ),
      for (final entry in totals.entries)
        HoldingDraft(
          accountId: accountId,
          categoryId: entry.key,
          amount: entry.value,
          source: RecordSource.csv,
        ),
    ];

    // 同じ日付に入金額を登録済みなら、それは維持する。
    final contribution = await repository.loadContribution(_date);
    await repository.saveSnapshot(_date, drafts, contribution: contribution);
    invalidateDataFrom(ref);
    if (!mounted) return;

    setState(() => _busy = false);
    Navigator.of(context).pop();
    showSnack(context, '${Fmt.displayDate(_date)}に ${totals.length} 件を取り込みました');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CSV を取り込む')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _result == null
          ? _buildPicker(context)
          : _buildReview(context),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SectionCard(
          title: '対応する CSV',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SBI証券・楽天証券などの「保有商品一覧」CSV に対応しています。'
                'Shift-JIS / UTF-8 は自動で判定します。',
              ),
              const SizedBox(height: 12),
              Text(
                '「銘柄名」と「評価額（時価評価額）」に相当する列を自動で探すため、'
                '列の並びが変わっても取り込めます。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'この機能について',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '証券会社の CSV は予告なく書式が変わります。取り込みは'
                  'ベストエフォートで提供しており、動作を保証するものではありません。'
                  '読み取れなかった場合は手入力をご利用ください。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'プライバシー',
          child: Row(
            children: [
              Icon(Icons.wifi_off, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('選んだファイルは端末の外に出ません。解析はすべてアプリ内で行われます。'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('CSV ファイルを選ぶ'),
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final result = _result!;
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final categoriesById = {for (final c in categories) c.id!: c};

    final totals = <int, int>{};
    for (var i = 0; i < result.holdings.length; i++) {
      final id = _assignment[i];
      if (id == null) continue;
      totals[id] = (totals[id] ?? 0) + result.holdings[i].amount;
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              SectionCard(
                title: '読み取り結果',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('ファイル', _fileName),
                    _kv('書式', result.format),
                    _kv('文字コード', _encoding),
                    _kv('明細', '${result.holdings.length} 件'),
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Text('合計評価額')),
                        Text(
                          Fmt.yen(result.total),
                          style: theme.textTheme.titleMedium?.tabular.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              for (final warning in result.warnings) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.35,
                    ),
                  ),
                  child: Text(warning, style: theme.textTheme.bodySmall),
                ),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: '取り込み先',
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _accountId,
                      decoration: const InputDecoration(labelText: '口座'),
                      items: [
                        for (final account in accounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(account.displayName),
                          ),
                      ],
                      onChanged: (value) => setState(() => _accountId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text('日付：${Fmt.displayDate(_date)}'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(DateTime.now().year + 1, 12),
                            );
                            if (picked != null) {
                              setState(() => _date = dateOnly(picked));
                            }
                          },
                          child: const Text('変更'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'カテゴリ別の集計',
                child: Column(
                  children: [
                    for (final entry in totals.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            ColorDot(
                              color:
                                  categoriesById[entry.key]?.color ??
                                  theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                categoriesById[entry.key]?.name ?? '不明',
                              ),
                            ),
                            Text(
                              Fmt.yen(entry.value),
                              style: theme.textTheme.bodyMedium?.tabular
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: '明細とカテゴリの割り当て',
                child: Column(
                  children: [
                    for (var i = 0; i < result.holdings.length; i++)
                      _HoldingAssignRow(
                        holding: result.holdings[i],
                        categories: categories,
                        categoryId: _assignment[i],
                        onChanged: (value) =>
                            setState(() => _assignment[i] = value),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _result = null),
                    child: const Text('選び直す'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _accountId == null || totals.isEmpty
                        ? null
                        : _import,
                    child: const Text('この内容で取り込む'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            key,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _HoldingAssignRow extends StatelessWidget {
  const _HoldingAssignRow({
    required this.holding,
    required this.categories,
    required this.categoryId,
    required this.onChanged,
  });

  final ParsedHolding holding;
  final List<AssetCategory> categories;
  final int? categoryId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holding.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  Fmt.yen(holding.amount),
                  style: theme.textTheme.bodySmall?.tabular.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<int>(
              initialValue: categoryId,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              items: [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(
                      category.name,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

