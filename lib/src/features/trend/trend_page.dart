import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../purchase/paywall_page.dart';

class TrendPage extends ConsumerWidget {
  const TrendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(trendProvider);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('資産推移')),
      body: trend.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('読み込みに失敗しました: $error')),
        data: (points) {
          if (points.length < 2) {
            return const EmptyState(
              icon: Icons.timeline_outlined,
              title: '推移を描くにはあと少しデータが必要です',
              message: '2 つ以上の月を記録すると、資産の折れ線グラフが表示されます。',
            );
          }

          final limited = applyFreeTrendLimit(points, isPro: isPro);
          final hidden = points.length - limited.length;
          // 元本ラインは入金を記録している Pro ユーザーにだけ意味がある。
          final showPrincipal = isPro && hasContributionData(limited);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MoneyHeadline(
                      label: '最新の総資産',
                      amount: limited.last.total,
                      delta: limited.last.total - limited.first.total,
                      deltaLabel: '${Fmt.displayMonth(limited.first.period)}から',
                    ),
                    if (showPrincipal) ...[
                      const SizedBox(height: 16),
                      _GainBreakdown(point: limited.last),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: _TrendChart(
                        points: limited,
                        showPrincipal: showPrincipal,
                      ),
                    ),
                    if (showPrincipal) ...[
                      const SizedBox(height: 14),
                      const _ChartLegend(),
                    ],
                  ],
                ),
              ),
              if (!isPro && hidden > 0) ...[
                const SizedBox(height: 12),
                ProUpsellBanner(
                  title: '全期間の推移を表示',
                  message:
                      'Free では直近 ${FreePlanLimits.trendMonths} ヶ月分を表示しています'
                      '（$hidden 件分が非表示）。',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PaywallPage()),
                  ),
                ),
              ],
              if (isPro && !showPrincipal) ...[
                const SizedBox(height: 12),
                const _ContributionHint(),
              ],
              const SizedBox(height: 12),
              SectionCard(
                title: '月ごとの推移',
                child: Column(
                  children: [
                    for (var i = limited.length - 1; i >= 0; i--) ...[
                      if (i < limited.length - 1) const Divider(height: 18),
                      _PeriodRow(
                        point: limited[i],
                        previous: i > 0 ? limited[i - 1] : null,
                        showContribution: showPrincipal,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Free プランは直近 [FreePlanLimits.trendMonths] ヶ月ぶんのみ表示する。
List<TrendPoint> applyFreeTrendLimit(
  List<TrendPoint> points, {
  required bool isPro,
}) {
  if (isPro || points.isEmpty) return points;
  final cutoff = DateTime(
    points.last.period.year,
    points.last.period.month - (FreePlanLimits.trendMonths - 1),
  );
  final limited = points
      .where((p) => !p.period.isBefore(cutoff))
      .toList(growable: false);
  return limited.isEmpty ? points.sublist(points.length - 1) : limited;
}

/// 「増えたのは入金のおかげか運用のおかげか」を分けて見せる。
class _GainBreakdown extends StatelessWidget {
  const _GainBreakdown({required this.point});

  final TrendPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gain = point.gain;
    final gainColor = gain > 0
        ? const Color(0xFF12B981)
        : gain < 0
        ? scheme.error
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '積み上げた元本',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.yen(point.principal),
                  style: theme.textTheme.titleSmall?.tabular.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: scheme.outlineVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '運用による損益',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.signedYen(gain),
                  style: theme.textTheme.titleSmall?.tabular.copyWith(
                    fontWeight: FontWeight.w700,
                    color: gainColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(theme, scheme.primary, '評価額', dashed: false),
        const SizedBox(width: 20),
        _legendItem(theme, scheme.onSurfaceVariant, '元本', dashed: true),
      ],
    );
  }

  Widget _legendItem(
    ThemeData theme,
    Color color,
    String label, {
    required bool dashed,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 18,
        height: 3,
        child: CustomPaint(painter: _LinePainter(color: color, dashed: dashed)),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 4).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.dashed != dashed;
}

class _ContributionHint extends StatelessWidget {
  const _ContributionHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Row(
        children: [
          Icon(Icons.savings_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '記録画面で「今月の入金額」を入れると、増えた分を'
              '入金と運用損益に分けて表示できます。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.showPrincipal});

  final List<TrendPoint> points;
  final bool showPrincipal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final values = <double>[
      for (final p in points) p.total.toDouble(),
      if (showPrincipal)
        for (final p in points) p.principal.toDouble(),
    ];
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final padding =
        (maxY - minY).abs() * 0.18 + (maxY == 0 ? 1000 : maxY * 0.05);

    return LineChart(
      LineChartData(
        minY: (minY - padding).clamp(0, double.infinity),
        maxY: maxY + padding,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  Fmt.compactYen(value),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: _bottomInterval,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    Fmt.shortMonth(points[index].period),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (spots) => spots.map((spot) {
              final point = points[spot.x.round()];
              final isPrincipal = spot.barIndex == 1;
              return LineTooltipItem(
                isPrincipal
                    ? '元本 ${Fmt.yen(point.principal)}'
                    : '${Fmt.displayMonth(point.period)}\n'
                          '${Fmt.yen(point.total)}',
                TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].total.toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.22,
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 3,
            dotData: FlDotData(
              show: points.length <= 18,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3.5,
                color: scheme.surface,
                strokeWidth: 2,
                strokeColor: scheme.primary,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.28),
                  scheme.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          if (showPrincipal)
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].principal.toDouble()),
              ],
              isCurved: false,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
              barWidth: 2,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  double get _bottomInterval {
    if (points.length <= 6) return 1;
    return (points.length / 6).ceilToDouble();
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.point,
    required this.previous,
    required this.showContribution,
  });

  final TrendPoint point;
  final TrendPoint? previous;
  final bool showContribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = previous == null ? null : point.total - previous!.total;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Fmt.displayMonth(point.period),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showContribution && point.contribution != 0)
                Text(
                  '入金 ${Fmt.yen(point.contribution)}',
                  style: theme.textTheme.labelSmall?.tabular.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (delta != null)
          Text(
            Fmt.signedYen(delta),
            style: theme.textTheme.bodySmall?.tabular.copyWith(
              color: delta > 0
                  ? const Color(0xFF12B981)
                  : delta < 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(width: 12),
        Text(
          Fmt.yen(point.total),
          style: theme.textTheme.bodyMedium?.tabular.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
