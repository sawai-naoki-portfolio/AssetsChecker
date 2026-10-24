import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/app_settings.dart';
import '../../dev/debug_pro_switch.dart';
import '../../providers.dart';
import '../../security/screen_guard.dart';
import '../../widgets/common.dart';
import '../accounts/accounts_page.dart';
import '../backup/backup_page.dart';
import '../categories/categories_page.dart';
import '../purchase/paywall_page.dart';
import '../transfer/device_transfer_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsValueProvider);
    final isPro = ref.watch(isProProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final backupStatus = ref.watch(backupStatusProvider);

    Future<void> setSetting(String key, String value) async {
      final repository = await ref.read(repositoryProvider.future);
      await repository.setSetting(key, value);
      invalidateDataFrom(ref);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (backupStatus.shouldWarn) ...[
            _BackupNag(
              status: backupStatus,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BackupPage()),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (isPro)
            SectionCard(
              child: Row(
                children: [
                  const ProBadge(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'すべての機能が利用できます',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            ProUpsellBanner(
              title: 'Pro（買い切り）',
              message: '口座無制限・全期間グラフ・入金額トラッキング・目標設定',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PaywallPage()),
              ),
            ),
          const SizedBox(height: 16),

          const _GroupLabel('毎月の記録'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.reminderEnabled,
                  onChanged: (value) =>
                      _toggleReminder(context, ref, settings, value),
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('入力リマインダー'),
                  subtitle: const Text('記録を忘れると、このアプリは価値を失います'),
                ),
                if (settings.reminderEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: const Text('通知するタイミング'),
                    trailing: Text(
                      '毎月${settings.reminderDay}日 ${settings.reminderHour}時',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _editSchedule(context, ref, settings),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          const _GroupLabel('目標'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Row(
                children: [
                  const Text('目標資産額'),
                  if (!isPro) ...[
                    const SizedBox(width: 8),
                    const ProBadge(compact: true),
                  ],
                ],
              ),
              subtitle: Text(
                settings.hasGoal
                    ? '資産配分の画面に進捗が表示されます'
                    : '設定すると達成率を追えます',
              ),
              trailing: Text(
                settings.hasGoal ? Fmt.compactYen(settings.goalAmount) : '未設定',
                style: theme.textTheme.bodyMedium?.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => isPro
                  ? _editGoal(context, ref, settings)
                  : Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PaywallPage(),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          const _GroupLabel('セキュリティ'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.biometricLock,
                  onChanged: (value) => setSetting(
                    SettingKeys.biometricLock,
                    value ? '1' : '0',
                  ),
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('起動時にロックする'),
                  subtitle: const Text('生体認証または端末のパスコードで解除します'),
                ),
                const Divider(height: 1),
                // スクリーンショット防止は Android のみ。iOS には公式 API が
                // ないため、効かないスイッチを見せずに事実を書く。
                if (ScreenGuard.screenshotBlockSupported)
                  SwitchListTile(
                    value: settings.blockScreenshot,
                    onChanged: (value) async {
                      await setSetting(
                        SettingKeys.blockScreenshot,
                        value ? '1' : '0',
                      );
                      await ScreenGuard.setBlockScreenshot(value);
                    },
                    secondary: const Icon(Icons.screenshot_monitor_outlined),
                    title: const Text('スクリーンショットを防ぐ'),
                    subtitle: const Text('切っても、タスク切り替え画面での遮蔽は続きます'),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.screenshot_monitor_outlined),
                    title: const Text('タスク切り替え時の画面遮蔽'),
                    subtitle: const Text('常に有効です。この OS ではスクリーンショット自体は防げません。'),
                    trailing: Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const _GroupLabel('データ'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: const Text('暗号化バックアップ'),
                  subtitle: const Text('パスワード保護したファイルを書き出し / 復元'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const BackupPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('端末の引き継ぎ'),
                  subtitle: const Text('2 台を並べて QR でデータを渡す'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DeviceTransferPage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('口座管理'),
                  subtitle: Text('${accounts.length} 件を登録中'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountsPage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('カテゴリ管理'),
                  subtitle: const Text('資産の分類を追加・改名'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CategoriesPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const _GroupLabel('このアプリが守っていること'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final pledge in AppInfo.privacyPledges)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            pledge,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const _GroupLabel('その他'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('バージョン'),
                  trailing: Text(AppInfo.version),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'すべてのデータを削除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () => _deleteEverything(context, ref),
                ),
              ],
            ),
          ),

          // kDebugMode は const なので、リリースビルドではこの分岐ごと消える。
          if (kDebugMode) ...[
            const SizedBox(height: 20),
            const _GroupLabel('デバッグ'),
            const DebugProSwitch(),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleReminder(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    bool enabled,
  ) async {
    final reminder = ref.read(reminderServiceProvider);
    final repository = await ref.read(repositoryProvider.future);

    if (!enabled) {
      await reminder.cancel();
      await repository.setSetting(SettingKeys.reminderEnabled, '0');
      invalidateDataFrom(ref);
      return;
    }

    final granted = await reminder.requestPermission();
    if (!granted) {
      if (context.mounted) {
        showSnack(context, '端末の設定で通知を許可すると、リマインダーを使えます');
      }
      return;
    }

    await reminder.schedule(
      day: settings.reminderDay,
      hour: settings.reminderHour,
    );
    await repository.setSetting(SettingKeys.reminderEnabled, '1');
    invalidateDataFrom(ref);
    if (context.mounted) {
      showSnack(
        context,
        '毎月${settings.reminderDay}日 ${settings.reminderHour}時にお知らせします',
      );
    }
  }

  Future<void> _editSchedule(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      builder: (_) => _ScheduleSheet(
        day: settings.reminderDay,
        hour: settings.reminderHour,
      ),
    );
    if (result == null) return;

    final (day, hour) = result;
    final repository = await ref.read(repositoryProvider.future);
    await repository.setSetting(SettingKeys.reminderDay, '$day');
    await repository.setSetting(SettingKeys.reminderHour, '$hour');
    await ref.read(reminderServiceProvider).schedule(day: day, hour: hour);
    invalidateDataFrom(ref);
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _GoalDialog(initialValue: settings.goalAmount),
    );
    if (result == null) return;

    final repository = await ref.read(repositoryProvider.future);
    await repository.setSetting(SettingKeys.goalAmount, '$result');
    invalidateDataFrom(ref);
  }

  Future<void> _deleteEverything(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'すべてのデータを削除',
      message: '口座・記録・設定をすべて削除します。元に戻せません。'
          'バックアップを取っていない場合、データは完全に失われます。',
      confirmLabel: '完全に削除',
      destructive: true,
    );
    if (!ok) return;

    final repository = await ref.read(repositoryProvider.future);
    await repository.deleteEverything();
    invalidateDataFrom(ref);
    if (context.mounted) showSnack(context, 'すべてのデータを削除しました');
  }
}

class _BackupNag extends StatelessWidget {
  const _BackupNag({required this.status, required this.onTap});

  final BackupStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: scheme.errorContainer.withValues(alpha: 0.35),
          border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.error),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status == BackupStatus.never
                        ? 'バックアップを取りましょう'
                        : '$kBackupReminderDays 日以上バックアップしていません',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'データは端末の中だけにあります。端末を失うと戻せません。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.day, required this.hour});

  final int day;
  final int hour;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late int _day = widget.day;
  late int _hour = widget.hour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('通知するタイミング', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '月末は日数が変わるため、選べるのは 28 日までです。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _day,
                    decoration: const InputDecoration(labelText: '日'),
                    items: [
                      for (var d = 1; d <= 28; d++)
                        DropdownMenuItem(value: d, child: Text('$d 日')),
                    ],
                    onChanged: (value) =>
                        setState(() => _day = value ?? _day),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _hour,
                    decoration: const InputDecoration(labelText: '時刻'),
                    items: [
                      for (var h = 0; h < 24; h++)
                        DropdownMenuItem(value: h, child: Text('$h 時')),
                    ],
                    onChanged: (value) =>
                        setState(() => _hour = value ?? _hour),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop((_day, _hour)),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.initialValue});

  final int initialValue;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late int _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('目標資産額'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'いくらまで増やしたいかを入れてください。0 にすると非表示になります。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          AmountField(
            initialValue: widget.initialValue,
            autofocus: true,
            onChanged: (value) => _value = value,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
