import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_asset_checker/src/data/csv/brokerage_csv_parser.dart';

/// SBI証券のポートフォリオ CSV に近い構造。
/// セクション見出し → ヘッダー → 明細、が繰り返される。
const _sbiCsv = '''
"口座管理","2026/7/28"

株式（現物/特定預り）
銘柄コード,銘柄,数量,取得単価,現在値,前日比,損益,評価額
7203,トヨタ自動車,100,2500,3000,10,50000,300000
9432,日本電信電話,200,150,180,1,6000,36000

投資信託（金額/特定預り）
ファンド名,数量,取得単価,基準価額,損益,評価額
eMAXIS Slim 米国株式（S&P500）,10000,15000,25000,100000,250000
'''; // 末尾改行あり

/// 楽天証券の保有商品一覧に近い構造。全項目がダブルクォート付き。
const _rakutenCsv = '''
"保有商品一覧","2026/7/28時点"
"銘柄コード","銘柄名","保有数量","平均取得価額","現在値","評価損益[円]","時価評価額[円]"
"1557","SPDR S&P500 ETF","10","70,000","95,000","250,000","950,000"
"","楽天・全米株式インデックス・ファンド","12,345","18,000","24,000","74,000","296,280"
''';

void main() {
  const parser = BrokerageCsvParser();

  group('parseAmount', () {
    test('3 桁区切りと通貨記号を取り除く', () {
      expect(BrokerageCsvParser.parseAmount('1,234,567'), 1234567);
      expect(BrokerageCsvParser.parseAmount('¥1,200'), 1200);
      expect(BrokerageCsvParser.parseAmount('300000円'), 300000);
    });

    test('全角数字を半角として読む', () {
      expect(BrokerageCsvParser.parseAmount('１２３４'), 1234);
    });

    test('小数は四捨五入する', () {
      expect(BrokerageCsvParser.parseAmount('1234.6'), 1235);
    });

    test('マイナス表記を負値として扱う', () {
      expect(BrokerageCsvParser.parseAmount('-1,000'), -1000);
      expect(BrokerageCsvParser.parseAmount('△1,000'), -1000);
      expect(BrokerageCsvParser.parseAmount('(1,000)'), -1000);
    });

    test('金額でないものは null', () {
      expect(BrokerageCsvParser.parseAmount(''), isNull);
      expect(BrokerageCsvParser.parseAmount('-'), isNull);
      expect(BrokerageCsvParser.parseAmount('トヨタ自動車'), isNull);
    });
  });

  group('guessCategory', () {
    test('セクション見出しからカテゴリを推定する', () {
      expect(BrokerageCsvParser.guessCategory('株式（現物/特定預り）'), '日本株');
      expect(BrokerageCsvParser.guessCategory('投資信託（金額/特定預り）'), '投資信託');
      expect(BrokerageCsvParser.guessCategory('外国株式（米国）'), '米国株');
      expect(BrokerageCsvParser.guessCategory('預り金'), '現金・預金');
    });

    test('該当しなければ null', () {
      expect(BrokerageCsvParser.guessCategory('よくわからない見出し'), isNull);
    });
  });

  group('SBI 形式', () {
    final result = parser.parse(_sbiCsv);

    test('書式を判定する', () {
      expect(result.format, 'SBI証券');
    });

    test('セクションをまたいで明細を読む', () {
      expect(result.holdings.length, 3);
      expect(result.holdings.map((h) => h.name), [
        'トヨタ自動車',
        '日本電信電話',
        'eMAXIS Slim 米国株式（S&P500）',
      ]);
    });

    test('「銘柄コード」ではなく「銘柄」列を名前として選ぶ', () {
      expect(result.holdings.first.name, 'トヨタ自動車');
    });

    test('評価額を集計できる', () {
      expect(result.total, 300000 + 36000 + 250000);
    });

    test('セクションからカテゴリを推定する', () {
      expect(result.holdings[0].categoryGuess, '日本株');
      expect(result.holdings[2].categoryGuess, '投資信託');
    });
  });

  group('楽天 形式', () {
    final result = parser.parse(_rakutenCsv);

    test('書式を判定する', () {
      expect(result.format, '楽天証券');
    });

    test('「時価評価額[円]」列を金額として読む', () {
      expect(result.holdings.length, 2);
      expect(result.holdings[0].amount, 950000);
      expect(result.holdings[1].amount, 296280);
    });

    test('「評価損益[円]」を金額列と取り違えない', () {
      expect(result.total, 950000 + 296280);
    });
  });

  test('評価額列がない CSV は警告を返す', () {
    final result = parser.parse('a,b,c\n1,2,3\n');
    expect(result.isEmpty, isTrue);
    expect(result.warnings, isNotEmpty);
  });
}
