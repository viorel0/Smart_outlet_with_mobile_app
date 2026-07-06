import 'package:flutter/material.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async'; 

class PowerMetrics extends StatefulWidget {
  final String? selectedDeviceMac; 

  const PowerMetrics({super.key, this.selectedDeviceMac});

  @override
  State<PowerMetrics> createState() => _PowerMetricsState();
}

class _PowerMetricsState extends State<PowerMetrics> {
  Map<String, dynamic>? _deviceData;
  bool _isLoading = true;
  RealtimeChannel? _telemetryChannel;
  final List<double> _currentHistory = [];
  Timer? _offlineTimer;

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
    _subscribeToTelemetryRealtime();
      _offlineTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
    if (mounted && _deviceData != null) {
      setState(() {
          //
          });
        }
      });
  }

  @override
  void didUpdateWidget(covariant PowerMetrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDeviceMac != oldWidget.selectedDeviceMac) {
      setState(() {
        _isLoading = true;
        _currentHistory.clear();
      });
      _fetchTelemetry();
      _subscribeToTelemetryRealtime();
    }
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
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
          if (response != null) {
            final double currentVal = (response['current'] ?? 0.0).toDouble();
            _currentHistory.add(currentVal);
            if (_currentHistory.length > 20) {
              _currentHistory.removeAt(0);
            }
          }
        });
      }
    } catch (e) {
      //
    }
  }

  void _subscribeToTelemetryRealtime() {
    _unsubscribeTelemetry();

    if (widget.selectedDeviceMac == null || widget.selectedDeviceMac!.isEmpty) {
      return;
    }

    _telemetryChannel = Supabase.instance.client.channel('public:devices_telemetry_${widget.selectedDeviceMac}');
    _telemetryChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'devices',
      callback: (payload) {
        _fetchTelemetry();
      },
    ).subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedDeviceMac == null || widget.selectedDeviceMac!.isEmpty) {
      return const SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              GlobalHeader(title: 'Power Metrics'),
              Padding(
                padding: EdgeInsets.only(top: 80, left: 24, right: 24),
                child: Center(
                  child: Text(
                    'Vă rugăm să selectați un dispozitiv din Dashboard pentru a vizualiza telemetria în timp real.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8E949A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Valori implicite în caz că nu există semnal sau conexiune
    double activePower = 0.0;
    double apparentPower = 0.0;
    double reactivePower = 0.0;
    double powerFactor = 0.0;
    double frequency = 0.0;
    double thdi = 0.0;
    double thdv = 0.0;
    double current = 0.0;
    double voltage = 0.0;

    bool isOnline = false;

    if (_deviceData != null) {
      if (_deviceData!['measured_at'] != null) {
        final DateTime lastMeasured = DateTime.parse(_deviceData!['measured_at']).toLocal();
        final difference = DateTime.now().difference(lastMeasured);
        
        isOnline = difference.inSeconds <= 10; 
      }
      if (isOnline){
      activePower = (_deviceData!['active_power'] ?? 0.0).toDouble();
      apparentPower = (_deviceData!['apparent_power'] ?? 0.0).toDouble();
      reactivePower = (_deviceData!['reactive_power'] ?? 0.0).toDouble();
      powerFactor = (_deviceData!['power_factor'] ?? 0.0).toDouble();
      frequency = (_deviceData!['freq'] ?? 50.0).toDouble();
      thdi = (_deviceData!['thd_i'] ?? 0.0).toDouble();
      thdv = (_deviceData!['thd_v'] ?? 0.0).toDouble();
      current = (_deviceData!['current'] ?? 0.0).toDouble();
      voltage = (_deviceData!['voltage'] ?? 0.0).toDouble();
      }
      else{

      }
    }

    String mainPowerText = activePower > 1000
        ? '${(activePower / 1000.0).toStringAsFixed(2)} kW'
        : '${activePower.toStringAsFixed(2)} W';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            const GlobalHeader(title: 'Power Metrics'),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    mainPowerText,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3A86FF),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 4, 
                        backgroundColor: isOnline ? Colors.green : Colors.orange
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOnline ? 'System Optimal' : 'Device Offline / No Signal',
                        style: const TextStyle(color: Color(0xFF8E949A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  NeumorphicContainer(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Consumption Trend',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          height: 120,
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                             child: isOnline
                              ? TrendLineChart(data: _currentHistory)
                              : Center(
                                  child: Text(
                                    'No data to display',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.1,
                    children: [
                      _buildMetricCard(
                        'Current (IRMS)',
                        current.toStringAsFixed(3),
                        'A',
                        Icons.bolt,
                      ),
                      _buildMetricCard(
                        'Voltage (VRMS)',
                        voltage.toStringAsFixed(2),
                        'V',
                        Icons.electrical_services,
                      ),
                      _buildMetricCard(
                        'Power Factor',
                        powerFactor.toStringAsFixed(2),
                        'PF',
                        Icons.speed,
                      ),
                      _buildMetricCard(
                        'Frequency',
                        frequency.toStringAsFixed(1),
                        'Hz',
                        Icons.waves,
                      ),
                      _buildMetricCard(
                        'THD (Current)',
                        thdi.toStringAsFixed(1),
                        '%',
                        Icons.show_chart,
                      ),
                      _buildMetricCard(
                        'THD (Voltage)',
                        thdv.toStringAsFixed(1),
                        '%',
                        Icons.show_chart_outlined,
                      ),
                      _buildMetricCard(
                        'Apparent Power',
                        apparentPower > 1000
                            ? (apparentPower / 1000.0).toStringAsFixed(2)
                            : apparentPower.toStringAsFixed(2),
                        apparentPower > 1000 ? 'kVA' : 'VA',
                        Icons.power,
                      ),
                      _buildMetricCard(
                        'Reactive Power',
                        reactivePower > 1000
                            ? (reactivePower / 1000.0).toStringAsFixed(2)
                            : reactivePower.toStringAsFixed(2),
                        reactivePower > 1000 ? 'kVAR' : 'VAR',
                        Icons.power,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String unit,
    IconData icon,
  ) {
    return NeumorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.orange.shade700, size: 20),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8E949A)),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E949A)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TrendLineChart extends StatelessWidget {
  final List<double> data;
  final Color lineColor;

  const TrendLineChart({
    super.key,
    required this.data,
    this.lineColor = const Color(0xFF3A86FF),
  });

  @override
  Widget build(BuildContext context) {

    final List<FlSpot> spots = data.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value);
    }).toList();
    
    final double maxY = data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) : 1.0;
    final double minY = data.isNotEmpty ? data.reduce((a, b) => a < b ? a : b) : 0.0;
    final double yRange = maxY - minY;
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.shade800,
            fitInsideHorizontally: true,
            fitInsideVertically: true,  
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(2)} A',
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
              reservedSize: 30, // Spațiu în stânga graficului ca să încapă textul "XX.XX A"
              interval: (yRange / 3) == 0 ? 1 : (yRange / 3), 
              getTitlesWidget: (spots, meta) {
                if (spots < minY || spots > maxY) {
                  return const SizedBox();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 6.0,
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
            color: lineColor,
            barWidth: 2.0,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.18),
                  lineColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
      
    );
  }
}