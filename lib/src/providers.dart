import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'data/backup/backup_service.dart';
import 'data/csv/csv_text_decoder.dart';
import 'data/db/app_database.dart';
import 'data/db/db_key_store.dart';
import 'data/models/app_settings.dart';
import 'data/models/models.dart';
import 'data/repositories/asset_repository.dart';
import 'dev/demo_seed.dart';
import 'notifications/reminder_service.dart';
import 'security/biometric_service.dart';

// ------------------------------------------------------------------ 基盤

final dbKeyStoreProvider = Provider<DbKeyStore>((ref) => DbKeyStore());

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(keyStore: ref.watch(dbKeyStoreProvider));
  ref.onDispose(db.close);
  return db;
});

/// 暗号化 DB を開いてリポジトリを返す。UI はこれの解決を待ってから描画される。
final repositoryProvider = FutureProvider<AssetRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider).open();
  final repository = AssetRepository(database);
  // ドキュメント用のデモデータ投入。リリースビルドでは何もしない。
  await DemoSeed.maybeSeed(repository, ref.watch(dbKeyStoreProvider));
  return repository;
});

/// 書き込みのたびに増やして、読み取り側の Provider を再実行させる。
final dbRevisionProvider = StateProvider<int>((ref) => 0);

/// Widget 側から書き込み後に呼ぶ。
void invalidateDataFrom(WidgetRef ref) {
  ref.read(dbRevisionProvider.notifier).state++;
}

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(),
);

final csvDecoderProvider = Provider<CsvTextDecoder>(
  (ref) => const CsvTextDecoder(),
);

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final repository = await ref.watch(repositoryProvider.future);
  return BackupService(repository);
});

// ------------------------------------------------------------------ データ

final categoriesProvider = FutureProvider<List<AssetCategory>>((ref) async {
  ref.watch(dbRevisionProvider);
  final repository = await ref.watch(repositoryProvider.future);
  return repository.listCategories();
});

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  ref.watch(dbRevisionProvider);
  final repository = await ref.watch(repositoryProvider.future);
  return repository.listAccounts();
});

final snapshotDatesProvider = FutureProvider<List<DateTime>>((ref) async {
  ref.watch(dbRevisionProvider);
  final repository = await ref.watch(repositoryProvider.future);
  return repository.listSnapshotDates();
});

/// アセットアロケーション画面が表示する対象日。null なら最新。
final selectedSnapshotDateProvider = StateProvider<DateTime?>((ref) => null);

final currentSnapshotProvider = FutureProvider<AssetSnapshot?>((ref) async {
  ref.watch(dbRevisionProvider);
  final repository = await ref.watch(repositoryProvider.future);
  final selected = ref.watch(selectedSnapshotDateProvider);
  if (selected == null) return repository.latestSnapshot();
  return repository.loadSnapshot(selected);
});

/// 対象日のひとつ前のスナップショット。前月比の算出に使う。
final previousSnapshotProvider = FutureProvider<AssetSnapshot?>((ref) async {
  final current = await ref.watch(currentSnapshotProvider.future);
  if (current == null) return null;
  final repository = await ref.watch(repositoryProvider.future);
  return repository.latestSnapshotBefore(current.date);
});

final trendProvider = FutureProvider<List<TrendPoint>>((ref) async {
  ref.watch(dbRevisionProvider);
  final repository = await ref.watch(repositoryProvider.future);
  return repository.trend();
});

// ------------------------------------------------------------------ 設定

final settingsProvider = FutureProvider<AppSettings>((ref) async {
  ref.watch(dbRevisionProvider);
  final repository = await ref.watch(repositoryProvider.future);
  return AppSettings.fromMap(await repository.loadSettings());
});

/// 同期的に読みたい場所（設定画面のトグルなど）向けの既定値つきビュー。
final settingsValueProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsProvider).valueOrNull ?? const AppSettings(),
);

/// バックアップの督促状態。
final backupStatusProvider = Provider<BackupStatus>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  final dates = ref.watch(snapshotDatesProvider).valueOrNull;
  if (settings == null || dates == null) return BackupStatus.notNeeded;
  return evaluateBackupStatus(
    lastBackupAt: settings.lastBackupAt,
    hasRecords: dates.isNotEmpty,
  );
});

// ------------------------------------------------------------------ 課金

/// Pro（買い切り）の解放状態。バックアップ復元で持ち込まれないよう
/// DB ではなく Keychain / Keystore に保存している。
class ProStatus extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(dbKeyStoreProvider).isProUnlocked();

  Future<void> unlock() async {
    await ref.read(dbKeyStoreProvider).setProUnlocked(true);
    state = const AsyncData(true);
  }

  Future<void> relock() async {
    await ref.read(dbKeyStoreProvider).setProUnlocked(false);
    state = const AsyncData(false);
  }
}

final proStatusProvider = AsyncNotifierProvider<ProStatus, bool>(
  ProStatus.new,
);

final isProProvider = Provider<bool>(
  (ref) => ref.watch(proStatusProvider).valueOrNull ?? false,
);

/// 口座をもう 1 つ追加できるか。
final canAddAccountProvider = Provider<bool>((ref) {
  if (ref.watch(isProProvider)) return true;
  final accounts = ref.watch(accountsProvider).valueOrNull;
  if (accounts == null) return true;
  return accounts.length < FreePlanLimits.maxAccounts;
});
