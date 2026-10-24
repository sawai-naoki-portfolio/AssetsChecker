import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import 'purchase_controller.dart';

/// 買い切り課金の案内。サブスクではないことを前面に出す。
class PaywallPage extends ConsumerWidget {
  const PaywallPage({super.key});

  /// 「データを守る機能は無料、深掘りする機能は有料」という線引き。
  /// バックアップに課金すると、ユーザーがデータを失う唯一の経路に
  /// 値段をつけることになるため Free 側に置いている。
  static const List<(String feature, String free, String pro)> _matrix = [
    ('登録できる口座数', '3 口座まで', '無制限'),
    ('資産推移グラフ', '直近 3 ヶ月', '全期間'),
    ('入金額の記録・元本ライン', '—', '利用可能'),
    ('目標額と達成率', '—', '利用可能'),
    ('暗号化バックアップ', '利用可能', '利用可能'),
    ('CSV ローカル解析', '利用可能', '利用可能'),
    ('生体認証ロック', '利用可能', '利用可能'),
    ('入力リマインダー', '利用可能', '利用可能'),
    ('広告・トラッキング', 'なし', 'なし'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final purchase = ref.watch(purchaseControllerProvider);
    final isPro = ref.watch(isProProvider);

    ref.listen(purchaseControllerProvider, (previous, next) {
      final message = next.message;
      if (message != null && message != previous?.message) {
        showSnack(context, message);
        ref.read(purchaseControllerProvider.notifier).clearMessage();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Pro について')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.22),
                  scheme.primary.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ProBadge(),
                    const SizedBox(width: 10),
                    Text(
                      '買い切り・サブスクなし',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isPro ? 'Pro をご利用中です' : '一度だけの支払いで、ずっと使えます',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isPro
                      ? 'すべての機能が解放されています。ありがとうございます。'
                      : 'サーバーを持たないアプリなので、維持費がかかりません。'
                            '毎月の課金ではなく、買い切りにしています。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (!isPro) ...[
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        purchase.priceLabel,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '（1 回のみ）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'できること',
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(flex: 5, child: SizedBox()),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Free',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Pro',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                for (final row in _matrix) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            row.$1,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            row.$2,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            row.$3,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row != _matrix.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'なぜサブスクではないのか',
            child: Text(
              'このアプリはサーバーを持たず、あなたのデータを預かりません。'
              '維持費がかからない以上、毎月お金をいただく理由がないと考えています。'
              '一度買えば、アプリが動く限りずっと使えます。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '課金しなくても失わないもの',
            child: Text(
              '暗号化バックアップ・生体認証ロック・入力リマインダーは Free でも'
              '制限しません。データを守る手段に課金するのは、'
              'このアプリの立場と矛盾すると考えているためです。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          if (!isPro) ...[
            FilledButton(
              // 商品を取得できていないと buy() が即座に失敗するので、
              // 押せてしまわないようにする（価格表示も既定値のままになる）。
              onPressed:
                  purchase.pending ||
                      !purchase.storeAvailable ||
                      purchase.product == null
                  ? null
                  : () => ref.read(purchaseControllerProvider.notifier).buy(),
              child: purchase.pending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('${purchase.priceLabel} で Pro にする'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: purchase.pending
                  ? null
                  : () =>
                        ref.read(purchaseControllerProvider.notifier).restore(),
              child: const Text('購入を復元する'),
            ),
            if (purchase.initialized &&
                (!purchase.storeAvailable || purchase.product == null))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  purchase.storeAvailable
                      ? 'この商品はストアでまだ取り扱われていないため、'
                            'いまは購入できません。'
                      : 'ストアに接続できないため、いまは購入できません。'
                            'ネットワーク接続が必要なのは購入時だけです。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ] else
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          const SizedBox(height: 16),
          Text(
            '商品 ID: ${IapProducts.proLifetime}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
