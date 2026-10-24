import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../data/transfer/lan_transfer.dart';
import '../../data/transfer/qr_transfer_codec.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// 送り方。既定は LAN で、繋がらないときに QR だけで送る方へ切り替える。
enum _SendMode { lan, qr }

/// 旧端末側。全データを暗号化し、LAN 経由か分割 QR で新端末へ渡す。
///
/// どちらの経路でも封筒は同じで、鍵は引き継ぎコードから導出する。
/// コードは QR に載せず画面に文字で出すので、QR を撮影されただけでは
/// 中身を読めない。
class TransferSendPage extends ConsumerStatefulWidget {
  const TransferSendPage({super.key});

  @override
  ConsumerState<TransferSendPage> createState() => _TransferSendPageState();
}

class _TransferSendPageState extends ConsumerState<TransferSendPage> {
  /// QR を切り替える間隔。速すぎると受信側のカメラが取りこぼす。
  static const Duration _frameInterval = Duration(milliseconds: 220);

  String? _code;
  List<String> _frames = const [];
  int _index = 0;
  Timer? _timer;

  LanTransferServer? _server;
  StreamSubscription<void>? _deliveredSubscription;
  _SendMode _mode = _SendMode.lan;
  bool _delivered = false;

  /// LAN を使えなかった理由。使えている間は null。
  String? _lanError;

  /// 封筒を作る段階で失敗した場合。こうなると送りようがない。
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_deliveredSubscription?.cancel());
    unawaited(_server?.stop());
    super.dispose();
  }

  Future<void> _prepare() async {
    final Uint8List envelope;
    final String code;
    try {
      final service = await ref.read(backupServiceProvider.future);
      code = QrTransferCodec.newTransferCode();
      // 鍵導出に 1〜2 秒かかる。バックアップと同じ封筒形式なので、
      // 受信側は既存の復号経路をそのまま使える。
      envelope = await service.createBackup(code);
    } catch (error) {
      if (mounted) setState(() => _fatalError = '$error');
      return;
    }
    if (!mounted) return;

    setState(() {
      _code = code;
      _frames = QrTransferCodec.encode(
        envelope,
        sessionId: QrTransferCodec.newSessionId(),
      );
    });

    await _startServer(envelope);
  }

  Future<void> _startServer(Uint8List envelope) async {
    try {
      final server = await LanTransferServer.start(envelope);
      if (!mounted) {
        await server.stop();
        return;
      }
      _deliveredSubscription = server.onDelivered.listen((_) {
        if (mounted) setState(() => _delivered = true);
      });
      setState(() => _server = server);
    } catch (error) {
      // LAN が使えないだけなので、QR 経路へ倒して続行する。
      if (mounted) _switchTo(_SendMode.qr, lanError: '$error');
    }
  }

  void _switchTo(_SendMode mode, {String? lanError}) {
    setState(() {
      _mode = mode;
      if (lanError != null) _lanError = lanError;
    });

    _timer?.cancel();
    _timer = null;
    if (mode == _SendMode.qr && _frames.length > 1) {
      _timer = Timer.periodic(_frameInterval, (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % _frames.length);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final code = _code;

    if (_fatalError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('この端末から送る')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SectionCard(
            title: '準備できませんでした',
            child: Text(_fatalError!, style: theme.textTheme.bodyMedium),
          ),
        ),
      );
    }

    if (code == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('この端末から送る')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('データを暗号化しています…'),
            ],
          ),
        ),
      );
    }

    final server = _server;
    final usingLan = _mode == _SendMode.lan && server != null;

    return Scaffold(
      appBar: AppBar(title: const Text('この端末から送る')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // QR は端末のテーマに関係なく白地・黒モジュールで出す。
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: usingLan
                    ? server.handshake.encode()
                    : _frames[_index],
                size: 280,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            usingLan
                ? _delivered
                      ? '新しい端末へ渡しました'
                      : 'この QR を 1 回読み取ってください'
                : _frames.length == 1
                ? 'この 1 枚を読み取ってください'
                : '${_index + 1} / ${_frames.length} 枚目（繰り返し表示されます）',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _delivered && usingLan
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
              fontWeight: _delivered && usingLan
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),
          SectionCard(
            title: '引き継ぎコード',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SelectableText(
                    _formatCode(code),
                    style: theme.textTheme.headlineMedium?.tabular.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '読み取りが終わると、新しい端末でこのコードを聞かれます。'
                  'このコードがなければデータは復号できません。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _RouteCard(
            usingLan: usingLan,
            canUseLan: server != null,
            lanError: _lanError,
            frameCount: _frames.length,
            onSwitch: _switchTo,
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '手順',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. 新しい端末で [設定] → [端末の引き継ぎ] → [この端末で受け取る] を選ぶ'),
                const SizedBox(height: 6),
                Text(
                  usingLan
                      ? '2. 新しい端末のカメラを、この画面の QR に向ける'
                      : '2. 新しい端末のカメラを向けたまま、QR が切り替わり続けるのを待つ',
                ),
                const SizedBox(height: 6),
                const Text('3. 読み取れたら、上の引き継ぎコードを入力する'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: scheme.errorContainer.withValues(alpha: 0.3),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_off_outlined, color: scheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '引き継ぎコードを他人に見られないようにしてください。'
                    '${usingLan ? '同じ Wi-Fi にいる第三者がデータを取得できたとしても' : 'QR をすべて撮影されたとしても'}、'
                    'コードが分からなければ中身は読めません。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'この端末のデータは消えません。転送が終わっても、'
            '不要になるまでそのまま使えます。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 8 桁は続けて読むと取り違えやすいので 4 桁ずつに区切る。
  static String _formatCode(String code) =>
      '${code.substring(0, 4)} ${code.substring(4)}';
}

/// いまどちらの経路で送っているかと、その切り替え。
class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.usingLan,
    required this.canUseLan,
    required this.lanError,
    required this.frameCount,
    required this.onSwitch,
  });

  final bool usingLan;
  final bool canUseLan;
  final String? lanError;
  final int frameCount;
  final void Function(_SendMode mode) onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SectionCard(
      title: usingLan ? 'Wi-Fi 経由で送っています' : 'QR だけで送っています',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            usingLan
                ? '同じ Wi-Fi にいる新しい端末へ直接渡します。'
                      'この QR にはデータではなく、待ち合わせ場所だけが入っています。'
                : 'ネットワークを使わず、QR の絵柄だけでデータを渡します。'
                      '$frameCount 枚を繰り返し表示するので、読み取りに少し時間がかかります。',
            style: theme.textTheme.bodySmall,
          ),
          if (lanError != null) ...[
            const SizedBox(height: 10),
            Text(
              'Wi-Fi 経由は使えませんでした: $lanError',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 12),
          if (usingLan)
            OutlinedButton.icon(
              onPressed: () => onSwitch(_SendMode.qr),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('繋がらないので QR だけで送る'),
            )
          else if (canUseLan)
            OutlinedButton.icon(
              onPressed: () => onSwitch(_SendMode.lan),
              icon: const Icon(Icons.wifi),
              label: const Text('Wi-Fi 経由に戻す'),
            ),
        ],
      ),
    );
  }
}
