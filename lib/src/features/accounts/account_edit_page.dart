import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../purchase/paywall_page.dart';

class AccountEditPage extends ConsumerStatefulWidget {
  const AccountEditPage({super.key, this.account});

  final Account? account;

  @override
  ConsumerState<AccountEditPage> createState() => _AccountEditPageState();
}

class _AccountEditPageState extends ConsumerState<AccountEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.account?.name ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.account?.note ?? '',
  );
  late AccountType _type = widget.account?.type ?? AccountType.specific;
  bool _saving = false;

  bool get _isNew => widget.account == null;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Free プランの口座数上限をここで一度だけ判定する。
    if (_isNew && !ref.read(canAddAccountProvider)) {
      await _showLimitReached();
      return;
    }

    setState(() => _saving = true);
    final repository = await ref.read(repositoryProvider.future);
    try {
      await repository.upsertAccount(
        (widget.account ??
                Account(name: '', type: AccountType.specific))
            .copyWith(
              name: _name.text.trim(),
              type: _type,
              note: _note.text.trim(),
            ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, '同じ名前と区分の口座が既にあります');
      return;
    }

    invalidateDataFrom(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _showLimitReached() async {
    final go = await confirmDialog(
      context,
      title: 'Free プランの上限に達しました',
      message:
          'Free プランで登録できる口座は ${FreePlanLimits.maxAccounts} つまでです。'
          'Pro（買い切り）にすると無制限に登録できます。',
      confirmLabel: 'Pro を見る',
    );
    if (go && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PaywallPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '口座を追加' : '口座を編集')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: '口座名',
                hintText: 'SBI証券 / 楽天銀行 など',
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '口座名を入力してください' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '区分'),
              items: [
                for (final type in AccountType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) =>
                  setState(() => _type = value ?? AccountType.other),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'メモ（任意）',
                hintText: '用途や運用方針など',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isNew ? '追加する' : '保存する'),
            ),
          ],
        ),
      ),
    );
  }
}
