import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_asset_checker/src/data/transfer/qr_transfer_codec.dart';

Uint8List _bytes(int length, {int seed = 7}) {
  final random = Random(seed);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// 受信側が全フレームを読み切った状況を作る。
Uint8List _roundTrip(Uint8List payload, {Iterable<int>? order}) {
  final frames = QrTransferCodec.encode(
    payload,
    sessionId: QrTransferCodec.newSessionId(),
  );
  final assembler = QrTransferAssembler();
  for (final index in order ?? List<int>.generate(frames.length, (i) => i)) {
    expect(assembler.add(frames[index]), isTrue);
  }
  expect(assembler.isComplete, isTrue);
  return assembler.build();
}

void main() {
  group('QR 分割転送', () {
    test('1 フレームに収まるデータを往復できる', () {
      final payload = _bytes(120);
      expect(_roundTrip(payload), payload);
    });

    test('複数フレームに分かれるデータを往復できる', () {
      final payload = _bytes(9000);
      final frames = QrTransferCodec.encode(payload, sessionId: 'ABCDEFGH');
      expect(frames.length, greaterThan(1));
      expect(_roundTrip(payload), payload);
    });

    test('フレームの順序が入れ替わっても復元できる', () {
      final payload = _bytes(9000);
      final frameCount = QrTransferCodec.encode(
        payload,
        sessionId: 'ABCDEFGH',
      ).length;
      final shuffled = List<int>.generate(frameCount, (i) => i)
        ..shuffle(Random(1));
      expect(_roundTrip(payload, order: shuffled), payload);
    });

    test('同じフレームを何度読んでも重複して数えない', () {
      final frames = QrTransferCodec.encode(_bytes(3000), sessionId: 'SESSION1');
      final assembler = QrTransferAssembler();

      assembler.add(frames.first);
      assembler.add(frames.first);
      assembler.add(frames.first);

      expect(assembler.receivedCount, 1);
      expect(assembler.totalCount, frames.length);
      expect(assembler.isComplete, isFalse);
    });

    test('どのフレームからでも全体の枚数が分かる', () {
      final frames = QrTransferCodec.encode(_bytes(6000), sessionId: 'SESSION1');
      final assembler = QrTransferAssembler();

      assembler.add(frames.last);

      expect(assembler.totalCount, frames.length);
    });

    test('無関係な QR は取り込まない', () {
      final assembler = QrTransferAssembler();

      expect(assembler.add('https://example.com'), isFalse);
      expect(assembler.add('PACQ1|SESSION1|0'), isFalse);
      expect(assembler.add('PACQ9|SESSION1|0|1|AAAA'), isFalse);
      expect(assembler.add('PACQ1|SESSION1|x|1|AAAA'), isFalse);
      // 総数を超える番号は壊れた入力として扱う。
      expect(assembler.add('PACQ1|SESSION1|3|2|AAAA'), isFalse);
      expect(assembler.receivedCount, 0);
    });

    test('送信をやり直すと、前のセッションの分は捨てて数え直す', () {
      final payload = _bytes(9000);
      final first = QrTransferCodec.encode(payload, sessionId: 'SESSION1');
      final second = QrTransferCodec.encode(payload, sessionId: 'SESSION2');
      final assembler = QrTransferAssembler();

      assembler.add(first[0]);
      assembler.add(first[1]);
      expect(assembler.receivedCount, 2);

      assembler.add(second[0]);

      expect(assembler.sessionId, 'SESSION2');
      expect(assembler.receivedCount, 1);
    });

    test('揃う前に組み立てようとすると失敗する', () {
      final frames = QrTransferCodec.encode(_bytes(9000), sessionId: 'SESSION1');
      final assembler = QrTransferAssembler();
      assembler.add(frames.first);

      expect(assembler.build, throwsStateError);
    });

    test('フレームは QR に載せられる長さに収まっている', () {
      final frames = QrTransferCodec.encode(_bytes(30000), sessionId: 'ABCDEFGH');

      for (final frame in frames) {
        // 誤り訂正レベル M のバージョン 23（byte モード 946 文字）以内。
        expect(frame.length, lessThanOrEqualTo(946));
      }
    });

    test('引き継ぎコードは紛らわしい文字を含まない', () {
      for (var i = 0; i < 200; i++) {
        final code = QrTransferCodec.newTransferCode();
        expect(code.length, QrTransferCodec.transferCodeLength);
        expect(RegExp(r'^[A-HJ-KM-NP-Z2-9]+$').hasMatch(code), isTrue, reason: code);
      }
    });
  });
}
