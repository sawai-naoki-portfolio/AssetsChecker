import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

/// CSV から読み取った 1 銘柄分の評価額。
@immutable
class ParsedHolding {
  const ParsedHolding({
    required this.name,
    required this.amount,
    this.section = '',
    this.categoryGuess,
  });

  /// 銘柄名・ファンド名。
  final String name;

  /// 評価額（円、整数）。
  final int amount;

  /// CSV 内の見出し行（「株式（現物／特定預り）」など）。
  final String section;

  /// セクションや銘柄名から推定したカテゴリ名。
  final String? categoryGuess;
}

@immutable
class CsvParseResult {
  const CsvParseResult({
    required this.format,
    required this.holdings,
    this.warnings = const [],
  });

  /// 判定した CSV の書式名。
  final String format;
  final List<ParsedHolding> holdings;
  final List<String> warnings;

  int get total => holdings.fold(0, (sum, h) => sum + h.amount);

  bool get isEmpty => holdings.isEmpty;
}

/// 証券会社の保有商品 CSV を端末内で解析する。
///
/// 各社でフォーマットが異なるうえ年に数回変わるため、列名を固定で決め打ちせず
/// 「銘柄名らしい列」と「評価額らしい列」をヘッダー行から動的に探す方式にしている。
class BrokerageCsvParser {
  const BrokerageCsvParser();

  static const List<String> _nameHeaders = [
    '銘柄名',
    'ファンド名',
    '商品名',
    '銘柄',
    '名称',
    '資産名',
    'ファンド',
    '通貨ペア',
  ];

  /// 評価額列の候補。前にあるものほど優先度が高い。
  static const List<String> _valueHeaders = [
    '時価評価額',
    '評価額',
    '評価金額',
    '時価残高',
    '円換算評価額',
    '資産評価額',
    '残高',
    '金額',
  ];

  static const Map<String, List<String>> _categoryKeywords = {
    '米国株': [
      '米国株',
      '外国株',
      '海外株',
      '外株',
      'us株',
      '米株',
      'adr',
      '海外etf',
      '外国etf',
    ],
    '日本株': ['国内株', '日本株', '株式', '現物', '東証', 'reit'],
    '投資信託': ['投資信託', '投信', 'ファンド', 'ｉｄｅｃｏ', 'ideco', '積立'],
    '債券': ['債券', '国債', '社債', 'ボンド'],
    '暗号資産': [
      '暗号資産',
      '仮想通貨',
      'ビットコイン',
      'btc',
      'eth',
      'イーサ',
      'crypto',
    ],
    '現金・預金': [
      '預り金',
      '預金',
      '現金',
      'mrf',
      'mmf',
      '円貨',
      '普通預金',
      '待機資金',
      'buying power',
    ],
  };

  CsvParseResult parse(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // 空行はセクションの区切りとして使うので捨てない。区切り文字の自動判定も
    // 見出し行の存在で誤検出しうるためカンマ固定にしている。
    final rows = Csv(
      fieldDelimiter: ',',
      autoDetect: false,
      skipEmptyLines: false,
      dynamicTyping: false,
    ).decode(normalized);

    final format = _detectFormat(normalized);
    final holdings = <ParsedHolding>[];
    final warnings = <String>[];

    var section = '';
    int? nameIndex;
    int? valueIndex;
    var skippedRows = 0;

    for (final raw in rows) {
      final cells = raw.map((c) => (c ?? '').toString().trim()).toList();
      final filled = cells.where((c) => c.isNotEmpty).toList();

      if (filled.isEmpty) {
        // 空行はテーブルの区切り。次のヘッダーを探し直す。
        nameIndex = null;
        valueIndex = null;
        continue;
      }

      // セルが 1 つだけの行は見出しとみなす（SBI 形式の「株式（現物）」など）。
      if (filled.length == 1) {
        section = filled.first;
        nameIndex = null;
        valueIndex = null;
        continue;
      }

      final header = _readHeader(cells);
      if (header != null) {
        nameIndex = header.nameIndex;
        valueIndex = header.valueIndex;
        continue;
      }

      if (nameIndex == null || valueIndex == null) continue;
      if (cells.length <= nameIndex || cells.length <= valueIndex) continue;

      final name = cells[nameIndex];
      final amount = parseAmount(cells[valueIndex]);
      if (name.isEmpty) continue;
      if (amount == null) {
        skippedRows++;
        continue;
      }
      if (_looksLikeTotalRow(name)) continue;

      holdings.add(
        ParsedHolding(
          name: name,
          amount: amount,
          section: section,
          categoryGuess: guessCategory('$section $name'),
        ),
      );
    }

    if (holdings.isEmpty) {
      warnings.add(
        '評価額の列を見つけられませんでした。'
        '「評価額」「時価評価額」などの見出しを含む CSV を選んでください。',
      );
    }
    if (skippedRows > 0) {
      warnings.add('$skippedRows 行は金額として読めなかったため除外しました。');
    }

    return CsvParseResult(
      format: format,
      holdings: holdings,
      warnings: warnings,
    );
  }

