import 'dart:io';
import 'package:flutter/foundation.dart';

class UdpService {
  final int port;
  final Function(List<double>) onDataReceived;
  final Function(String) onMacAddressReceived;
  RawDatagramSocket? _socket;

  UdpService({required this.port, required this.onDataReceived, required this.onMacAddressReceived});

  void start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      debugPrint("Socket UDP pornit pe portul $port.");
      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _socket?.receive();
          if (datagram != null && datagram.data.lengthInBytes == 2632) {
            String macAddress = datagram.data.sublist(0, 6).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
            onMacAddressReceived(macAddress);
            Float32List floats = Float32List.view(datagram.data.buffer, 8, 656);
            onDataReceived(floats.toList());
          }
        }
      });
    } catch (e) {
      debugPrint("Eroare în serviciul UDP: $e");
    }
  }

  void stop() {
    _socket?.close();
    debugPrint("Socket UDP oprit.");
  }
}
