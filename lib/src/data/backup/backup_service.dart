import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../repositories/asset_repository.dart';

/// バックアップの復号に失敗したときに投げる例外。
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// バックアップ内容の要約。復元前の確認ダイアログに表示する。
class BackupSummary {
  const BackupSummary({
    required this.createdAt,
    required this.accountCount,
    required this.recordCount,
    required this.categoryCount,
  });

  final DateTime createdAt;
  final int accountCount;
  final int recordCount;
  final int categoryCount;
}

/// パスワード保護された暗号化バックアップの作成と復元。
///
/// 形式は「PBKDF2-HMAC-SHA256 でパスワードから鍵を導出 →
/// gzip 圧縮した JSON を AES-256-GCM で暗号化 → JSON 封筒に格納」。
/// 生成物は自分で選んだ場所（iCloud Drive / Google Drive など）へ保存する。
class BackupService {
  const BackupService(this._repository);

  static const String formatId = 'privacy-asset-checker-backup';
  static const int formatVersion = 1;
  static const String fileExtension = 'pacbk';

  /// OWASP 推奨水準。端末で 1〜2 秒かかる想定なので必ず別 isolate で回す。
  static const int kdfIterations = 210000;
  static const int _saltLength = 16;
  static const int _ivLength = 12;
  static const int _keyLength = 32;

  final AssetRepository _repository;

  String suggestedFileName(DateTime now) {
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    return 'PrivacyAsset-$stamp.$fileExtension';
  }

  /// 暗号化済みバックアップのバイト列を作る。
  Future<Uint8List> createBackup(String password) async {
    if (password.isEmpty) {
      throw BackupException('パスワードを入力してください');
    }
    return buildEnvelope(await _repository.exportAll(), password);
  }

  /// 復号して中身を検証する（DB には書き込まない）。
  Future<({BackupSummary summary, Map<String, List<Map<String, Object?>>> data})>
  decodeBackup(Uint8List fileBytes, String password) =>
      readEnvelope(fileBytes, password);

  /// 復号したデータで DB を置き換える。
  Future<void> applyRestore(
    Map<String, List<Map<String, Object?>>> data,
  ) async {
    await _repository.importAll(data);
  }

  /// テーブルダンプを暗号化封筒に詰める。DB に依存しないので単体テスト可能。
  static Future<Uint8List> buildEnvelope(
    Map<String, List<Map<String, Object?>>> tables,
    String password,
  ) async {
    final plain = utf8.encode(
      jsonEncode({
        'schemaVersion': formatVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'tables': tables,
      }),
    );
    final compressed = gzip.encode(plain);

    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLength);
    final key = await _deriveKey(password, salt);

    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(compressed, iv: enc.IV(iv));

    final envelope = {
      'format': formatId,
      'version': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'kdf': {
        'algorithm': 'PBKDF2-HMAC-SHA256',
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
      },
      'cipher': {'algorithm': 'AES-256-GCM', 'iv': base64Encode(iv)},
      'compression': 'gzip',
      'payload': base64Encode(encrypted.bytes),
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// 封筒を開いて中身を検証する。DB に依存しないので単体テスト可能。
  static Future<
    ({BackupSummary summary, Map<String, List<Map<String, Object?>>> data})
  >
  readEnvelope(Uint8List fileBytes, String password) async {
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('バックアップファイルとして読み取れませんでした');
    }

    if (envelope['format'] != formatId) {
      throw BackupException('このアプリのバックアップファイルではありません');
    }
    final version = (envelope['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw BackupException('新しいバージョンのアプリで作られたバックアップです。アプリを更新してください');
    }

    final kdf = envelope['kdf'] as Map<String, dynamic>;
    final cipher = envelope['cipher'] as Map<String, dynamic>;
    final salt = base64Decode(kdf['salt'] as String);
    final iterations = (kdf['iterations'] as num).toInt();
    final iv = base64Decode(cipher['iv'] as String);
    final payload = base64Decode(envelope['payload'] as String);

    final key = await _deriveKey(password, salt, iterations: iterations);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );

    List<int> compressed;
    try {
      compressed = encrypter.decryptBytes(
        enc.Encrypted(payload),
        iv: enc.IV(iv),
      );
    } catch (_) {
      // GCM の認証タグ不一致 = パスワード違い、またはファイル破損。
      throw BackupException('パスワードが違うか、ファイルが破損しています');
    }

    final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(gzip.decode(compressed)))
              as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('バックアップの中身を復元できませんでした');
    }

    final tables = (decoded['tables'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        (value as List)
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList(),
      ),
    );

    return (
      summary: BackupSummary(
        createdAt:
            DateTime.tryParse(envelope['createdAt'] as String? ?? '') ??
            DateTime.now(),
        accountCount: tables['accounts']?.length ?? 0,
        recordCount: tables['asset_records']?.length ?? 0,
        categoryCount: tables['categories']?.length ?? 0,
      ),
      data: tables,
    );
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Future<Uint8List> _deriveKey(
    String password,
    List<int> salt, {
    int iterations = kdfIterations,
  }) {
    final passwordBytes = utf8.encode(password);
    final saltBytes = Uint8List.fromList(salt);
    // UI をブロックしないよう別 isolate で計算する。
    return Isolate.run(
      () => pbkdf2HmacSha256(
        password: passwordBytes,
        salt: saltBytes,
        iterations: iterations,
        keyLength: _keyLength,
      ),
    );
  }
}

/// PBKDF2-HMAC-SHA256（RFC 8018）。外部依存を増やさないための最小実装。
Uint8List pbkdf2HmacSha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int keyLength,
}) {
  final hmac = Hmac(sha256, password);
  const blockSize = 32;
  final blocks = (keyLength / blockSize).ceil();
  final output = Uint8List(blocks * blockSize);

  for (var block = 1; block <= blocks; block++) {
    final blockIndex = Uint8List(4)
      ..[0] = (block >> 24) & 0xFF
      ..[1] = (block >> 16) & 0xFF
      ..[2] = (block >> 8) & 0xFF
      ..[3] = block & 0xFF;

    var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
    final accumulated = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < blockSize; j++) {
        accumulated[j] ^= u[j];
      }
    }
    output.setRange((block - 1) * blockSize, block * blockSize, accumulated);
  }

  return Uint8List.sublistView(output, 0, keyLength);
}
