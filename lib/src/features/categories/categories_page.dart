import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// カテゴリの追加・改名・削除。
///
/// 色はパレットから自動で割り当てる。ユーザーに色を選ばせても
/// グラフが読みやすくなるわけではなく、破綻する配色を選べるようになるだけなので
/// 編集手段はあえて用意していない。
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('カテゴリ管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('カテゴリを追加'),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('読み込みに失敗しました: $error')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'グラフの色は、見分けやすさを保つためにアプリ側で自動的に割り当てます。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final category in list) ...[
              Card(
                child: ListTile(
                  onTap: () => _edit(context, ref, category),
                  leading: ColorDot(color: category.color, size: 18),
                  title: Text(category.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _delete(context, ref, category),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AssetCategory? category,
  ) async {
    final existing = await ref.read(categoriesProvider.future);
    if (!context.mounted) return;

    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(category: category),
    );
    if (name == null || name.isEmpty) return;

    final repository = await ref.read(repositoryProvider.future);
    try {
      await repository.upsertCategory(
        category?.copyWith(name: name) ??
            AssetCategory(
              name: name,
              color: AppTheme
                  .categoryPalette[existing.length %
                      AppTheme.categoryPalette.length],
            ),
      );
    } catch (_) {
      if (context.mounted) showSnack(context, '同じ名前のカテゴリが既にあります');
      return;
    }
    invalidateDataFrom(ref);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AssetCategory category,
  ) async {
    final ok = await confirmDialog(
      context,
      title: '「${category.name}」を削除',
      message: 'このカテゴリを削除します。記録で使われている場合は削除できません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;

    final repository = await ref.read(repositoryProvider.future);
    final deleted = await repository.deleteCategory(category.id!);
    invalidateDataFrom(ref);
    if (!context.mounted) return;
    showSnack(context, deleted ? 'カテゴリを削除しました' : '記録で使われているため削除できません');
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({this.category});

  final AssetCategory? category;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.category == null ? 'カテゴリを追加' : 'カテゴリ名を変更',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'カテゴリ名'),
              onSubmitted: (value) =>
                  Navigator.of(context).pop(value.trim()),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_name.text.trim()),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
