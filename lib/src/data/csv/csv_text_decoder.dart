import 'dart:convert';

import 'package:charset_converter/charset_converter.dart';
import 'package:flutter/foundation.dart';

/// 文字コード判定の結果。
@immutable
class DecodedCsv {
  const DecodedCsv({required this.text, required this.encoding});

  final String text;
  final String encoding;
}

/// 証券会社の CSV は Shift-JIS が主流だが、UTF-8 で出力されるものもある。
/// 端末内で完結させるため、外部サービスに一切問い合わせずに判定する。
class CsvTextDecoder {
  const CsvTextDecoder({Future<String> Function(String, Uint8List)? decodeWith})
    : _decodeWith = decodeWith ?? CharsetConverter.decode;

  final Future<String> Function(String charset, Uint8List data) _decodeWith;

  static const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

  Future<DecodedCsv> decode(Uint8List bytes) async {
    if (_hasPrefix(bytes, _utf8Bom)) {
      return DecodedCsv(
        text: utf8.decode(bytes.sublist(_utf8Bom.length)),
        encoding: 'UTF-8 (BOM)',
      );
    }
    if (_hasPrefix(bytes, const [0xFF, 0xFE])) {
      return DecodedCsv(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
        encoding: 'UTF-16 LE',
      );
    }
    if (_hasPrefix(bytes, const [0xFE, 0xFF])) {
      return DecodedCsv(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
        encoding: 'UTF-16 BE',
      );
    }

    // BOM なし。まず UTF-8 として厳密にデコードし、失敗したら Shift-JIS とみなす。
    // ASCII のみの CSV は UTF-8 として正しく読めるので取りこぼしはない。
    try {
      final text = const Utf8Decoder(allowMalformed: false).convert(bytes);
      return DecodedCsv(text: text, encoding: 'UTF-8');
    } on FormatException {
      // 続けて Shift-JIS を試す。
    }

    for (final charset in const ['Shift_JIS', 'windows-31j', 'MS932']) {
      try {
        final text = await _decodeWith(charset, bytes);
        if (text.isNotEmpty) {
          return DecodedCsv(text: text, encoding: 'Shift-JIS');
        }
      } catch (error) {
        debugPrint('CsvTextDecoder: $charset failed ($error)');
      }
    }

    // 最終手段。文字化けしても行構造だけは読めるようにしておく。
    return DecodedCsv(
      text: const Utf8Decoder(allowMalformed: true).convert(bytes),
      encoding: '不明（UTF-8 として代替解釈）',
    );
  }

  static bool _hasPrefix(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final view = ByteData.sublistView(bytes);
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(view.getUint16(i, littleEndian ? Endian.little : Endian.big));
    }
    return String.fromCharCodes(units);
  }
}
