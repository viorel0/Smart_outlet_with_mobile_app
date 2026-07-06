import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:energymon/ble_service.dart';
import 'package:energymon/wifi_setup_screen.dart';

class BluetoothScanningScreen extends StatefulWidget {
  const BluetoothScanningScreen({super.key});

  @override
  State<BluetoothScanningScreen> createState() =>
      _BluetoothScanningScreenState();
}

class _BluetoothScanningScreenState extends State<BluetoothScanningScreen> {
  final BleService _bleService = BleService();

  bool _isScanning = false;
  int _connectingIndex = -1;
  String? _errorMessage;
  List<ScanResult> _scanResults = [];

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningSub;

  @override
  void initState() {
    super.initState();

    _scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isScanning = scanning);
    });

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults =
              results.where((r) => r.device.advName.isNotEmpty).toList()
                ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      }
    });

    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _stopScan();
    super.dispose();
  }


  Future<void> _startScan() async {
    setState(() {
      _errorMessage = null;
      _scanResults.clear();
    });

    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        setState(() => _errorMessage = 'Bluetooth-ul nu este activat.');
        return;
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Eroare la scanare: $e');
      }
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void _refreshScan() {
    _stopScan();
    setState(() {
      _connectingIndex = -1;
      _errorMessage = null;
    });
    _startScan();
  }

  Future<void> _connectToDevice(int index) async {
    if (_connectingIndex != -1) return;
    await _stopScan();

    setState(() {
      _connectingIndex = index;
      _errorMessage = null;
    });

    try {
      await _bleService.connectAndDiscover(_scanResults[index].device);
      if (!mounted) return;
      setState(() => _connectingIndex = -1);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WiFiSetupScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectingIndex = -1;
          _errorMessage = 'Conectare eșuată: $e';
        });
      }
    }
  }


  String _signalLabel(int rssi) {
    if (rssi >= -50) return 'Semnal: Excelent';
    if (rssi >= -60) return 'Semnal: Foarte bun';
    if (rssi >= -70) return 'Semnal: Bun';
    if (rssi >= -80) return 'Semnal: Slab';
    return 'Semnal: Foarte slab';
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('energy') || n.contains('esp32')) return Icons.memory;
    if (n.contains('plug') || n.contains('power')) return Icons.power;
    if (n.contains('light') || n.contains('lamp')) return Icons.lightbulb_outline;
    return Icons.bluetooth;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _header(),
              const SizedBox(height: 32),
              _bluetoothIcon(),
              const SizedBox(height: 20),
              _statusText(),
              const SizedBox(height: 28),
              _listHeader(),
              const SizedBox(height: 12),
              Expanded(child: _deviceList()),
            ],
          ),
        ),
      ),
    );
  }


  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const NeumorphicContainer(
            padding: EdgeInsets.all(12),
            borderRadius: 12,
            child: Icon(Icons.arrow_back, color: Color(0xFF003566), size: 20),
          ),
        ),
        const Text(
          'Scanning for Devices',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF003566),
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }


  Widget _bluetoothIcon() {
    final IconData icon;
    if (_isScanning) {
      icon = Icons.bluetooth_searching;
    } else if (_scanResults.isNotEmpty) {
      icon = Icons.bluetooth_connected;
    } else {
      icon = Icons.bluetooth_disabled;
    }

    return NeumorphicContainer(
      width: 100,
      height: 100,
      borderRadius: 50,
      child: Center(
        child: Icon(
          icon,
          size: 40,
          color: _errorMessage != null
              ? const Color(0xFFE63946)
              : const Color(0xFF3A86FF),
        ),
      ),
    );
  }


  Widget _statusText() {
    final String title;
    final String subtitle;
    final Color titleColor;

    if (_errorMessage != null) {
      title = 'Eroare';
      subtitle = _errorMessage!;
      titleColor = const Color(0xFFE63946);
    } else if (_isScanning) {
      title = 'Searching for nearby devices...';
      subtitle = 'Make sure your ESP32 is in BLE mode.';
      titleColor = const Color(0xFF003566);
    } else {
      title = 'Scan complete';
      subtitle = '${_scanResults.length} device(s) found.';
      titleColor = const Color(0xFF003566);
    }

    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF8E949A), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _listHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'AVAILABLE DEVICES (${_scanResults.length})',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8E949A),
            letterSpacing: 0.8,
          ),
        ),
        GestureDetector(
          onTap: _refreshScan,
          child: NeumorphicContainer(
            padding: const EdgeInsets.all(8),
            borderRadius: 8,
            child: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF3A86FF),
                    ),
                  )
                : const Icon(Icons.refresh, size: 16, color: Color(0xFF3A86FF)),
          ),
        ),
      ],
    );
  }


  Widget _deviceList() {
    if (_scanResults.isEmpty) {
      if (_isScanning) {
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF3A86FF),
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bluetooth_disabled,
              size: 48,
              color: Color(0xFF8E949A),
            ),
            const SizedBox(height: 12),
            const Text(
              'No devices found',
              style: TextStyle(color: Color(0xFF8E949A)),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _refreshScan,
              child: const Text(
                'Tap to retry',
                style: TextStyle(
                  color: Color(0xFF3A86FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Results
    return ListView.separated(
      itemCount: _scanResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      padding: const EdgeInsets.only(bottom: 24),
      itemBuilder: (_, index) {
        final r = _scanResults[index];
        final isConnecting = _connectingIndex == index;
        final isEsp32 = r.device.advName == BleService.esp32DeviceName;

        return NeumorphicContainer(
          padding: const EdgeInsets.all(16),
          backgroundColor: isEsp32
              ? const Color(0xFFEDF2FF)
              : const Color(0xFFF7F9FC),
          child: Row(
            children: [
              // Icon
              NeumorphicContainer(
                padding: const EdgeInsets.all(10),
                borderRadius: 12,
                isInset: true,
                child: Icon(
                  _iconFor(r.device.advName),
                  color: const Color(0xFF3A86FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),

              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.device.advName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEsp32) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A86FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ESP32',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnecting ? 'Connecting...' : _signalLabel(r.rssi),
                      style: TextStyle(
                        color: isConnecting
                            ? const Color(0xFF3A86FF)
                            : const Color(0xFF8E949A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Connect button
              if (isConnecting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3A86FF),
                  ),
                )
              else
                GestureDetector(
                  onTap: _connectingIndex == -1
                      ? () => _connectToDevice(index)
                      : null,
                  child: const NeumorphicContainer(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    borderRadius: 12,
                    child: Text(
                      'Connect',
                      style: TextStyle(
                        color: Color(0xFF3A86FF),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
