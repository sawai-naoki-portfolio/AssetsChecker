import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'transfer_receive_page.dart';
import 'transfer_send_page.dart';

/// 機種変更のときに、2 台を並べて QR でデータを渡すための入口。
///
/// 旧端末が動くことが前提なので、暗号化バックアップの代わりにはならない。
/// その線引きはこの画面で明示する。
class DeviceTransferPage extends StatelessWidget {
  const DeviceTransferPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('端末の引き継ぎ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionCard(
            title: '2 台を並べて引き継ぐ',
            child: Text(
              '古い端末が QR を表示し、新しい端末のカメラで読み取ります。'
              '同じ Wi-Fi にいれば、QR は待ち合わせにだけ使い、データ本体は'
              '2 台の間で直接やり取りするので一瞬で終わります。'
              'Wi-Fi が使えない場合は、QR の絵柄だけでデータを渡す方法に切り替わります。'
              'iPhone と Android の間でも使えます。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TransferSendPage()),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('この端末から送る（古い端末）'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TransferReceivePage(),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('この端末で受け取る（新しい端末）'),
          ),
          const SizedBox(height: 20),
          SectionCard(
            title: '知っておいてほしいこと',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _note(
                  theme,
                  Icons.devices_other_outlined,
                  '古い端末が手元で動くことが前提です。'
                  '紛失・故障・水没に備えるには、暗号化バックアップを取っておいてください。',
                ),
                _note(
                  theme,
                  Icons.swap_horiz,
                  '受け取り側のデータはすべて置き換わります。'
                  '新しい端末で既に入力した内容があれば消えます。',
                ),
                _note(
                  theme,
                  Icons.workspace_premium_outlined,
                  'Pro の購入状態は引き継ぎに含まれません。'
                  'ストアのアカウントに紐づいているので、新しい端末で自動的に戻ります。',
                ),
                _note(
                  theme,
                  Icons.photo_camera_outlined,
                  'カメラは QR の読み取りにだけ使います。'
                  '画像を保存することも、どこかへ送ることもありません。',
                ),
                _note(
                  theme,
                  Icons.wifi_tethering,
                  'Wi-Fi 経由の場合も、通信は 2 台の間だけで完結します。'
                  'ルーターの外へは出ず、インターネット上のサーバーは介しません。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'データは AES-256-GCM で暗号化したうえで QR に載せます。'
            '鍵は転送のたびに作り直される引き継ぎコードから導出します。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    ),
  );
}
