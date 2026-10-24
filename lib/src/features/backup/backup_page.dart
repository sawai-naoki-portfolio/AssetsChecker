import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/backup/backup_service.dart';
import '../../data/models/app_settings.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// 暗号化バックアップの書き出しと復元。
///
/// 保存先はユーザーが選ぶ（iCloud Drive / Google Drive / ファイルアプリなど）。
/// アプリはどこへ保存されたかを一切記録しない。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  Future<void> _export() async {
    final password = await _askPassword(
      title: 'バックアップのパスワード',
      message: 'このパスワードがないとバックアップは復元できません。'
          'アプリ側には保存されないため、必ず控えてください。',
      confirm: true,
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final bytes = await service.createBackup(password);
      final fileName = service.suggestedFileName(DateTime.now());

      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: fileName,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );

      final repository = await ref.read(repositoryProvider.future);
      await repository.setSetting(
        SettingKeys.lastBackupAt,
        DateTime.now().toIso8601String(),
      );
      invalidateDataFrom(ref);

      // 共有シートを閉じた後、一時ファイルは残さない。
      if (await file.exists()) await file.delete();

      if (!mounted) return;
      showSnack(context, 'バックアップを書き出しました');
    } catch (error) {
      if (!mounted) return;
      showSnack(context, '書き出しに失敗しました: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      dialogTitle: 'バックアップファイルを選択',
    );
    final files = picked?.files ?? const <PlatformFile>[];
    if (files.isEmpty || files.first.bytes == null || !mounted) return;
    final bytes = Uint8List.fromList(files.first.bytes!);

    final password = await _askPassword(
      title: 'バックアップのパスワード',
      message: '書き出したときに設定したパスワードを入力してください。',
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final decoded = await service.decodeBackup(bytes, password);
      if (!mounted) return;

      setState(() => _busy = false);
      final ok = await confirmDialog(
        context,
        title: 'このバックアップを復元しますか？',
        message:
            '作成日時: ${Fmt.displayDate(decoded.summary.createdAt)}\n'
            '口座: ${decoded.summary.accountCount} 件 / '
            '記録: ${decoded.summary.recordCount} 件\n\n'
            '現在このアプリにあるデータはすべて置き換えられます。',
        confirmLabel: '復元する',
        destructive: true,
      );
      if (!ok || !mounted) return;

      setState(() => _busy = true);
      await service.applyRestore(decoded.data);
      invalidateDataFrom(ref);
      if (!mounted) return;
      showSnack(context, 'バックアップを復元しました');
    } on BackupException catch (error) {
      if (mounted) showSnack(context, error.message);
    } catch (error) {
      if (mounted) showSnack(context, '復元に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword({
    required String title,
    required String message,
    bool confirm = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _PasswordDialog(title: title, message: message, confirm: confirm),
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsValueProvider);
    final lastBackup = settings.lastBackupAt;
    final status = ref.watch(backupStatusProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('バックアップ')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (status.shouldWarn) ...[
                _BackupWarning(status: status),
                const SizedBox(height: 12),
              ],
              SectionCard(
                title: '暗号化して書き出す',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'パスワードから鍵を導出し（PBKDF2-HMAC-SHA256）、'
                      'AES-256-GCM で暗号化したファイルを作ります。'
                      '書き出し先は共有シートであなたが選びます。',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lastBackup == null
                          ? 'まだ書き出していません'
                          : '前回: ${Fmt.displayDate(lastBackup)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('バックアップを書き出す'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'バックアップから復元',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '復元すると、いま端末にあるデータはすべて置き換わります。'
                      '機種変更のときは、新しい端末で復元してください。',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('ファイルを選んで復元'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: '仕様',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _spec('拡張子', '.${BackupService.fileExtension}'),
                    _spec('鍵導出', 'PBKDF2-HMAC-SHA256'),
                    _spec(
                      '反復回数',
                      '${BackupService.kdfIterations} 回',
                    ),
                    _spec('暗号化', 'AES-256-GCM（改ざん検知あり）'),
                    _spec('圧縮', 'gzip'),
                    const SizedBox(height: 8),
                    Text(
                      'パスワードを忘れると復元できません。アプリ側にも復旧手段はありません。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
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

  Widget _spec(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 80,
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

/// 端末を失えばデータは戻らない。その事実をぼかさずに伝える。
class _BackupWarning extends StatelessWidget {
  const _BackupWarning({required this.status});

  final BackupStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.error),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status == BackupStatus.never
                      ? 'まだバックアップがありません'
                      : '$kBackupReminderDays 日以上バックアップしていません',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'データは端末の中にしかありません。端末を失うと復元できません。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.message,
    required this.confirm,
  });

  final String title;
  final String message;
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _obscure = true;
  String? _error;

  static const int _minLength = 8;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _password.text;
    if (value.length < _minLength) {
      setState(() => _error = '$_minLength 文字以上にしてください');
      return;
    }
    if (widget.confirm && value != _repeat.text) {
      setState(() => _error = 'パスワードが一致しません');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'パスワード',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _repeat,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'パスワード（確認）'),
            ),
          ],
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
        FilledButton(onPressed: _submit, child: const Text('決定')),
      ],
    );
  }
}
