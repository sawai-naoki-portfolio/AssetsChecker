import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../purchase/paywall_page.dart';
import 'account_edit_page.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final isPro = ref.watch(isProProvider);
    final canAdd = ref.watch(canAddAccountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('口座管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => canAdd
            ? Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountEditPage()),
              )
            : Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PaywallPage()),
              ),
        icon: Icon(canAdd ? Icons.add : Icons.lock_outline),
        label: Text(canAdd ? '口座を追加' : 'Pro で無制限に'),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('読み込みに失敗しました: $error')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (!isPro)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProUpsellBanner(
                  title: '登録口座数 ${list.length} / ${FreePlanLimits.maxAccounts}',
                  message: 'Pro（買い切り）にすると口座を無制限に登録できます。',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PaywallPage()),
                  ),
                ),
              ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyState(
                  icon: Icons.account_balance_outlined,
                  title: '口座がまだありません',
                  message: '資産を置いている口座を追加すると、記録を始められます。',
                ),
              ),
            for (final account in list) ...[
              _AccountTile(account: account),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AccountEditPage(account: account),
          ),
        ),
        title: Text(
          account.name,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          account.note.isEmpty
              ? account.type.label
              : '${account.type.label}・${account.note}',
        ),
        trailing: IconButton(
          tooltip: '削除',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => _confirmDelete(context, ref),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repository = await ref.read(repositoryProvider.future);
    final count = await repository.countRecordsForAccount(account.id!);
    if (!context.mounted) return;

    final ok = await confirmDialog(
      context,
      title: '「${account.name}」を削除',
      message: count == 0
          ? 'この口座を削除します。'
          : 'この口座に紐づく $count 件の記録もすべて削除されます。元に戻せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;

    await repository.deleteAccount(account.id!);
    invalidateDataFrom(ref);
    if (context.mounted) showSnack(context, '口座を削除しました');
  }
}
