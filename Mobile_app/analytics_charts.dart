import 'package:flutter/material.dart';
import 'dart:math';
import 'package:energymon/shared_widgets.dart';
import 'package:energymon/udp_read.dart';
import 'package:energymon/analytics_create_chart.dart';
import 'dart:async';

class AnalyticsChartsScreen extends StatefulWidget {
  final String? selectedDeviceMac;

  const AnalyticsChartsScreen({super.key, this.selectedDeviceMac});

  @override
  State<AnalyticsChartsScreen> createState() => _AnalyticsChartsScreenState();
}

class _AnalyticsChartsScreenState extends State<AnalyticsChartsScreen> {
  late UdpService _udpService;
  List<double> _currentWaveformData = [];
  List<double> _voltageWaveformData = [];
  List<double> _voltageFFTData = [];
  List<double> _currentFFTData = [];
  String _currentDeviceMac = 'N/A';

  Timer? _udpTimeoutTimer;
  DateTime? _lastPacketTime;

  @override
  void initState() {
    super.initState();
    _udpService = UdpService(
      port: 5005,
      onMacAddressReceived: (macAddress) {
        setState(() {
          _currentDeviceMac = macAddress;
        });
      },
      onDataReceived: (newData) {
        
        _lastPacketTime = DateTime.now();

        setState(() {
          if (widget.selectedDeviceMac == null || _currentDeviceMac.toUpperCase() != widget.selectedDeviceMac!.toUpperCase()) {
            _voltageWaveformData = [];
            _currentWaveformData = [];
            _voltageFFTData = [];
            _currentFFTData = [];
          }
          else {
            _voltageWaveformData = newData.sublist(0, 200);
            _currentWaveformData = newData.sublist(200, 400);
            _voltageFFTData = newData.sublist(400, 528);
            _currentFFTData = newData.sublist(528, 656);
          }
        });
      },
    );
    _udpService.start();

    _udpTimeoutTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _lastPacketTime != null) {
        final difference = DateTime.now().difference(_lastPacketTime!);
        
        if (difference.inSeconds >= 5) {
          setState(() {
           
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnalyticsChartsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedDeviceMac != oldWidget.selectedDeviceMac) {
      setState(() {
        _voltageWaveformData = [];
        _currentWaveformData = [];
        _voltageFFTData = [];
        _currentFFTData = [];
        _currentDeviceMac = 'N/A';
        _lastPacketTime = null; 
      });
    }
  }
  
  @override
  void dispose() {
    _udpTimeoutTimer?.cancel();
    _udpService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final bool isOnline = _lastPacketTime != null && DateTime.now().difference(_lastPacketTime!).inSeconds < 5;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              const GlobalHeader(title: 'Analytics'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScreenHeader(),
                    const SizedBox(height: 24),

                    _buildChartCard(
                      title: 'Voltage',
                      subtitle: 'Real-time Voltage (Live UDP)',
                      icon: Icons.show_chart,
                      accentColor: const Color(0xFF3A86FF),
                      secondaryColor: const Color(0xFF60A5FA),
                      value: isOnline && _voltageWaveformData.isNotEmpty
                          ? '${_calculatePkPk(_voltageWaveformData).toStringAsFixed(2)} V (Pk-Pk)'
                          : '0.0 V',
                      status: isOnline && _voltageWaveformData.isNotEmpty
                          ? 'Live'
                          : 'No Signal',
                      statusColor: isOnline && _voltageWaveformData.isNotEmpty
                          ? const Color(0xFF22C55E)
                          : Colors.orange,
                      chartChild: RealWaveChart(
                        data: isOnline ? _voltageWaveformData : [],
                        primaryColor: const Color(0xFF7B61FF),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildChartCard(
                      title: 'Current',
                      subtitle: 'Real-time Current (Live UDP)',
                      icon: Icons.show_chart,
                      accentColor: const Color(0xFF7B61FF),
                      secondaryColor: const Color(0xFFA78BFA),
                      value: isOnline && _currentWaveformData.isNotEmpty
                          ? '${_calculatePkPk(_currentWaveformData).toStringAsFixed(2)} A (Pk-Pk)'
                          : '0.0 A',
                      status: isOnline && _currentWaveformData.isNotEmpty
                          ? 'Live'
                          : 'No Signal',
                      statusColor: isOnline && _currentWaveformData.isNotEmpty
                          ? const Color(0xFF22C55E)
                          : Colors.orange,
                      chartChild: RealWaveChart(
                        data: isOnline ? _currentWaveformData : [],
                        primaryColor: const Color(0xFF7B61FF),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildChartCard(
                      title: 'Voltage FFT',
                      subtitle: 'Frequency Domain Analysis for Voltage',
                      icon: Icons.bar_chart_rounded,
                      accentColor: const Color(0xFFF59E0B),
                      secondaryColor: const Color(0xFFFBBF24),
                      value: isOnline && _voltageFFTData.isNotEmpty
                          ? '${_calculatePkPk(_voltageFFTData).toStringAsFixed(2)} V (Pk-Pk)'
                          : '0.0 V',
                      status: isOnline && _voltageFFTData.isNotEmpty ? 'Live' : 'No Signal',
                      statusColor: isOnline && _voltageFFTData.isNotEmpty
                          ? const Color(0xFF22C55E)
                          : Colors.orange,
                      chartChild: DecoratedBarChart(
                        data: isOnline ? _voltageFFTData : [],
                        primaryColor: const Color(0xFFF59E0B),
                        secondaryColor: const Color(0xFFFBBF24),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildChartCard(
                      title: 'Current FFT',
                      subtitle: 'Frequency Domain Analysis for Current',
                      icon: Icons.bar_chart_rounded,
                      accentColor: const Color(0xFFFF6B6B),
                      secondaryColor: const Color(0xFFFCA5A5),
                      value: isOnline && _currentFFTData.isNotEmpty
                          ? '${_calculatePkPk(_currentFFTData).toStringAsFixed(2)} A (Pk-Pk)'
                          : '0.0 A',
                      status: isOnline && _currentFFTData.isNotEmpty ? 'Live' : 'No Signal',
                      statusColor: isOnline && _currentFFTData.isNotEmpty
                          ? const Color(0xFF22C55E)
                          : Colors.orange,
                      chartChild: DecoratedBarChart(
                        data: isOnline ? _currentFFTData : [],
                        primaryColor: const Color(0xFFFF6B6B),
                        secondaryColor: const Color(0xFFFCA5A5),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _calculatePkPk(List<double> data) {
    if (data.isEmpty) return 0.0;
    return data.reduce(max) - data.reduce(min);
  }

  Widget _buildScreenHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A86FF), Color(0xFF7B61FF)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Electrical Analysis',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003566),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Monitor voltage, current & harmonics in real-time',
          style: TextStyle(
            fontSize: 13,
            color: const Color(0xFF8E949A).withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

Widget _buildChartCard({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color accentColor,
  required Color secondaryColor,
  required String value,
  required String status,
  required Color statusColor,
  required Widget chartChild,
}) {
  return NeumorphicContainer(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accentColor, secondaryColor]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8E949A),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
            // const Spacer(),
            // Icon(
            //   Icons.fullscreen_rounded,
            //   color: const Color(0xFF8E949A).withValues(alpha: 0.6),
            //   size: 22,
            // ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accentColor.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accentColor.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: chartChild,
          ),
        ),
      ],
    ),
  );
}
