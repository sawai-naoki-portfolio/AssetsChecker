import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_asset_checker/src/data/transfer/lan_transfer.dart';

Uint8List _bytes(int length, {int seed = 3}) {
  final random = Random(seed);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// ループバックだけで完結する待ち受けを立てる。
Future<LanTransferServer> _localServer(Uint8List payload) =>
    LanTransferServer.start(
      payload,
      bindAddress: InternetAddress.loopbackIPv4,
      hosts: const ['127.0.0.1'],
    );

void main() {
  group('待ち合わせ情報', () {
    test('文字列に直して読み戻せる', () {
      const original = LanHandshake(
        token: 'abcDEF123',
        hosts: ['192.168.1.20', '10.0.0.4'],
        port: 49152,
      );

      final parsed = LanHandshake.parse(original.encode())!;

      expect(parsed.token, original.token);
      expect(parsed.hosts, original.hosts);
      expect(parsed.port, original.port);
    });

    test('QR 1 枚に収まる短さである', () {
      const handshake = LanHandshake(
        token: 'aA1bB2cC3dD4eE5f',
        hosts: ['192.168.100.200', '10.128.64.32'],
        port: 65535,
      );

      expect(handshake.encode().length, lessThan(100));
    });

    test('無関係な QR や壊れた入力は受け付けない', () {
      expect(LanHandshake.parse('https://example.com'), isNull);
      expect(LanHandshake.parse('PACQ1|SESSION1|0|1|AAAA'), isNull);
      expect(LanHandshake.parse('PACL1|token|192.168.1.1'), isNull);
      expect(LanHandshake.parse('PACL1|token|192.168.1.1|ポート'), isNull);
      expect(LanHandshake.parse('PACL1|token|192.168.1.1|70000'), isNull);
      expect(LanHandshake.parse('PACL1||192.168.1.1|8080'), isNull);
      expect(LanHandshake.parse('PACL1|token||8080'), isNull);
    });
  });

  group('LAN 転送', () {
    test('置いたデータをそのまま取得できる', () async {
      final payload = _bytes(64 * 1024);
      final server = await _localServer(payload);
      addTearDown(server.stop);

      final received = await LanTransferClient.fetch(server.handshake);

      expect(received, payload);
    });

    test('トークンが違うと取得できない', () async {
      final server = await _localServer(_bytes(256));
      addTearDown(server.stop);

      final wrongToken = LanHandshake(
        token: 'wrong-token',
        hosts: server.handshake.hosts,
        port: server.handshake.port,
      );

      expect(
        () => LanTransferClient.fetch(wrongToken),
        throwsA(isA<LanTransferException>()),
      );
    });

    test('繋がらない候補があっても、繋がる候補で成功する', () async {
      final payload = _bytes(1024);
      final server = await _localServer(payload);
      addTearDown(server.stop);

      // 先頭は RFC 5737 のテスト用アドレスで、応答しない。
      final withDeadHost = LanHandshake(
        token: server.handshake.token,
        hosts: ['192.0.2.1', ...server.handshake.hosts],
        port: server.handshake.port,
      );

      expect(await LanTransferClient.fetch(withDeadHost), payload);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('受信側がやり直しても、もう一度渡せる', () async {
      final payload = _bytes(2048);
      final server = await _localServer(payload);
      addTearDown(server.stop);

      expect(await LanTransferClient.fetch(server.handshake), payload);
      expect(await LanTransferClient.fetch(server.handshake), payload);
    });

    test('渡し終えたことを通知する', () async {
      final server = await _localServer(_bytes(128));
      addTearDown(server.stop);
      final delivered = server.onDelivered.first;

      await LanTransferClient.fetch(server.handshake);

      await expectLater(delivered, completes);
    });

    test('停止すると接続できなくなる', () async {
      final server = await _localServer(_bytes(128));
      final handshake = server.handshake;
      await server.stop();

      expect(
        () => LanTransferClient.fetch(handshake),
        throwsA(isA<LanTransferException>()),
      );
    });
  });
}
