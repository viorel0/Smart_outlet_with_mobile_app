import 'package:flutter/material.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:energymon/ble_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 

class WiFiSetupScreen extends StatefulWidget {
  const WiFiSetupScreen({super.key});

  @override
  State<WiFiSetupScreen> createState() => _WiFiSetupScreenState();
}

class _WiFiSetupScreenState extends State<WiFiSetupScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSending = false;
  String? _errorMessage;

  final BleService _bleService = BleService();

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _onSendCredentials() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();
    final deviceName = _deviceNameController.text.trim();

    if (ssid.isEmpty) {
      _showSnackBar('Introdu numele rețelei Wi-Fi (SSID).');
      return;
    }
    if (password.isEmpty) {
      _showSnackBar('Introdu parola Wi-Fi.');
      return;
    }
    if (deviceName.isEmpty) {
      _showSnackBar('Introdu numele dispozitivului.');
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      String macAddress = await _bleService.readMacAddress();
      await _bleService.sendWiFiCredentials(ssid, password);
      final userEmail = Supabase.instance.client.auth.currentUser!.email!;

      await Supabase.instance.client.from('devices').upsert({
        'mac_address': macAddress,
        'user_email': userEmail,
        'device_name': deviceName,
        'relay_status': true,
      }, onConflict: 'mac_address');

      if (!mounted) return;
      setState(() => _isSending = false);

      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = 'Eroare la trimitere: ${e.toString()}';
      });
      _showSnackBar('Trimiterea a eșuat. Încearcă din nou.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF003566),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFF7F9FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NeumorphicContainer(
                width: 80,
                height: 80,
                borderRadius: 40,
                child: Center(
                  child: Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF2DC653),
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Device Configured!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003566),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Wi-Fi credentials have been sent\nto your ESP32 via Bluetooth.\n\nThe device will restart and connect\nto the Wi-Fi network automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E949A),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const NeumorphicContainer(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  borderRadius: 16,
                  child: Center(
                    child: Text(
                      'Back to Dashboard',
                      style: TextStyle(
                        color: Color(0xFF3A86FF),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = _bleService.connectedDevice?.advName ?? 'Unknown Device';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      _bleService.disconnect();
                      Navigator.pop(context);
                    },
                    child: const NeumorphicContainer(
                      padding: EdgeInsets.all(12),
                      borderRadius: 12,
                      child: Icon(
                        Icons.arrow_back,
                        color: Color(0xFF003566),
                        size: 20,
                      ),
                    ),
                  ),
                  const Text(
                    'Wi-Fi Setup',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003566),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: 48),

              // Wi-Fi Icon Area
              const Center(
                child: NeumorphicContainer(
                  width: 120,
                  height: 120,
                  borderRadius: 60,
                  child: Center(
                    child: Icon(Icons.wifi, color: Color(0xFF3A86FF), size: 44),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Configure Wi-Fi for $deviceName',
                style: const TextStyle(color: Color(0xFF8E949A), fontSize: 14),
                textAlign: TextAlign.center,
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE63946).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFE63946),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFE63946),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),

              NeumorphicTextField(
                label: 'WI-FI NAME (SSID)',
                hint: 'Home_Network_5G',
                icon: Icons.router_outlined,
                controller: _ssidController,
              ),
              const SizedBox(height: 24),
              NeumorphicTextField(
                label: 'PASSWORD',
                hint: '••••••••••••',
                icon: Icons.lock_outline,
                isPassword: _obscurePassword,
                controller: _passwordController,
                trailing: GestureDetector(
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xFF8E949A),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              NeumorphicTextField(
                label: 'SET DEVICE NAME',
                hint: 'My smart device',
                icon: Icons.lightbulb_outline,
                controller: _deviceNameController,
              ),
              const Spacer(),

              GestureDetector(
                onTap: _isSending ? null : _onSendCredentials,
                child: NeumorphicContainer(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  borderRadius: 16,
                  child: Center(
                    child: _isSending
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF3A86FF),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Sending via Bluetooth...',
                                style: TextStyle(
                                  color: Color(0xFF3A86FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.send_rounded,
                                color: Color(0xFF3A86FF),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Send to Device',
                                style: TextStyle(
                                  color: Color(0xFF3A86FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
