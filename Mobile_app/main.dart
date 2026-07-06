import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:energymon/home_dashboard.dart';
import 'package:energymon/energy_stats.dart';
import 'package:energymon/power_metrics.dart';
import 'package:energymon/analytics_charts.dart';
import 'package:energymon/settings_screen.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:energymon/auth_screen.dart';
import 'package:flutter/services.dart';

//aici trebuie introduse din supabase url si anon key, altfel nu se poate conecta la baza de date
const String supabaseUrl = '';
const String supabaseAnonKey = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

   // fortare orientare verticala
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // debugPaintSizeEnabled = true;
  runApp(const SmartHomeApp());
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartHome',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        fontFamily: 'Manrope',
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
   
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const MainNavigation();
        }

        return const LoginScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  String? _selectedDeviceMac;

  void _onDeviceSelected(String mac, String name) {
    setState(() {
      _selectedDeviceMac = mac;
    });
  }


  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeDashboard(
        selectedDeviceMac: _selectedDeviceMac,
        onDeviceSelected: _onDeviceSelected,
      ),
      EnergyStats(selectedDeviceMac: _selectedDeviceMac),
      PowerMetrics(selectedDeviceMac: _selectedDeviceMac),
      AnalyticsChartsScreen(selectedDeviceMac: _selectedDeviceMac),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NeumorphicBottomBar(
        selectedIndex: _selectedIndex,
        onItemSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}
