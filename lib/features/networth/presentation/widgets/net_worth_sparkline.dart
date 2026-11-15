import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/net_worth.dart';

/// Minimal trend line; renders nothing with fewer than two points.
class NetWorthSparkline extends StatelessWidget {
  final List<NetWorthPoint> points;
  final Color color;
  final double height;
  final bool interactive;

  const NetWorthSparkline({
    super.key,
    required this.points,
    required this.color,
    this.height = 48,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final spots = [
      for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].netWorth),
    ];
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(enabled: interactive),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
            ),
          ],
        ),
      ),
    );
  }
}
