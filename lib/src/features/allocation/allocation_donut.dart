import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';

/// カテゴリ別構成比のドーナツグラフ。
///
/// 中央に総額を置いて「合計 → 内訳」の順で読めるようにしている。
/// タップしたセクションは少しだけ外側に伸び、中央の表示がその内訳に切り替わる。
class AllocationDonut extends StatefulWidget {
  const AllocationDonut({
    super.key,
    required this.slices,
    required this.total,
  });

  final List<CategorySlice> slices;
  final int total;

  @override
  State<AllocationDonut> createState() => _AllocationDonutState();
}

class _AllocationDonutState extends State<AllocationDonut> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = widget.slices.where((s) => s.amount > 0).toList();

    if (visible.isEmpty || widget.total <= 0) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            '表示できる残高がありません',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final focused = _touchedIndex >= 0 && _touchedIndex < visible.length
        ? visible[_touchedIndex]
        : null;

    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 70,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response?.touchedSection == null) {
                    setState(() => _touchedIndex = -1);
                    return;
                  }
                  setState(() {
                    _touchedIndex =
                        response!.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              sections: [
                for (var i = 0; i < visible.length; i++)
                  PieChartSectionData(
                    value: visible[i].amount.toDouble().abs(),
                    color: visible[i].category.color,
                    radius: _touchedIndex == i ? 44 : 36,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                focused?.category.name ?? '合計',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Fmt.compactYen(focused?.amount ?? widget.total),
                style: theme.textTheme.headlineSmall?.tabular.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (focused != null) ...[
                const SizedBox(height: 2),
                Text(
                  Fmt.percent(focused.ratioOf(widget.total)),
                  style: theme.textTheme.bodySmall?.tabular.copyWith(
                    color: focused.category.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
