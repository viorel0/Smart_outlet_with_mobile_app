import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // Service bytes:  4f af c2 01 1f b5 45 9e 8f cc c5 c9 c3 31 91 4b
  // Reversed:       4b9131c3-c9c5-cc8f-9e45-b51f01c2af4f
  static const String serviceUuid = "4b9131c3-c9c5-cc8f-9e45-b51f01c2af4f";

  // SSID char bytes:  be b5 48 3e 36 e1 46 88 b7 f5 ea 07 36 1b 26 a8
  // Reversed:         a8261b36-07ea-f5b7-8846-e1363e48b5be
  static const String ssidCharUuid = "a8261b36-07ea-f5b7-8846-e1363e48b5be";

  // Pass char bytes:  cb a1 d9 4e 28 e1 4b c8 a7 f5 fa 07 36 1b 26 b9
  // Reversed:         b9261b36-07fa-f5a7-c84b-e1284ed9a1cb
  static const String passCharUuid = "b9261b36-07fa-f5a7-c84b-e1284ed9a1cb";

  static const String macCharUuid = "c1261b36-07fa-f5a7-c84b-e1284ed9a1cb";

  static const String esp32DeviceName = "ESP32-Energy-Monitor";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ssidChar;
  BluetoothCharacteristic? _passChar;
  BluetoothCharacteristic? _macChar;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  Future<void> connectAndDiscover(BluetoothDevice device) async {
    await device.connect(
      timeout: const Duration(seconds: 10),
      autoConnect: false,
    );
    _connectedDevice = device;

    await Future.delayed(const Duration(seconds: 1));

    List<BluetoothService> services = await device.discoverServices();

    try {
      await device.requestMtu(128);
    } catch (e) {
      debugPrint('[BLE] MTU negotiation failed: $e');
    }

    _ssidChar = null;
    _passChar = null;
    _macChar = null;

    for (var service in services) {
      debugPrint('[BLE] Service: ${service.uuid}');
      for (var characteristic in service.characteristics) {
        debugPrint(
          '[BLE]   Char: ${characteristic.uuid} | Props: ${characteristic.properties}',
        );
      }
    }

    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == serviceUuid) {
        debugPrint('[BLE] Found ESP32 service: $serviceUuid');
        for (var characteristic in service.characteristics) {
          String uuid = characteristic.uuid.toString().toLowerCase();
          if (uuid == ssidCharUuid) {
            _ssidChar = characteristic;
            debugPrint('[BLE] Found SSID characteristic');
          } else if (uuid == passCharUuid) {
            _passChar = characteristic;
            debugPrint('[BLE] Found Password characteristic');
          } else if (uuid == macCharUuid) {
            _macChar = characteristic;
            debugPrint(
              '[BLE] Found MAC characteristic: ${_macChar.toString()}',
            );
          }
        }
        break;
      }
    }

    if (_ssidChar == null || _passChar == null || _macChar == null) {

      final discoveredUuids = services.map((s) => s.uuid.toString()).toList();
      throw Exception(
        'Nu am găsit characteristics-urile GATT pe dispozitiv.\n'
        'Servicii descoperite: $discoveredUuids\n'
        'Căutam: $serviceUuid\n'
        'Verifică dacă firmware-ul ESP32 are bluenimble.c activ.',
      );
    }
  }
  
  Future<String> readMacAddress() async {
    if (_macChar == null) {
      throw Exception('Caracteristica de MAC nu este inițializată.');
    }
    List<int> bytes = await _macChar!.read();
    String macText = utf8.decode(bytes).trim();
    debugPrint('[BLE] Adresă MAC citită cu succes: $macText');
    return macText;
  }

  
  Future<bool> sendWiFiCredentials(String ssid, String password) async {
    if (_ssidChar == null || _passChar == null) {
      throw Exception(
        'Nu sunt conectat la un dispozitiv BLE sau nu s-au descoperit serviciile.',
      );
    }

    // Scriem SSID-ul pe prima characteristic
    await _ssidChar!.write(utf8.encode(ssid), withoutResponse: false);
    debugPrint('[BLE] SSID trimis: $ssid');

    // Pauză între write-uri
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      await _passChar!.write(utf8.encode(password), withoutResponse: false);
      debugPrint('[BLE] Parola trimisă');
    } catch (e) {
      debugPrint(
        '[BLE] Parola trimisă (ESP32 a deconectat): $e',
      );
    }

    await Future.delayed(const Duration(milliseconds: 500));

    _connectedDevice = null;
    _ssidChar = null;
    _passChar = null;
    _macChar = null;
    return true;
  }

  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {

    }
    _connectedDevice = null;
    _ssidChar = null;
    _passChar = null;
    _macChar = null;
  }
}
