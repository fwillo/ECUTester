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
    final ports = SerialPort.availablePorts;
    return ports
        .map(_readPortInfo)
        .where(
          (port) =>
              port.vendorId == targetUsbVendorId &&
              port.productId == targetUsbProductId,
        )
        .toList();
  }

  SerialPortInfo _readPortInfo(String portName) {
    final port = SerialPort(portName);
    try {
      return SerialPortInfo(
        name: portName,
        description: port.description,
        manufacturer: port.manufacturer,
        productName: port.productName,
        serialNumber: port.serialNumber,
        vendorId: port.vendorId,
        productId: port.productId,
      );
    } finally {
      port.dispose();
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
    final written = _port.write(request, timeout: 50);
    _logSerial('TX $written/${request.length} bytes: ${_hexBytes(request)}');
    return _readResponseBytes();
  }

  Future<Uint8List> _readResponseBytes() async {
    final bytes = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(const Duration(milliseconds: 80));

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
