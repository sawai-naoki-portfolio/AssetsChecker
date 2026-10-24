import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_asset_checker/src/data/backup/backup_service.dart';

Map<String, List<Map<String, Object?>>> _sampleTables() => {
  'categories': [
    {'id': 1, 'name': '日本株', 'color': 0xFF2F80ED, 'sort_order': 0},
  ],
  'accounts': [
    {
      'id': 1,
      'name': 'SBI証券',
      'account_type': 'specific',
      'note': '',
      'sort_order': 0,
      'archived': 0,
    },
  ],
  'asset_records': [
    {
      'id': 1,
      'account_id': 1,
      'category_id': 1,
      'recorded_on': '2026-07-28',
      'amount': 1234567,
      'memo': '',
      'source': 'manual',
    },
  ],
  'app_settings': <Map<String, Object?>>[],
};

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // RFC 7914 / 一般に流通している HMAC-SHA256 のテストベクタ。
    test('c=1 の既知ベクタと一致する', () {
      final key = pbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 32,
      );
      expect(
        key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('c=2 の既知ベクタと一致する', () {
      final key = pbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 2,
        keyLength: 32,
      );
      expect(
        key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('鍵長が 32 バイトを超えても導出できる', () {
      final key = pbkdf2HmacSha256(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 40,
      );
      expect(key.length, 40);
    });
  });

  group('バックアップ封筒', () {
    test('同じパスワードなら往復できる', () async {
      final tables = _sampleTables();
      final bytes = await BackupService.buildEnvelope(tables, 'correct-horse');
      final restored = await BackupService.readEnvelope(bytes, 'correct-horse');

      expect(restored.summary.accountCount, 1);
      expect(restored.summary.recordCount, 1);
      expect(restored.data['asset_records']!.first['amount'], 1234567);
      expect(restored.data['accounts']!.first['name'], 'SBI証券');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('パスワードが違うと復号できない', () async {
      final bytes = await BackupService.buildEnvelope(
        _sampleTables(),
        'correct-horse',
      );
      expect(
        () => BackupService.readEnvelope(bytes, 'wrong-password'),
        throwsA(isA<BackupException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('平文が本文に残っていない', () async {
      final bytes = await BackupService.buildEnvelope(
        _sampleTables(),
        'correct-horse',
      );
      final asText = utf8.decode(bytes);

      expect(asText, isNot(contains('SBI証券')));
      expect(asText, isNot(contains('1234567')));
      expect(asText, contains('privacy-asset-checker-backup'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('別ファイルを渡すと明確なエラーになる', () async {
      expect(
        () => BackupService.readEnvelope(
          Uint8List.fromList(utf8.encode('{"hello":"world"}')),
          'whatever',
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('壊れたファイルを渡すと明確なエラーになる', () async {
      expect(
        () => BackupService.readEnvelope(
          Uint8List.fromList([0, 1, 2, 3]),
          'whatever',
        ),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
