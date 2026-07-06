import 'package:flutter/material.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class EnergyStats extends StatefulWidget {
  final String? selectedDeviceMac;

  const EnergyStats({super.key, this.selectedDeviceMac});

  @override
  State<EnergyStats> createState() => _EnergyStatsState();
}

class _EnergyStatsState extends State<EnergyStats> {
  Map<String, dynamic>? _deviceData;
  bool _isLoading = true;
  RealtimeChannel? _telemetryChannel;
  double _todayEnergy = 0.0;
  double _monthEnergy = 0.0;
  List<dynamic> _monthdaysData = [];
  List<dynamic> _yearData = [];

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
    _fetchHistoryStats();
    _subscribeToTelemetryRealtime();
  }

  @override
  void didUpdateWidget(covariant EnergyStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDeviceMac != oldWidget.selectedDeviceMac) {
      setState(() {
        _isLoading = true;
      });
      _fetchTelemetry();
      _fetchHistoryStats();
      _subscribeToTelemetryRealtime();
    }
  }

  @override
  void dispose() {
    _unsubscribeTelemetry();
    super.dispose();
  }

  void _unsubscribeTelemetry() {
    if (_telemetryChannel != null) {
      Supabase.instance.client.removeChannel(_telemetryChannel!);
      _telemetryChannel = null;
    }
  }

  Future<void> _fetchTelemetry() async {
    if (widget.selectedDeviceMac == null || widget.selectedDeviceMac!.isEmpty) {
      return;
    }
    try {
      final response = await Supabase.instance.client
          .from('devices')
          .select()
          .eq('mac_address', widget.selectedDeviceMac!)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _deviceData = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      //
    }
  }

  Future<void> _fetchHistoryStats() async {
    if (widget.selectedDeviceMac == null || widget.selectedDeviceMac!.isEmpty) {
      return;
    }
    try {
      final results = await Future.wait([
        Supabase.instance.client.rpc('get_today_energy', params: {'device_mac': widget.selectedDeviceMac}),
        Supabase.instance.client.rpc('get_month_energy', params: {'device_mac': widget.selectedDeviceMac}),
        Supabase.instance.client.rpc('get_montly_energy', params: {'device_mac': widget.selectedDeviceMac}),
        Supabase.instance.client.rpc('get_year_energy_data', params: {'device_mac': widget.selectedDeviceMac}),
      ]);
      if (mounted) {
        setState(() {
          _todayEnergy = (results[0] ?? 0.0).toDouble();
          _monthEnergy = (results[1] ?? 0.0).toDouble();
          _monthdaysData = results[2] ?? [];
          _yearData = results[3] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Eroare la preluarea statisticilor: $e");
    }
  }

  void _subscribeToTelemetryRealtime() {
    _unsubscribeTelemetry();

    if (widget.selectedDeviceMac == null || widget.selectedDeviceMac!.isEmpty) {
      return;
    }

    _telemetryChannel = Supabase.instance.client.channel('public:devices_telemetry_stats_${widget.selectedDeviceMac}');
    _telemetryChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'devices',
      callback: (payload) {
        _fetchTelemetry();
        _fetchHistoryStats();
      },
    ).subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    double activePower = 0.0;
    if (_deviceData != null) {
      activePower = (_deviceData!['active_power'] ?? 0.0).toDouble();
    }

    String powerValueText = activePower > 1000
        ? (activePower / 1000.0).toStringAsFixed(1)
        : activePower.toStringAsFixed(0);
    String powerUnitText = activePower > 1000 ? 'kW' : 'W';

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await _fetchHistoryStats();
        },
        color: const Color(0xFF3A86FF),
        backgroundColor: const Color(0xFFF7F9FC),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
            const GlobalHeader(title: 'Energy Stats'),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  NeumorphicContainer(
                    height: 240,
                    width: 240,
                    borderRadius: 120,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'CURRENT POWER',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8E949A),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            powerValueText,
                            style: const TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3A86FF),
                            ),
                          ),
                          Text(
                            powerUnitText,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF3A86FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSimpleStatCard(
                          'Today',
                          '${_todayEnergy.toStringAsFixed(7)} kWh',
                          Icons.flash_on,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSimpleStatCard(
                          'This Month',
                          '${_monthEnergy.toStringAsFixed(7)} kWh',
                          Icons.calendar_today,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Graficul ultimele 30 de zile
                  NeumorphicContainer(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daily Usage (Last 30 Days)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 150,
                          child: HistoricBarChart(
                            data: _monthdaysData,
                            primaryColor: const Color(0xFF3A86FF),
                            secondaryColor: const Color(0xFF60A5FA),
                            labelKey: 'day_name',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Graficul ultimele 12 luni
                  NeumorphicContainer(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monthly Usage (Last 12 Months)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 150,
                          child: HistoricBarChart(
                            data: _yearData,
                            primaryColor: const Color(0xFF22C55E),
                            secondaryColor: const Color(0xFF4ADE80),
                            labelKey: 'day_num',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildSimpleStatCard(String title, String value, IconData icon) {
    return NeumorphicContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF8E949A), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// Widget-ul comun pentru afișarea datelor istorice
class HistoricBarChart extends StatelessWidget {
  final List<dynamic> data;
  final Color primaryColor;
  final Color secondaryColor;
  final String labelKey;
  final String valueKey;

  const HistoricBarChart({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.secondaryColor,
    this.labelKey = 'day_name',
    this.valueKey = 'value',
  });

  @override
  Widget build(BuildContext context) {
  
    final List<BarChartGroupData> barGroups = data.asMap().entries.map((entry) {
      final int index = entry.key;
      final Map<String, dynamic> item = Map<String, dynamic>.from(entry.value);
      final double value = (item[valueKey] ?? 0.0).toDouble();

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
            width: data.length > 7 ? 12.0 : 16.0,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();

    final double chartWidth = data.length > 7 ? data.length * 48.0 : double.infinity;

    Widget chart = BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: const Color(0xFFE2E8F0).withValues(alpha: 0.15),
            strokeWidth: 0.8,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final int index = value.toInt();
                if (index >= 0 && index < data.length) {
                  final Map<String, dynamic> item = Map<String, dynamic>.from(data[index]);
                  final String label = (item[labelKey] ?? '').toString();

                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      label,
                      style: const TextStyle(color: Color(0xFF8E949A), fontSize: 10),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
              width: 1,
            ),
          ),
        ),
        barGroups: barGroups,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.shade800,
            tooltipRoundedRadius: 8,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final Map<String, dynamic> item = Map<String, dynamic>.from(data[group.x]);
              final String label = (item[labelKey] ?? '').toString();
              return BarTooltipItem(
                '$label\n${rod.toY.toStringAsFixed(3)} kWh',
                const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
      ),
    );

    if (data.length > 7) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          width: chartWidth,
          height: 150,
          child: chart,
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        height: 150,
        child: chart,
      );
    }
  }
}
