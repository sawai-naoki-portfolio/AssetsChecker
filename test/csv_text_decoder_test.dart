import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_asset_checker/src/data/csv/csv_text_decoder.dart';

void main() {
  /// 端末のネイティブ変換の代わりに、呼ばれたことだけを記録するスタブ。
  late List<String> requestedCharsets;
  late CsvTextDecoder decoder;

  setUp(() {
    requestedCharsets = [];
    decoder = CsvTextDecoder(
      decodeWith: (charset, data) async {
        requestedCharsets.add(charset);
        return '銘柄,評価額';
      },
    );
  });

  test('UTF-8 BOM を取り除いて読む', () async {
    final bytes = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('銘柄,評価額'),
    ]);
    final result = await decoder.decode(bytes);

    expect(result.text, '銘柄,評価額');
    expect(result.encoding, 'UTF-8 (BOM)');
    expect(requestedCharsets, isEmpty);
  });

  test('BOM なしの UTF-8 をそのまま読む', () async {
    final result = await decoder.decode(
      Uint8List.fromList(utf8.encode('銘柄,評価額\nトヨタ,300000')),
    );

    expect(result.encoding, 'UTF-8');
    expect(result.text, contains('トヨタ'));
    expect(requestedCharsets, isEmpty);
  });

  test('ASCII のみの CSV も UTF-8 として扱う', () async {
    final result = await decoder.decode(
      Uint8List.fromList(ascii.encode('name,value\nfoo,100')),
    );

    expect(result.encoding, 'UTF-8');
    expect(requestedCharsets, isEmpty);
  });

  test('UTF-8 として不正なら Shift-JIS へ切り替える', () async {
    // 「銘柄」の Shift-JIS バイト列。UTF-8 としてはデコードできない。
    final shiftJisBytes = Uint8List.fromList([
      0x96,
      0x7A,
      0x95,
      0x40,
      0x2C,
      0x8C,
      0x5A,
    ]);
    final result = await decoder.decode(shiftJisBytes);

    expect(result.encoding, 'Shift-JIS');
    expect(requestedCharsets.first, 'Shift_JIS');
  });

  test('どの文字コードでも読めない場合は代替解釈にフォールバックする', () async {
    final failing = CsvTextDecoder(
      decodeWith: (charset, data) async => throw StateError('unsupported'),
    );
    final result = await failing.decode(Uint8List.fromList([0x96, 0x7A]));

    expect(result.encoding, contains('不明'));
    expect(result.text, isNotEmpty);
  });
}
