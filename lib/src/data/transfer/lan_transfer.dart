import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// LAN 経由で引き継ぐときに、QR へ載せる待ち合わせ情報。
///
/// 中身は「どこへ取りに行けばよいか」だけで、鍵は含まない。
/// 実データは暗号化済みなので、この QR を読まれても内容は漏れない。
///
/// 形式は `PACL1|<token>|<host,host,...>|<port>` の 1 行。
/// 50 文字前後にしかならないので QR 1 枚で収まる。
@immutable
class LanHandshake {
  const LanHandshake({
    required this.token,
    required this.hosts,
    required this.port,
  });

  static const String magic = 'PACL1';
  static const String _separator = '|';

  /// 同じ LAN の別端末が先に取りに来るのを防ぐためのワンタイム経路。
  /// 秘匿性の主役ではない（それは引き継ぎコードの役目）。
  final String token;

  /// 送信側の IPv4 アドレス候補。Wi-Fi と VPN が同時に有効な場合など、
  /// 正解が 1 つに決まらないため複数載せて受信側に順に試させる。
  final List<String> hosts;

  final int port;

  String encode() =>
      [magic, token, hosts.join(','), '$port'].join(_separator);

  /// 読み取った文字列を待ち合わせ情報として解釈する。違えば null。
  static LanHandshake? parse(String raw) {
    final parts = raw.split(_separator);
    if (parts.length != 4 || parts[0] != magic) return null;

    final port = int.tryParse(parts[3]);
    if (port == null || port <= 0 || port > 65535) return null;
    if (parts[1].isEmpty) return null;

    final hosts = parts[2].split(',').where((h) => h.isNotEmpty).toList();
    if (hosts.isEmpty) return null;

    return LanHandshake(token: parts[1], hosts: hosts, port: port);
  }
}

/// 旧端末側。暗号化済みのデータを LAN に置いて、取りに来るのを待つ。
///
/// 外部へ出ていく通信はしない。同じネットワークにいる相手からの
/// 取得要求に応えるだけで、ルーターの外には出ない。
class LanTransferServer {
  LanTransferServer._(this._server, this.handshake, this._payload);

  /// 取りに来ないまま放置された場合に、待ち受けを畳むまでの時間。
  static const Duration idleTimeout = Duration(minutes: 5);

  static const String _tokenAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static const int _tokenLength = 16;

  final HttpServer _server;
  final Uint8List _payload;
  final LanHandshake handshake;

  final StreamController<void> _delivered = StreamController<void>.broadcast();
  Timer? _idleTimer;

  /// データを渡し終えるたびに通知する。受信側が途中で失敗してやり直す
  /// ことがあるので、1 回で閉じずに何度でも応じる。
  Stream<void> get onDelivered => _delivered.stream;

  /// 待ち受けを開始する。空きポートは OS に選ばせる。
  static Future<LanTransferServer> start(
    Uint8List payload, {
    InternetAddress? bindAddress,
    List<String>? hosts,
  }) async {
    final resolvedHosts = hosts ?? await localAddresses();
    if (resolvedHosts.isEmpty) {
      throw const LanTransferException('この端末が LAN に接続されていません');
    }

    final server = await HttpServer.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
    );
    final handshake = LanHandshake(
      token: _randomToken(),
      hosts: resolvedHosts,
      port: server.port,
    );

    final instance = LanTransferServer._(server, handshake, payload);
    instance._listen();
    return instance;
  }

  void _listen() {
    _resetIdleTimer();
    _server.listen((request) async {
      // トークンが違えば何も教えない。存在自体を伏せるため 404 で返す。
      if (request.method != 'GET' ||
          request.uri.path != '/${handshake.token}') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      _resetIdleTimer();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary
        ..headers.contentLength = _payload.length
        ..add(_payload);
      await request.response.close();
      if (!_delivered.isClosed) _delivered.add(null);
    }, onError: (Object error) => debugPrint('LAN transfer server: $error'));
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () => unawaited(stop()));
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_delivered.isClosed) await _delivered.close();
    await _server.close(force: true);
  }

  /// 相手が接続してくる可能性のある自分の IPv4 アドレス。
  ///
  /// プライベートアドレスを先に並べる。VPN やエミュレータの仮想 NIC が
  /// 混ざると先頭が正解でないことがあるため、候補は捨てずに全部返す。
  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final addresses = [
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ];
    addresses.sort((a, b) => _hostRank(a).compareTo(_hostRank(b)));
    return addresses;
  }

  /// 家庭やオフィスの Wi-Fi で使われる帯を優先する。
  static int _hostRank(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    final match = RegExp(r'^172\.(\d+)\.').firstMatch(address);
    if (match != null) {
      final second = int.parse(match.group(1)!);
      if (second >= 16 && second <= 31) return 2;
    }
    return 3;
  }

  static String _randomToken() {
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < _tokenLength; i++)
        _tokenAlphabet.codeUnitAt(random.nextInt(_tokenAlphabet.length)),
    ]);
  }
}

/// 新端末側。QR で受け取った待ち合わせ情報をもとにデータを取りに行く。
class LanTransferClient {
  const LanTransferClient._();

  /// 1 つのアドレスを見限るまでの時間。候補を順に試すので短めにする。
  static const Duration attemptTimeout = Duration(seconds: 4);

  /// 想定を超える応答を読み込まないための上限。
  static const int maxPayloadBytes = 8 * 1024 * 1024;

  /// 候補アドレスを順に試し、最初に成功したものを返す。
  static Future<Uint8List> fetch(LanHandshake handshake) async {
    Object? lastError;

    for (final host in handshake.hosts) {
      try {
        return await _fetchFrom(host, handshake);
      } catch (error) {
        lastError = error;
        debugPrint('LAN transfer: $host failed with $error');
      }
    }

    throw LanTransferException(
      '古い端末に接続できませんでした。'
      '2 台が同じ Wi-Fi に繋がっているか確認してください。'
      'ルーター側で端末どうしの通信が禁止されている場合は、QR だけで送る方法に切り替えてください。'
      '${lastError == null ? '' : '\n\n$lastError'}',
    );
  }

  static Future<Uint8List> _fetchFrom(
    String host,
    LanHandshake handshake,
  ) async {
    final client = HttpClient()..connectionTimeout = attemptTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:${handshake.port}/${handshake.token}'))
          .timeout(attemptTimeout);
      final response = await request.close().timeout(attemptTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw LanTransferException('応答が異常です (${response.statusCode})');
      }
      if (response.contentLength > maxPayloadBytes) {
        throw const LanTransferException('データが大きすぎます');
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxPayloadBytes) {
          throw const LanTransferException('データが大きすぎます');
        }
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}

class LanTransferException implements Exception {
  const LanTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}