  /// 「1,234,567」「¥1,234」「1234.5」「△1,000」などを整数に変換する。
  /// 金額として解釈できない場合は null。
  static int? parseAmount(String raw) {
    if (raw.isEmpty) return null;

    var text = _toHalfWidth(raw).trim();
    if (text.isEmpty || text == '-' || text == '--' || text == '---') {
      return null;
    }

    var negative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      negative = true;
      text = text.substring(1, text.length - 1);
    }
    if (text.startsWith('△') || text.startsWith('▲') || text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    }

    text = text.replaceAll(RegExp(r'[,\s¥￥円]'), '');
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) return null;

    final value = double.tryParse(text);
    if (value == null) return null;
    final rounded = value.round();
    return negative ? -rounded : rounded;
  }

  /// セクション名や銘柄名からカテゴリを推定する。該当なしなら null。
  static String? guessCategory(String text) {
    final haystack = _toHalfWidth(text).toLowerCase();
    // 「現金」系を先に判定する（「預り金」は株式セクション内にも現れるため）。
    for (final category in const ['現金・預金', '暗号資産', '債券', '投資信託', '米国株', '日本株']) {
      for (final keyword in _categoryKeywords[category]!) {
        if (haystack.contains(keyword)) return category;
      }
    }
    return null;
  }

  /// ヘッダー行から「銘柄名の列」と「評価額の列」を探す。
  ///
  /// 完全一致を部分一致より優先する。そうしないと SBI の「銘柄コード」列が
  /// 「銘柄」列より先に名前列として選ばれてしまう。
  _HeaderMatch? _readHeader(List<String> cells) {
    int? nameIndex;
    int? valueIndex;
    var bestNameScore = 1 << 30;
    var bestValueScore = 1 << 30;

    for (var i = 0; i < cells.length; i++) {
      final cell = _toHalfWidth(cells[i]);
      if (cell.isEmpty) continue;

      final nameScore = _headerScore(cell, _nameHeaders);
      if (nameScore != null && nameScore < bestNameScore) {
        bestNameScore = nameScore;
        nameIndex = i;
      }

      final valueScore = _headerScore(cell, _valueHeaders);
      if (valueScore != null && valueScore < bestValueScore) {
        bestValueScore = valueScore;
        valueIndex = i;
      }
    }

    if (nameIndex == null || valueIndex == null) return null;
    if (nameIndex == valueIndex) return null;
    return _HeaderMatch(nameIndex: nameIndex, valueIndex: valueIndex);
  }

  /// 小さいほど良い一致。候補リストの順位 × 2、部分一致なら +1。
  static int? _headerScore(String cell, List<String> candidates) {
    for (var rank = 0; rank < candidates.length; rank++) {
      final candidate = candidates[rank];
      if (cell == candidate) return rank * 2;
      if (cell.contains(candidate)) return rank * 2 + 1;
    }
    return null;
  }

  static bool _looksLikeTotalRow(String name) {
    const totals = ['合計', '総合計', '小計', '評価額合計', 'total'];
    final normalized = _toHalfWidth(name).toLowerCase();
    return totals.any((t) => normalized == t.toLowerCase());
  }

  String _detectFormat(String text) {
    final head = text.length > 4000 ? text.substring(0, 4000) : text;
    if (head.contains('SBI') || head.contains('株式（現物')) return 'SBI証券';
    if (head.contains('楽天') || head.contains('時価評価額[円]')) return '楽天証券';
    if (head.contains('マネックス')) return 'マネックス証券';
    if (head.contains('松井')) return '松井証券';
    if (head.contains('auカブコム') || head.contains('カブコム')) {
      return 'auカブコム証券';
    }
    return '汎用CSV';
  }

  /// 全角英数字・記号を半角へ。証券会社ごとの表記ゆれを吸収する。
  static String _toHalfWidth(String input) {
    final buffer = StringBuffer();
    for (final unit in input.runes) {
      if (unit >= 0xFF01 && unit <= 0xFF5E) {
        buffer.writeCharCode(unit - 0xFEE0);
      } else if (unit == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }
}

@immutable
class _HeaderMatch {
  const _HeaderMatch({required this.nameIndex, required this.valueIndex});

  final int nameIndex;
  final int valueIndex;
}
