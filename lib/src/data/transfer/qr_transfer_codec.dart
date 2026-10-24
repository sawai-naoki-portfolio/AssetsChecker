import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// 端末間引き継ぎで表示する QR 1 枚分のフレーム。
///
/// 1 枚あたりの本文は base64url なので、`|` と衝突しない。
class QrTransferFrame {
  const QrTransferFrame({
    required this.sessionId,
    required this.index,
    required this.total,
    required this.payload,
  });

  final String sessionId;
  final int index;
  final int total;
  final String payload;
}

/// 引き継ぎデータを複数の QR に分割し、受信側で組み立てるための形式。
///
/// フレームは `PACQ1|<session>|<index>|<total>|<base64url>` の 1 行。
/// どのフレームにも全体の情報が入っているため、受信側は何枚目から
/// 読み始めても復元できる。順序も問わない。
///
/// 本文の完全性は AES-256-GCM の認証タグが保証するので、ここでは
/// チェックサムを持たない（[QrTransferCodec] は封筒の中身を知らない）。
class QrTransferCodec {
  const QrTransferCodec._();

  static const String magic = 'PACQ1';
  static const String _separator = '|';

  /// 1 フレームに載せる base64url の文字数。
  ///
  /// ヘッダーを足して 720 文字前後になる。これは誤り訂正レベル M で
  /// バージョン 21〜23 相当で、スマホの画面を 20cm ほどの距離から
  /// 読める密度。増やすとフレーム数は減るが、読み取りが不安定になる。
  static const int payloadCharsPerFrame = 700;

  /// セッション ID の文字数。転送をやり直したときに、前回のフレームと
  /// 混ざらないよう区別するためだけのもので、秘匿性は要らない。
  static const int _sessionIdLength = 8;

  /// 紛らわしい文字（0/O/1/I/L）を除いた引き継ぎコード用の英数字。
  static const String _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// 引き継ぎコードの長さ。31 文字から 8 桁で約 40bit。
  ///
  /// QR を全フレーム撮影された場合の最後の砦なので、BackupService の
  /// PBKDF2 21 万回と合わせて総当たりに耐える長さにしている。
  static const int transferCodeLength = 8;

  /// 暗号化済みの封筒を QR フレームの文字列に分割する。
  static List<String> encode(Uint8List payload, {required String sessionId}) {
    final text = _stripPadding(base64Url.encode(payload));
    final total = max(1, (text.length / payloadCharsPerFrame).ceil());

    return [
      for (var index = 0; index < total; index++)
        [
          magic,
          sessionId,
          '$index',
          '$total',
          text.substring(
            index * payloadCharsPerFrame,
            min((index + 1) * payloadCharsPerFrame, text.length),
          ),
        ].join(_separator),
    ];
  }

  /// 読み取った文字列をフレームとして解釈する。
  ///
  /// このアプリのフレームでなければ `null`。カメラには無関係な QR も
  /// 映り込むので、例外ではなく null で弾く。
  static QrTransferFrame? parseFrame(String raw) {
    final parts = raw.split(_separator);
    if (parts.length != 5 || parts[0] != magic) return null;

    final index = int.tryParse(parts[2]);
    final total = int.tryParse(parts[3]);
    if (index == null || total == null) return null;
    if (total < 1 || index < 0 || index >= total) return null;
    if (parts[1].isEmpty || parts[4].isEmpty) return null;

    return QrTransferFrame(
      sessionId: parts[1],
      index: index,
      total: total,
      payload: parts[4],
    );
  }

  static String newSessionId() => _randomString(_sessionIdLength);

  static String newTransferCode() => _randomString(transferCodeLength);

  static String _randomString(int length) {
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < length; i++)
        _codeAlphabet.codeUnitAt(random.nextInt(_codeAlphabet.length)),
    ]);
  }

  static String _stripPadding(String base64Text) =>
      base64Text.replaceAll('=', '');

  static String _restorePadding(String base64Text) {
    final remainder = base64Text.length % 4;
    if (remainder == 0) return base64Text;
    return base64Text.padRight(base64Text.length + (4 - remainder), '=');
  }

  static Uint8List decodeAll(String base64Text) =>
      base64Url.decode(_restorePadding(base64Text));
}

/// 受信側でフレームを集める。
///
/// 送信側がやり直すとセッション ID が変わるので、その場合は集めた分を
/// 捨てて新しいセッションで数え直す。古いフレームを混ぜたまま組み立てると、
/// 復号は失敗するのに原因が分からなくなるため。
class QrTransferAssembler {
  String? _sessionId;
  int? _total;
  final Map<int, String> _chunks = {};

  String? get sessionId => _sessionId;
  int get receivedCount => _chunks.length;
  int? get totalCount => _total;
  bool get isComplete => _total != null && _chunks.length == _total;

  /// 読み取った文字列を取り込む。取り込めたら true。
  bool add(String raw) {
    final frame = QrTransferCodec.parseFrame(raw);
    if (frame == null) return false;

    if (_sessionId != frame.sessionId) {
      _sessionId = frame.sessionId;
      _total = frame.total;
      _chunks.clear();
    }

    _chunks[frame.index] = frame.payload;
    return true;
  }

  void reset() {
    _sessionId = null;
    _total = null;
    _chunks.clear();
  }

  /// 集めたフレームを結合して復号前のバイト列に戻す。
  ///
  /// [isComplete] が true のときだけ呼ぶこと。
  Uint8List build() {
    final total = _total;
    if (total == null || _chunks.length != total) {
      throw StateError('フレームがすべて揃っていません');
    }
    final buffer = StringBuffer();
    for (var index = 0; index < total; index++) {
      buffer.write(_chunks[index]);
    }
    return QrTransferCodec.decodeAll(buffer.toString());
  }
}
