part of '../main.dart';

abstract class SerialService {
  Future<List<SerialPortInfo>> listPorts();
  Future<EcuSerialConnection> connect(String portName);
}

abstract class EcuSerialConnection {
  String get portName;
  Future<Uint8List> requestFrame();
  void dispose();
}

class SerialPortInfo {
  const SerialPortInfo({
    required this.name,
    this.description,
    this.manufacturer,
    this.productName,
    this.serialNumber,
    this.vendorId,
    this.productId,
  });

  final String name;
  final String? description;
  final String? manufacturer;
  final String? productName;
  final String? serialNumber;
  final int? vendorId;
  final int? productId;

  String get subtitle {
    final parts = [
      productName,
      manufacturer,
      description,
      serialNumber == null ? null : 'SN $serialNumber',
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Serial port' : parts.join(' | ');
  }

  String? get chipLabel {
    if (vendorId == null && productId == null) return null;
    final vid = vendorId?.toRadixString(16).padLeft(4, '0').toUpperCase();
    final pid = productId?.toRadixString(16).padLeft(4, '0').toUpperCase();
    return [if (vid != null) 'VID $vid', if (pid != null) 'PID $pid'].join(' ');
  }

  TestLogDevice toLogDevice() {
    return TestLogDevice(
      portName: name,
      description: description,
      manufacturer: manufacturer,
      productName: productName,
      serialNumber: serialNumber,
      vendorId: vendorId,
      productId: productId,
    );
  }
}

class LibSerialPortService implements SerialService {
  @override
  Future<List<SerialPortInfo>> listPorts() async {
    if (Platform.isWindows) {
      // libserialport resolves VID/PID on Windows by walking the USB hub
      // tree, which is unreliable for composite devices (COM port on
      // interface MI_01). Ask Windows for the present devices instead.
      final portNames = await _findWindowsPortsByUsbId(
        targetUsbVendorId,
        targetUsbProductId,
      );
      _logSerial(
        'Available ports: ${SerialPort.availablePorts.join(', ')}; '
        'matching VID/PID: ${portNames.join(', ')}',
      );
      return portNames
          .map(
            (name) => _readPortInfo(
              name,
              knownIds: (targetUsbVendorId, targetUsbProductId),
            ),
          )
          .whereType<SerialPortInfo>()
          .toList();
    }

    final ports = SerialPort.availablePorts;
    return ports
        // On macOS, querying USB info of non-USB ports (Bluetooth,
        // debug-console) throws a SerialPortError with a stale errno.
        .where(
          (name) => !Platform.isMacOS || name.startsWith('/dev/cu.usbmodem'),
        )
        .map(_readPortInfo)
        .whereType<SerialPortInfo>()
        .where(
          (port) =>
              port.vendorId == targetUsbVendorId &&
              port.productId == targetUsbProductId,
        )
        .toList();
  }

  SerialPortInfo? _readPortInfo(String portName, {(int, int)? knownIds}) {
    final port = SerialPort(portName);
    try {
      return SerialPortInfo(
        name: portName,
        description: port.description,
        manufacturer: port.manufacturer,
        productName: port.productName,
        serialNumber: port.serialNumber,
        vendorId: knownIds?.$1 ?? port.vendorId,
        productId: knownIds?.$2 ?? port.productId,
      );
    } on SerialPortError catch (error) {
      _logSerial('Unable to read details of $portName: ${error.message}');
      if (knownIds == null) return null;
      return SerialPortInfo(
        name: portName,
        vendorId: knownIds.$1,
        productId: knownIds.$2,
      );
    } finally {
      port.dispose();
    }
  }

  /// Returns the COM port names of all currently present USB devices with
  /// the given VID/PID, as listed in Device Manager.
  Future<List<String>> _findWindowsPortsByUsbId(int vid, int pid) async {
    String hex(int value) =>
        value.toRadixString(16).padLeft(4, '0').toUpperCase();
    // Win32_PnPEntity only contains present devices; the COM port name is
    // stored in the device's "Device Parameters" registry key.
    final script =
        r"$ErrorActionPreference = 'SilentlyContinue'; "
        r'Get-CimInstance Win32_PnPEntity -Filter '
        '"PNPDeviceID LIKE \'USB\\\\VID_${hex(vid)}&PID_${hex(pid)}%\'" | '
        r'ForEach-Object { (Get-ItemProperty '
        r'"HKLM:\SYSTEM\CurrentControlSet\Enum\$($_.PNPDeviceID)\Device Parameters"'
        r').PortName }';
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]);
      if (result.exitCode != 0) {
        _logSerial('Device query failed: ${result.stderr}');
      }
      return (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.toUpperCase().startsWith('COM'))
          .toSet()
          .toList()
        ..sort();
    } on ProcessException catch (error) {
      _logSerial('Unable to query devices: ${error.message}');
      return const [];
    }
  }

  @override
  Future<EcuSerialConnection> connect(String portName) async {
    return LibSerialConnection.open(portName);
  }
}

class LibSerialConnection implements EcuSerialConnection {
  LibSerialConnection._(this._port, this.portName);

  factory LibSerialConnection.open(String portName) {
    final port = SerialPort(portName);
    var opened = false;

    try {
      opened = port.openReadWrite();
      if (!opened) {
        throw StateError(
          SerialPort.lastError?.message ?? 'Unable to open port.',
        );
      }

      final config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);
      port.config = config;
      port.flush(SerialPortBuffer.both);

      return LibSerialConnection._(port, portName);
    } catch (error) {
      if (opened) port.close();
      port.dispose();
      rethrow;
    }
  }

  final SerialPort _port;
  var _disposed = false;

  @override
  final String portName;

  @override
  Future<Uint8List> requestFrame() async {
    if (_disposed) return Uint8List(0);

    final request = EcuProtocol.makeDataRequest();
    _port.write(request, timeout: 50);
    return _readResponseBytes();
  }

  Future<Uint8List> _readResponseBytes() async {
    final bytes = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(const Duration(milliseconds: 250));

    while (!_disposed &&
        _port.isOpen &&
        DateTime.now().isBefore(deadline) &&
        bytes.length < ecuResponsePacketLength) {
      final available = _port.bytesAvailable;
      if (available > 0) {
        bytes.add(_port.read(available));
      }
      if (bytes.length >= ecuResponsePacketLength) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    return bytes.takeBytes();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    if (_port.isOpen) {
      _port.close();
    }
    _port.dispose();
  }
}
