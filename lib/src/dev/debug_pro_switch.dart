import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// ストアに課金プロダクトを登録する前に Pro 機能を確認するための開発用スイッチ。
///
/// 実際の購入と同じ [ProStatus] を切り替えるので、アプリを再起動しても
/// 状態は保たれる。確認が終わったら戻しておくこと。
///
/// `kDebugMode` が false のリリースビルドでは呼び出し側の分岐ごと
/// ツリーシェイクで落ちるが、別の場所から使われても事故らないよう
/// ここでも同じ条件で閉じている。
class DebugProSwitch extends ConsumerWidget {
  const DebugProSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(proStatusProvider);

    return Card(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      child: SwitchListTile(
        // 読み込み中はスイッチを触らせない（連打で状態が食い違うため）。
        value: status.valueOrNull ?? false,
        onChanged: status.isLoading
            ? null
            : (value) async {
                final notifier = ref.read(proStatusProvider.notifier);
                await (value ? notifier.unlock() : notifier.relock());
              },
        secondary: Icon(Icons.bug_report_outlined, color: scheme.tertiary),
        title: const Text('Pro を解放する（デバッグ）'),
        subtitle: const Text('課金を通さずに切り替えます。デバッグビルドにのみ表示されます。'),
      ),
    );
  }
}
