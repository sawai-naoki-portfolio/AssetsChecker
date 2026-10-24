import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/backup/backup_service.dart';
import '../../data/transfer/lan_transfer.dart';
import '../../data/transfer/qr_transfer_codec.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// 新端末側。旧端末が出す QR をカメラで読む。
///
/// QR には 2 種類ある。待ち合わせ情報なら LAN 経由で取りに行き、
/// 分割フレームならその場で組み立てる。どちらが来るかは読んでから
/// 判別するので、ユーザーが経路を選ぶ必要はない。
class TransferReceivePage extends ConsumerStatefulWidget {
  const TransferReceivePage({super.key});

  @override
  ConsumerState<TransferReceivePage> createState() =>
      _TransferReceivePageState();
}

class _TransferReceivePageState extends ConsumerState<TransferReceivePage> {
  final QrTransferAssembler _assembler = QrTransferAssembler();
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // 表示が切り替わるたびに読みたいので、間引きはしない。
    detectionSpeed: DetectionSpeed.unrestricted,
  );

  /// 揃った暗号化データ。ここに入ればカメラの出番は終わり。
  Uint8List? _payload;

  /// LAN から取得している最中。
  bool _fetching = false;
  bool _busy = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_payload != null || _fetching) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final handshake = LanHandshake.parse(raw);
      if (handshake != null) {
        unawaited(_fetchOverLan(handshake));
        return;
      }
    }

    var accepted = false;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && _assembler.add(raw)) accepted = true;
    }
    if (!accepted || !mounted) return;

    setState(() {
      if (_assembler.isComplete) _payload = _assembler.build();
    });
    // カメラの停止は MobileScanner のウィジェットが木から外れるときに
    // 自動で行われる。ここで stop() を呼ぶと二重停止になる。
    if (_payload != null) unawaited(HapticFeedback.mediumImpact());
  }

  Future<void> _fetchOverLan(LanHandshake handshake) async {
    setState(() => _fetching = true);
    try {
      final bytes = await LanTransferClient.fetch(handshake);
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _payload = bytes;
        _fetching = false;
      });
    } on LanTransferException catch (error) {
      // 繋がらなくてもカメラは動かしたままにする。旧端末側で
      // 「QR だけで送る」に切り替えれば、そのまま読み取りを続けられる。
      if (!mounted) return;
      setState(() => _fetching = false);
      showSnack(context, error.message);
    }
  }

  Future<void> _restore() async {
    final payload = _payload;
    if (payload == null) return;

    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _TransferCodeDialog(),
    );
    if (code == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final decoded = await service.decodeBackup(payload, code);
      if (!mounted) return;

      setState(() => _busy = false);
      final ok = await confirmDialog(
        context,
        title: 'このデータを取り込みますか？',
        message:
            '作成日時: ${Fmt.displayDate(decoded.summary.createdAt)}\n'
            '口座: ${decoded.summary.accountCount} 件 / '
            '記録: ${decoded.summary.recordCount} 件\n\n'
            'いまこの端末にあるデータはすべて置き換えられます。',
        confirmLabel: '取り込む',
        destructive: true,
      );
      if (!ok || !mounted) return;

      setState(() => _busy = true);
      await service.applyRestore(decoded.data);
      invalidateDataFrom(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, '引き継ぎが完了しました');
    } on BackupException catch (error) {
      // 引き継ぎコードの入力間違いはここに来る。受け取ったデータは
      // 捨てずに残すので、コードを入れ直すだけでやり直せる。
      if (mounted) showSnack(context, error.message);
    } catch (error) {
      if (mounted) showSnack(context, '取り込みに失敗しました: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// カメラは MobileScanner が木に戻った時点で自動的に始まるので、
  /// ここで start() を呼ぶと再アタッチ前に走って失敗する。
  void _restart() => setState(() {
    _assembler.reset();
    _payload = null;
    _fetching = false;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = _payload;
    final frameTotal = _assembler.totalCount;

    return Scaffold(
      appBar: AppBar(title: const Text('この端末で受け取る')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: payload != null
                      ? const _DoneView()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(
                              controller: _controller,
                              onDetect: _onDetect,
                              errorBuilder: (context, error) =>
                                  _ScannerError(error: error),
                            ),
                            if (_fetching) const _ConnectingOverlay(),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              if (payload != null) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('引き継ぎコードを入力'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _restart,
                  child: const Text('最初からやり直す'),
                ),
              ] else if (frameTotal != null) ...[
                _Progress(
                  received: _assembler.receivedCount,
                  total: frameTotal,
                ),
                const SizedBox(height: 12),
                Text(
                  'QR は繰り返し表示されます。すべて揃うまで端末を動かさずに構えてください。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else
                SectionCard(
                  title: '読み取り方',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('1. 古い端末で [設定] → [端末の引き継ぎ] → [この端末から送る] を開く'),
                      SizedBox(height: 6),
                      Text('2. 表示される QR に、この端末のカメラを向ける'),
                      SizedBox(height: 6),
                      Text('3. Wi-Fi 経由なら 1 回で終わります。QR だけの場合は、揃うまで構えたままにしてください'),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'カメラは QR の読み取りにだけ使います。'
                'Wi-Fi 経由で受け取る場合も、通信は古い端末との間だけで完結します。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xAA000000),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 16),
        Text(
          '古い端末に接続しています…',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: Colors.white),
        ),
      ],
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.received, required this.total});

  final int received;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('読み取り済み', style: theme.textTheme.bodyMedium),
            Text(
              '$received / $total 枚',
              style: theme.textTheme.titleMedium?.tabular.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: total == 0 ? null : received / total,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text('データを受け取りました', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '古い端末に表示されているコードを入力してください',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              denied ? Icons.no_photography_outlined : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              denied ? 'カメラを使えません' : 'カメラを起動できませんでした',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? '端末の設定でこのアプリにカメラを許可すると、QR を読み取れます。'
                        'カメラは QR の読み取りにだけ使い、画像は保存も送信もしません。'
                  : error.errorCode.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 引き継ぎコードの入力。旧端末の画面に出ている 8 桁を打ち込む。
class _TransferCodeDialog extends StatefulWidget {
  const _TransferCodeDialog();

  @override
  State<_TransferCodeDialog> createState() => _TransferCodeDialogState();
}

class _TransferCodeDialogState extends State<_TransferCodeDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // 表示は 4 桁ずつ区切っているので、空白を落としてから照合する。
    final value = _controller.text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (value.length != QrTransferCodec.transferCodeLength) {
      setState(
        () => _error = '${QrTransferCodec.transferCodeLength} 文字で入力してください',
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('引き継ぎコード'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '古い端末の画面に表示されている 8 文字を入力してください。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(letterSpacing: 4, fontSize: 20),
            decoration: const InputDecoration(labelText: 'コード'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _submit, child: const Text('取り込む')),
      ],
    );
  }
}
