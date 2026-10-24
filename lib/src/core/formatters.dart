import 'package:intl/intl.dart';

/// 金額・日付の表示フォーマット。すべて日本語ロケール固定。
class Fmt {
  const Fmt._();

  static final NumberFormat _integer = NumberFormat.decimalPattern('ja_JP');
  static final NumberFormat _percent = NumberFormat('#0.0', 'ja_JP');
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _displayDate = DateFormat('yyyy年M月d日', 'ja_JP');
  static final DateFormat _displayMonth = DateFormat('yyyy年M月', 'ja_JP');
  static final DateFormat _shortMonth = DateFormat('M月', 'ja_JP');
  static final DateFormat _fileStamp = DateFormat('yyyyMMdd-HHmmss');

  /// 「¥1,234,567」
  static String yen(num value) => '¥${_integer.format(value)}';

  /// 符号付きの差分。「+¥12,300」「-¥4,500」
  static String signedYen(num value) {
    if (value == 0) return '±¥0';
    final sign = value > 0 ? '+' : '-';
    return '$sign¥${_integer.format(value.abs())}';
  }

  /// 桁区切りのみ。入力欄などで使用。
  static String number(num value) => _integer.format(value);

  /// グラフ軸向けの短縮表記。「1.2億」「340万」「5,000」
  static String compactYen(num value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 100000000) {
      return '$sign${(abs / 100000000).toStringAsFixed(abs >= 1000000000 ? 0 : 1)}億';
    }
    if (abs >= 10000) {
      return '$sign${(abs / 10000).toStringAsFixed(abs >= 1000000 ? 0 : 1)}万';
    }
    return '$sign${_integer.format(abs)}';
  }

  /// 「12.3%」
  static String percent(double ratio) => '${_percent.format(ratio * 100)}%';

  /// DB 保存用の ISO8601 日付（YYYY-MM-DD）。
  static String isoDate(DateTime date) => _isoDate.format(date);

  static String displayDate(DateTime date) => _displayDate.format(date);

  static String displayMonth(DateTime date) => _displayMonth.format(date);

  static String shortMonth(DateTime date) => _shortMonth.format(date);

  static String year(DateTime date) => '${date.year}年';

  static String fileStamp(DateTime date) => _fileStamp.format(date);

  /// 「2026-07-28」形式の文字列を日付に戻す。
  static DateTime parseIsoDate(String value) => DateTime.parse(value);
}

/// 時刻成分を落とした日付。DB のキーと一致させるために必ず経由する。
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// その月の 1 日。
DateTime monthStart(DateTime value) => DateTime(value.year, value.month);

/// その年の 1 月 1 日。
DateTime yearStart(DateTime value) => DateTime(value.year);
