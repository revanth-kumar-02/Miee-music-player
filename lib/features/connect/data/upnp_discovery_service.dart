import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/connect_device.dart';

class DiscoveredUpnpDevice {
  final String usn;
  final String location;
  final String friendlyName;
  final String manufacturer;
  final String modelName;
  final String? controlUrl;
  final DeviceType deviceType;

  const DiscoveredUpnpDevice({
    required this.usn,
    required this.location,
    required this.friendlyName,
    this.manufacturer = '',
    this.modelName = '',
    this.controlUrl,
    this.deviceType = DeviceType.speaker,
  });

  ConnectDevice toConnectDevice() {
    return ConnectDevice(
      id: usn,
      name: friendlyName,
      type: deviceType,
      protocol: DeviceProtocol.dlna,
      isCurrent: false,
      ipAddress: Uri.tryParse(location)?.host,
      lastSeen: DateTime.now(),
    );
  }
}

class UpnpDiscoveryService {
  static final UpnpDiscoveryService _instance = UpnpDiscoveryService._internal();
  factory UpnpDiscoveryService() => _instance;
  UpnpDiscoveryService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ),
  );

  final StreamController<List<DiscoveredUpnpDevice>> _devicesController =
      StreamController<List<DiscoveredUpnpDevice>>.broadcast();
  Stream<List<DiscoveredUpnpDevice>> get devicesStream => _devicesController.stream;

  final Map<String, DiscoveredUpnpDevice> _devices = {};
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  List<DiscoveredUpnpDevice> get discoveredDevices => _devices.values.toList();

  /// Scans the local Wi-Fi network for genuine UPnP / DLNA media renderers and smart TVs.
  Future<void> scan({Duration timeout = const Duration(seconds: 4)}) async {
    if (kIsWeb) return;
    if (_isScanning) return;
    _isScanning = true;

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;

      final multicastAddress = InternetAddress('239.255.255.250');
      const port = 1900;

      // SSDP M-SEARCH requests for media renderers and AV devices
      final targets = [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'ssdp:all',
      ];

      for (final target in targets) {
        final message = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 3\r\n'
            'ST: $target\r\n'
            '\r\n';

        socket.send(utf8.encode(message), multicastAddress, port);
      }

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            _handleSsdpResponse(utf8.decode(datagram.data, allowMalformed: true));
          }
        }
      });

      await Future.delayed(timeout);
    } catch (e) {
      debugPrint('[UpnpDiscoveryService] Scan error: $e');
    } finally {
      socket?.close();
      _isScanning = false;
      _devicesController.add(_devices.values.toList());
    }
  }

  void _handleSsdpResponse(String response) {
    try {
      final lines = response.split('\r\n');
      String? location;
      String? usn;

      for (final line in lines) {
        final lower = line.toLowerCase();
        if (lower.startsWith('location:')) {
          location = line.substring(9).trim();
        } else if (lower.startsWith('usn:')) {
          usn = line.substring(4).trim();
        }
      }

      if (location != null && location.isNotEmpty && usn != null && usn.isNotEmpty) {
        if (!_devices.containsKey(usn)) {
          _fetchDeviceDescription(location, usn);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchDeviceDescription(String locationUrl, String usn) async {
    try {
      final response = await _dio.get<String>(locationUrl);
      final xml = response.data;
      if (xml == null) return;

      final friendlyName = _extractTag(xml, 'friendlyName');
      if (friendlyName == null || friendlyName.isEmpty) return;

      final manufacturer = _extractTag(xml, 'manufacturer') ?? '';
      final modelName = _extractTag(xml, 'modelName') ?? '';
      final deviceTypeTag = _extractTag(xml, 'deviceType') ?? '';

      final isTv = deviceTypeTag.toLowerCase().contains('tv') ||
          friendlyName.toLowerCase().contains('tv') ||
          modelName.toLowerCase().contains('tv');

      // Look for AVTransport controlURL
      String? controlUrl = _extractControlUrl(xml, 'urn:schemas-upnp-org:service:AVTransport:1');
      if (controlUrl != null && !controlUrl.startsWith('http')) {
        final uri = Uri.parse(locationUrl);
        controlUrl = '${uri.scheme}://${uri.host}:${uri.port}${controlUrl.startsWith('/') ? '' : '/'}$controlUrl';
      }

      final device = DiscoveredUpnpDevice(
        usn: usn,
        location: locationUrl,
        friendlyName: friendlyName,
        manufacturer: manufacturer,
        modelName: modelName,
        controlUrl: controlUrl,
        deviceType: isTv ? DeviceType.tv : DeviceType.speaker,
      );

      _devices[usn] = device;
      _devicesController.add(_devices.values.toList());
    } catch (_) {}
  }

  String? _extractTag(String xml, String tag) {
    final start = xml.indexOf('<$tag>');
    final end = xml.indexOf('</$tag>');
    if (start != -1 && end != -1 && end > start) {
      return xml.substring(start + tag.length + 2, end).trim();
    }
    return null;
  }

  String? _extractControlUrl(String xml, String serviceType) {
    final serviceIndex = xml.indexOf(serviceType);
    if (serviceIndex == -1) return null;

    final sub = xml.substring(serviceIndex);
    return _extractTag(sub, 'controlURL');
  }

  /// Sends a UPnP SetAVTransportURI and Play command to a discovered DLNA smart device
  Future<bool> playMediaOnDevice(DiscoveredUpnpDevice device, String mediaUrl) async {
    final controlUrl = device.controlUrl;
    if (controlUrl == null) return false;

    try {
      final setUriSoap = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>$mediaUrl</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';

      await _dio.post(
        controlUrl,
        data: setUriSoap,
        options: Options(
          headers: {
            'SOAPAction': '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
        ),
      );

      final playSoap = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>''';

      await _dio.post(
        controlUrl,
        data: playSoap,
        options: Options(
          headers: {
            'SOAPAction': '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
        ),
      );

      return true;
    } catch (e) {
      debugPrint('[UpnpDiscoveryService] Cast error: $e');
      return false;
    }
  }

  void clear() {
    _devices.clear();
    _devicesController.add([]);
  }
}

