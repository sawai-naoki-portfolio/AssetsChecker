import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SQLCipher の復号キーを OS の安全領域（iOS Keychain / Android Keystore）で
/// 管理する。キーはアプリのコードにも DB にも一切残さない。
class DbKeyStore {
  DbKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? defaultStorage;

  static const String _keyName = 'pac_db_key_v1';
  static const String _proEntitlementKey = 'pac_pro_entitlement_v1';

  /// iOS では `first_unlock_this_device` を使い、iCloud キーチェーン経由で
  /// 他端末へ複製されないようにする。Android は既定の
  /// AES-GCM + Keystore ラップを使用。
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _storage;

  /// 既存のキーを返す。存在しなければ 256bit の乱数キーを生成して保存する。
  Future<String> obtainDatabaseKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateKey();
    await _storage.write(key: _keyName, value: generated);
    return generated;
  }

  Future<bool> hasDatabaseKey() async => _storage.containsKey(key: _keyName);

  /// Pro 購入状態。復元されたバックアップから課金状態が持ち込まれないよう、
  /// DB ではなく Keychain / Keystore 側に置く。
  Future<bool> isProUnlocked() async =>
      (await _storage.read(key: _proEntitlementKey)) == '1';

  Future<void> setProUnlocked(bool value) async {
    if (value) {
      await _storage.write(key: _proEntitlementKey, value: '1');
    } else {
      await _storage.delete(key: _proEntitlementKey);
    }
  }

  /// 全データ削除時に使用。キーを消せば DB ファイルは復号不能になる。
  Future<void> destroyDatabaseKey() => _storage.delete(key: _keyName);

  static String _generateKey() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(bytes);
  }
}
