import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';


class RealWaveChart extends StatelessWidget {
  final List<double> data;
  final Color primaryColor;

  const RealWaveChart({
    super.key,
    required this.data,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    
    if (data.isEmpty) {
      return const SizedBox();
    }

    final List<FlSpot> spots = data.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value);
    }).toList();


    final double minY = data.reduce((a, b) => a < b ? a : b);
    final double maxY = data.reduce((a, b) => a > b ? a : b);
    final double yRange = maxY - minY;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.blueGrey.shade800,
              fitInsideHorizontally: true,
              fitInsideVertically: true, 
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    spot.y.toStringAsFixed(2),
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: const Color(0xFFE2E8F0).withValues(alpha: 0.2),
              strokeWidth: 0.8,
            ),
          ),
          titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40, 
              interval: (yRange / 3),
              getTitlesWidget: (spots, meta) {
                if (spots < minY || spots > maxY) {
                  return const SizedBox();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 3.0,
                  child: Text(
                    '${spots.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF8E949A), fontSize: 10),
                  ),
                );
              },
            ),
          ),  
        ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: primaryColor,
              barWidth: 2.0,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primaryColor.withValues(alpha: 0.12),
                    primaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

class DecoratedBarChart extends StatelessWidget {
  final List<double> data;
  final Color primaryColor;
  final Color secondaryColor;

  const DecoratedBarChart({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox();
    }

    final List<BarChartGroupData> barGroups = data.asMap().entries.map((entry) {
      final int index = entry.key;
      final double value = entry.value;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [primaryColor, secondaryColor],
            ),
            width: 2.0,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(1),
              topRight: Radius.circular(1),
            ),
          ),
        ],
      );
    }).toList();

    // return SingleChildScrollView(
    // scrollDirection: Axis.horizontal,
    // physics: const BouncingScrollPhysics(),
    // child:
     return Padding(
      padding: const EdgeInsets.only(top: 8),
      child:
      //  SizedBox(
        // width: data.length * 8.0, // Lățime dinamică în funcție de numărul de bare
        // height: 200,
        // child: 
      BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: const Color(0xFFE2E8F0).withValues(alpha: 0.2),
              strokeWidth: 0.8,
            ),
          ),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.blueGrey.shade800,
              tooltipRoundedRadius: 8,
              fitInsideHorizontally: true, 
              fitInsideVertically: true,  
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  'Harmonic #${group.x}\n${rod.toY.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
        ),
        swapAnimationDuration: Duration.zero,
      ),);
  }
}
