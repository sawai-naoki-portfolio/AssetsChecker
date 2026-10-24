import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/theme.dart';
import 'db_key_store.dart';

/// AES-256 で暗号化された SQLite (SQLCipher) を開くためのゲートウェイ。
class AppDatabase {
  AppDatabase({DbKeyStore? keyStore}) : _keyStore = keyStore ?? DbKeyStore();

  static const String fileName = 'privacy_asset_checker.db';

  /// v2: 入金額を記録する snapshot_meta を追加。
  static const int schemaVersion = 2;

  final DbKeyStore _keyStore;
  Database? _db;

  Database get instance {
    final db = _db;
    if (db == null) {
      throw StateError('AppDatabase.open() が呼ばれていません');
    }
    return db;
  }

  Future<Database> open() async {
    if (_db != null) return _db!;

    final password = await _keyStore.obtainDatabaseKey();
    final path = p.join(await getDatabasesPath(), fileName);

    _db = await openDatabase(
      path,
      version: schemaVersion,
      password: password,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seedCategories(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSnapshotMeta(db);
        }
      },
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_accounts_identity ON accounts(name, account_type)',
    );

    await db.execute('''
      CREATE TABLE asset_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
        recorded_on TEXT NOT NULL,
        amount INTEGER NOT NULL,
        memo TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'manual'
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_records_identity '
      'ON asset_records(recorded_on, account_id, category_id)',
    );
    await db.execute(
      'CREATE INDEX idx_records_date ON asset_records(recorded_on)',
    );

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createSnapshotMeta(db);
  }

  /// 日付単位の付随情報。いまは「その期間の入金額」だけを持つ。
  ///
  /// 評価額の増減を「入金によるもの」と「運用によるもの」に分けるために使う。
  static Future<void> _createSnapshotMeta(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS snapshot_meta (
        recorded_on TEXT PRIMARY KEY,
        contribution INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// 初回起動時のカテゴリ。ユーザーは後から自由に追加・改名できる。
  static Future<void> _seedCategories(Database db) async {
    const names = [
      '日本株',
      '米国株',
      '投資信託',
      '債券',
      '暗号資産',
      '現金・預金',
      'その他',
    ];
    final batch = db.batch();
    for (var i = 0; i < names.length; i++) {
      batch.insert('categories', {
        'name': names[i],
        'color': AppTheme.categoryPalette[i % AppTheme.categoryPalette.length]
            .toARGB32(),
        'sort_order': i,
      });
    }
    await batch.commit(noResult: true);
  }
}
