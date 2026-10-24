import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../records/snapshot_editor_page.dart';
import 'allocation_donut.dart';

class AllocationPage extends ConsumerWidget {
  const AllocationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(currentSnapshotProvider);
    final dates = ref.watch(snapshotDatesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('資産配分'),
        actions: [
          if (dates.length > 1)
            _DatePickerButton(
              dates: dates,
              selected: snapshot.valueOrNull?.date,
              onSelected: (date) => ref
                  .read(selectedSnapshotDateProvider.notifier)
                  .state = date,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('読み込みに失敗しました: $error')),
        data: (data) {
          if (data == null || data.isEmpty) {
            return EmptyState(
              icon: Icons.savings_outlined,
              title: 'まだ資産が登録されていません',
              message: '最初の記録をつくると、カテゴリ別の構成比と口座一覧がここに表示されます。',
              actionLabel: '資産を記録する',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SnapshotEditorPage(),
                ),
              ),
            );
          }
          return _AllocationBody(snapshot: data);
        },
      ),
    );
  }
}

class _AllocationBody extends ConsumerWidget {
  const _AllocationBody({required this.snapshot});

  final AssetSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previous = ref.watch(previousSnapshotProvider).valueOrNull;
    final categories = snapshot.byCategory();
    final accounts = snapshot.byAccount();
    final total = snapshot.total;
    // 目標は Pro 機能。未設定・Free のときは 0 になり、カードごと出ない。
    final goal = ref.watch(isProProvider)
        ? ref.watch(settingsValueProvider).goalAmount
        : 0;

    return RefreshIndicator(
      onRefresh: () async => invalidateDataFrom(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyHeadline(
                  label: '総資産  ${Fmt.displayDate(snapshot.date)}時点',
                  amount: total,
                  delta: previous == null ? null : total - previous.total,
                  deltaLabel: previous == null
                      ? null
                      : '${Fmt.displayDate(previous.date)}比',
                ),
              ],
            ),
          ),
          if (goal > 0) ...[
            const SizedBox(height: 12),
            _GoalCard(goal: goal, total: total),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: 'カテゴリ別構成比',
            child: Column(
              children: [
                AllocationDonut(slices: categories, total: total),
                const SizedBox(height: 20),
                ...categories.map(
                  (slice) => _CategoryRow(slice: slice, total: total),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '保有口座',
            child: Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _AccountRow(slice: accounts[i], total: total),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'このデータは端末内の暗号化データベースにのみ保存されています',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 目標額に対する進捗。数字の羅列に物語を与えるための 1 枚。
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.total});

  final int goal;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = goal == 0 ? 0.0 : (total / goal).clamp(0.0, 1.0);
    final remaining = goal - total;

    return SectionCard(
      title: '目標までの進捗',
      trailing: Text(
        Fmt.percent(ratio),
        style: theme.textTheme.titleSmall?.tabular.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.primary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RatioBar(ratio: ratio, color: scheme.primary),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  remaining > 0
                      ? 'あと ${Fmt.yen(remaining)}'
                      : '目標を達成しています',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '目標 ${Fmt.compactYen(goal)}',
                style: theme.textTheme.bodySmall?.tabular.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.slice, required this.total});

  final CategorySlice slice;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = slice.ratioOf(total);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: [
          Row(
            children: [
              ColorDot(color: slice.category.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  slice.category.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                Fmt.percent(ratio),
                style: theme.textTheme.bodySmall?.tabular.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                Fmt.yen(slice.amount),
                style: theme.textTheme.bodyMedium?.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RatioBar(ratio: ratio, color: slice.category.color),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.slice, required this.total});

  final AccountSlice slice;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final holdings = [...slice.holdings]
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slice.account.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    slice.account.type.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.yen(slice.amount),
                  style: theme.textTheme.bodyLarge?.tabular.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  Fmt.percent(slice.ratioOf(total)),
                  style: theme.textTheme.bodySmall?.tabular.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final holding in holdings)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: holding.category.color.withValues(alpha: 0.12),
                ),
                child: Text(
                  '${holding.category.name}  ${Fmt.compactYen(holding.amount)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: holding.category.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.dates,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> dates;
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<DateTime?>(
      tooltip: '表示する時点を選ぶ',
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem<DateTime?>(value: null, child: Text('最新')),
        const PopupMenuDivider(),
        for (final date in dates.take(24))
          PopupMenuItem<DateTime?>(
            value: date,
            child: Text(Fmt.displayDate(date)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected == null ? '最新' : Fmt.displayMonth(selected!),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
