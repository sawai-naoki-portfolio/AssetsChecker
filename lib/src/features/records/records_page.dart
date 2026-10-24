import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../csv/csv_import_page.dart';
import 'snapshot_editor_page.dart';

/// 記録した日付の一覧。ここが毎月の更新作業の入口になる。
class RecordsPage extends ConsumerWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(snapshotDatesProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('記録'),
        actions: [
          IconButton(
            tooltip: 'CSV を取り込む',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CsvImportPage()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('今月を記録'),
      ),
      body: dates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('読み込みに失敗しました: $error')),
        data: (list) {
          if (accounts.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'まず口座を登録しましょう',
              message: 'SBI証券・楽天銀行など、資産を置いている口座を追加すると記録を始められます。',
              actionLabel: '口座を追加',
              onAction: () => _openEditor(context, ref, null),
            );
          }
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.event_note_outlined,
              title: 'まだ記録がありません',
              message: '最初の 1 回だけ入力すれば、翌月からは「前回データを複製」で数秒で更新できます。',
              actionLabel: '最初の記録をつくる',
              onAction: () => _openEditor(context, ref, null),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _SnapshotTile(
              date: list[index],
              onTap: () => _openEditor(context, ref, list[index]),
              onDelete: () => _confirmDelete(context, ref, list[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    DateTime? date,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SnapshotEditorPage(initialDate: date),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
  ) async {
    final ok = await confirmDialog(
      context,
      title: '${Fmt.displayDate(date)}の記録を削除',
      message: 'この日付に登録したすべての金額が削除されます。元に戻せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;

    final repository = await ref.read(repositoryProvider.future);
    await repository.deleteSnapshot(date);
    invalidateDataFrom(ref);
    if (context.mounted) showSnack(context, '記録を削除しました');
  }
}

class _SnapshotTile extends ConsumerWidget {
  const _SnapshotTile({
    required this.date,
    required this.onTap,
    required this.onDelete,
  });

  final DateTime date;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshot = ref.watch(_snapshotSummaryProvider(date));

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.displayDate(date),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snapshot.valueOrNull == null
                          ? '—'
                          : '${snapshot.value!.holdings.length} 件の内訳',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                snapshot.valueOrNull == null
                    ? ''
                    : Fmt.yen(snapshot.value!.total),
                style: theme.textTheme.titleMedium?.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: '削除',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一覧の各行が自分の合計を取りに行くための Provider。
final _snapshotSummaryProvider = FutureProvider.family<AssetSnapshot?, DateTime>(
  (ref, date) async {
    ref.watch(dbRevisionProvider);
    final repository = await ref.watch(repositoryProvider.future);
    return repository.loadSnapshot(date);
  },
);
