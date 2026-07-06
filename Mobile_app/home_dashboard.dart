import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:energymon/bluetooth_scanning_screen.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 

class HomeDashboard extends StatefulWidget {
  final String? selectedDeviceMac;
  final Function(String, String) onDeviceSelected;

  const HomeDashboard({
    super.key,
    required this.selectedDeviceMac,
    required this.onDeviceSelected,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> with SingleTickerProviderStateMixin {
  bool _isPlugOn = true;
  List<Map<String, dynamic>> _registeredDevices = [];
  late final AnimationController _lottieController;
  bool _isFirstLoad = true;
  RealtimeChannel? _devicesChannel;
  String nameofuser = ""; 

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _lottieController.value = _isPlugOn ? 1.0 : 0.0;
    
    _fetchUserName();
    _subscribeToDevicesRealtime();
    _fetchMyDevices();
  }

  void _subscribeToDevicesRealtime() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;
    final userEmail = currentUser.email;
    if (userEmail == null) return;

    _devicesChannel = Supabase.instance.client.channel('public:devices');
    _devicesChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'devices',
      callback: (payload) {
        _fetchMyDevices();
      },
    ).subscribe();
  }

  @override
  void dispose() {
    if (_devicesChannel != null) {
      Supabase.instance.client.removeChannel(_devicesChannel!);
    }
    _lottieController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserName() async {
    try {
      // Luăm utilizatorul curent direct din memoria telefonului
      final user = Supabase.instance.client.auth.currentUser;
      
      if (user != null && user.userMetadata != null) {
    
        // print("Metadate: ${user.userMetadata}"); 

        setState(() {
          nameofuser = user.userMetadata!['name'] ?? 
                       user.userMetadata!['full_name'] ?? 
                       user.userMetadata!['display_name'] ?? 
                       '';
        });
      }
    } catch (e) {
      
    }
  }

  Future<void> _fetchMyDevices() async {
    try {
      final userEmail = Supabase.instance.client.auth.currentUser!.email!;
      final response = await Supabase.instance.client
          .from('devices')
          .select()
          .eq('user_email', userEmail)
          .order('device_name', ascending: true);

      setState(() {
        _registeredDevices = List<Map<String, dynamic>>.from(response);
      });

      if (_registeredDevices.isNotEmpty) {
        final activeMac = widget.selectedDeviceMac ?? _registeredDevices.first['mac_address'];
        final hasSelected = _registeredDevices.any((d) => d['mac_address'] == widget.selectedDeviceMac);
        if (!hasSelected) {
          final firstMac = _registeredDevices.first['mac_address'] ?? '';
          final firstName = _registeredDevices.first['device_name'] ?? '';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onDeviceSelected(firstMac, firstName);
          });
        }

        final selectedDevice = _registeredDevices.firstWhere(
          (d) => d['mac_address'] == activeMac,
          orElse: () => _registeredDevices.first,
        );
        final newStatus = selectedDevice['relay_status'] ?? false;
        
        setState(() {
          if (_isFirstLoad) {
            _isPlugOn = newStatus;
            _lottieController.value = _isPlugOn ? 1.0 : 0.0;
            _isFirstLoad = false;
          } else if (newStatus != _isPlugOn) {
            _isPlugOn = newStatus;
            if (_isPlugOn) {
              _lottieController.forward();
            } else {
              _lottieController.reverse();
            }
          }
        });
      }
    } catch (e) {
      //
    }
  }

  Future<void> _deleteDevice(String macAddress) async {
    try {
      // comanda de ștergere în baza de date
      await Supabase.instance.client
          .from('devices')
          .delete()
          .eq('mac_address', macAddress);

      _fetchMyDevices();
    }
    catch (e) {
      //
    }
  }

  void _showDeleteConfirmationDialog(String macAddress, String deviceName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFF7F9FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Delete icon
              const NeumorphicContainer(
                width: 80,
                height: 80,
                borderRadius: 40,
                child: Center(
                  child: Icon(
                    Icons.delete_forever_outlined,
                    color: Color.fromARGB(255, 253, 16, 16),
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Delete Device',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003566),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to delete "$deviceName"?\n',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8E949A),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteDevice(macAddress);
                },
                child: const NeumorphicContainer(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  borderRadius: 16,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_forever,
                            color: Color.fromARGB(255, 253, 16, 16), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Yes, Delete',
                          style: TextStyle(
                            color: Color.fromARGB(255, 253, 16, 16),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Cancel button
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF8E949A),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectDevice(String macAddress, bool isOn) {
    final dev = _registeredDevices.firstWhere(
      (d) => d['mac_address'] == macAddress,
      orElse: () => {},
    );
    final name = dev.isNotEmpty ? (dev['device_name'] ?? '') : '';
    
    widget.onDeviceSelected(macAddress, name);
    
    setState(() {
      _isPlugOn = isOn;
      if (_isPlugOn) {
        _lottieController.forward();
      } else {
        _lottieController.reverse();
      }
    });
  }

  Future<void> _togglePlugState() async {
    final newStatus = !_isPlugOn;
    final activeMac = widget.selectedDeviceMac;
    setState(() {
      _isPlugOn = newStatus;
      if (_isPlugOn) {
        _lottieController.forward();
      } else {
        _lottieController.reverse();
      }
      if (activeMac != null) {
        final idx = _registeredDevices.indexWhere((d) => d['mac_address'] == activeMac);
        if (idx != -1) {
          _registeredDevices[idx]['relay_status'] = newStatus;
        }
      }
    });
    if (activeMac != null) {
      try {
        await Supabase.instance.client
            .from('devices')
            .update({'relay_status': newStatus})
            .eq('mac_address', activeMac);
      } catch (e) {
        //
      }
    }
  }

  void _showBluetoothDialog() async {
    final adapterState = await FlutterBluePlus.adapterState.first;

    if (!mounted) return;

    if (adapterState == BluetoothAdapterState.on) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BluetoothScanningScreen()),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFF7F9FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bluetooth icon
              const NeumorphicContainer(
                width: 80,
                height: 80,
                borderRadius: 40,
                child: Center(
                  child: Icon(Icons.bluetooth,
                      color: Color(0xFF3A86FF), size: 36),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Enable Bluetooth',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003566),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bluetooth is required to discover\nand connect to nearby smart devices.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E949A),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              GestureDetector(
                onTap: () async {
                  Navigator.of(ctx).pop();

                  try {
                    await FlutterBluePlus.turnOn();
                  } catch (_) {
                    
                  }

                  await Future.delayed(const Duration(milliseconds: 500));

                  if (!mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BluetoothScanningScreen()),
                  );
                },
                child: const NeumorphicContainer(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  borderRadius: 16,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_connected,
                            color: Color(0xFF3A86FF), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Enable & Scan',
                          style: TextStyle(
                            color: Color(0xFF3A86FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Cancel
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF8E949A),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GlobalHeader(),
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nameofuser != "" ? 'Welcome back, $nameofuser!' : 'Welcome back!',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w400),
                  ),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Center(
                          child: _buildsmartplugbutton(),
                        ),
                      ],
                    ),
                  const SizedBox(height: 32),

                  // dispozitivele si butonul de adaugare
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'My Devices',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          GestureDetector(
                            onTap: _fetchMyDevices,
                            child: 
                            Container(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.refresh, color: const Color(0xFF3A86FF))
                                ),
                          ),]
                      ),
                      GestureDetector(
                        onTap: _showBluetoothDialog,
                        child: const NeumorphicContainer(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          borderRadius: 14,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_circle_outline,
                                  color: Color(0xFF3A86FF), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Add Device',
                                style: TextStyle(
                                  color: Color(0xFF3A86FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_registeredDevices.isEmpty)
                        const Center(
                          child: Text(
                            'No devices registered on this account yet.\nTap "Add Device" to connect.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF8E949A)),
                          ),)
                  else
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.9,
                    children: [
                        for (var device in _registeredDevices)
                          _buildDeviceCard(
                            device['device_name'] ?? 'Dispozitiv Necunoscut',
                            Icons.lightbulb_outline,                         
                            device['relay_status'] ?? false, 
                            device['mac_address'] ?? '',                  
                            device['mac_address'] == widget.selectedDeviceMac,
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

  Widget _buildDeviceCard(String name, IconData icon, bool isOn, String macAddress, bool isSelected) {
    return NeumorphicContainer(
      padding: const EdgeInsets.all(16),
      backgroundColor: isSelected ? const Color(0xFFEBF3FF) : const Color(0xFFF7F9FC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon, 
                color: isSelected 
                    ? const Color(0xFF3A86FF) 
                    : (isOn ? const Color(0xFF3A86FF) : const Color(0xFF8E949A)),
              ),
              GestureDetector(
                onTap: () => _showDeleteConfirmationDialog(macAddress, name),
                child: const NeumorphicContainer(
                  padding: EdgeInsets.all(8),
                  borderRadius: 10,
                  child: Icon(
                    Icons.delete_outline,
                    color: Color.fromARGB(255, 253, 16, 16),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),         
          Center(
            child: Text(
              name, 
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isSelected ? const Color(0xFF003566) : Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => _selectDevice(macAddress, isOn),
            child: NeumorphicContainer(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              borderRadius: 12,
              backgroundColor: isSelected ? const Color(0xFF3A86FF) : const Color(0xFFF7F9FC),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.white : const Color(0xFF3A86FF),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isSelected ? 'Active' : 'Select',
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF3A86FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ), 
          ) 
        ],    
      ),  
    );  
  }

  Widget _buildsmartplugbutton() {
    final selectedDevice = _registeredDevices.firstWhere(
      (d) => d['mac_address'] == widget.selectedDeviceMac,
      orElse: () => {},
    );
    final String displayName = selectedDevice.isNotEmpty
        ? (selectedDevice['device_name'] ?? 'Smart Plug')
        : 'Smart Plug';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isPlugOn ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
                boxShadow: [
                  BoxShadow(
                    color: (_isPlugOn ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C))
                        .withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isPlugOn ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _isPlugOn ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        GestureDetector(
          onTap: _togglePlugState,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: _isPlugOn
                  ? [
                      // Inner warm glow
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                      // Mid amber glow
                      BoxShadow(
                        color: const Color(0xFFFFA500).withValues(alpha: 0.25),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                      // Outer soft glow
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                        blurRadius: 80,
                        spreadRadius: 20,
                      ),
                    ]
                  : [],
            ),
            child: AnimatedScale(
              scale: _isPlugOn ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    'assets/smartoutlet.png',
                    width: 260,
                    height: 260,
                  ),
                  IgnorePointer(
                    child: Lottie.asset(
                      'assets/outletin.json',
                      controller: _lottieController,
                      onLoaded: (composition) {
                        _lottieController.duration = composition.duration;
                      },
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_isPlugOn)
                    IgnorePointer(
                      child: Lottie.asset(
                        'assets/pikachulightning.json',
                        width: 260,
                        height: 260,
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        Text(
          displayName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFF003566),
          ),
        ),
      ],
    );
  }
}
