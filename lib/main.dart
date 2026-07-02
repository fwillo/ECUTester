import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'ecu_protocol.dart';
import 'test_log_writer.dart';

const int targetUsbVendorId = 0x0483;
const int targetUsbProductId = 0x5740;
const bool serialDebugLogging = true;

void _logSerial(String message) {
  if (serialDebugLogging) {
    debugPrint('[ECU] $message');
  }
}

String _hexBytes(List<int> bytes, {int maxBytes = 80}) {
  final shown = bytes
      .take(maxBytes)
      .map((byte) {
        return byte.toRadixString(16).padLeft(2, '0').toUpperCase();
      })
      .join(' ');

  if (bytes.length <= maxBytes) return shown;
  return '$shown ... +${bytes.length - maxBytes} bytes';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(EcuTesterApp(serialService: LibSerialPortService()));
}

class EcuTesterApp extends StatelessWidget {
  const EcuTesterApp({super.key, required this.serialService});

  final SerialService serialService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BremerECU Production Tester',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f6f5e),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff5f7f4),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: UartSelectionScreen(serialService: serialService),
    );
  }
}

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

class UartSelectionScreen extends StatefulWidget {
  const UartSelectionScreen({super.key, required this.serialService});

  final SerialService serialService;

  @override
  State<UartSelectionScreen> createState() => _UartSelectionScreenState();
}

class _UartSelectionScreenState extends State<UartSelectionScreen> {
  var _ports = <SerialPortInfo>[];
  var _loading = true;
  var _connectingPort = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  Future<void> _refreshPorts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ports = await widget.serialService.listPorts();
      if (!mounted) return;
      setState(() => _ports = ports);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _connect(SerialPortInfo port) async {
    setState(() => _connectingPort = port.name);
    try {
      final connection = await widget.serialService.connect(port.name);
      if (!mounted) {
        connection.dispose();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DataCollectionScreen(
            serialService: widget.serialService,
            port: port,
            connection: connection,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _connectingPort = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BremerECU Production Tester'),
        actions: [
          IconButton(
            tooltip: 'Refresh ports',
            onPressed: _loading ? null : _refreshPorts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UART Selection',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '115200 8N1 | 10 Hz sampling | $ecuFrameTarget-frame livedata test before final assembly',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Expanded(child: _buildPortList(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: 'Unable to list serial ports',
        message: _error!,
        action: FilledButton.icon(
          onPressed: _refreshPorts,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }

    if (_ports.isEmpty) {
      return _EmptyState(
        icon: Icons.usb_off,
        title: 'No ECU UART found',
        message: 'Connect a BremerECU, then refresh.',
        action: FilledButton.icon(
          onPressed: _refreshPorts,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    }

    return ListView.separated(
      itemCount: _ports.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final port = _ports[index];
        final connecting = _connectingPort == port.name;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: const Icon(Icons.settings_input_component),
            ),
            title: Text(
              port.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [port.subtitle, port.chipLabel].whereType<String>().join('\n'),
              ),
            ),
            trailing: connecting
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _connectingPort.isEmpty ? () => _connect(port) : null,
          ),
        );
      },
    );
  }
}

class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({
    super.key,
    required this.serialService,
    required this.port,
    required this.connection,
  });

  final SerialService serialService;
  final SerialPortInfo port;
  final EcuSerialConnection connection;

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  final _rxBuffer = <int>[];
  final _frames = <EcuFrame>[];
  Timer? _timer;
  EcuFrame? _latestFrame;
  String? _error;
  final _startedAt = DateTime.now();
  var _completed = false;
  var _connectionDisposed = false;
  var _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      unawaited(_requestAndReadFrame());
    });
    unawaited(_requestAndReadFrame());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_connectionDisposed) {
      widget.connection.dispose();
      _connectionDisposed = true;
    }
    super.dispose();
  }

  Future<void> _requestAndReadFrame() async {
    if (_completed || _requestInFlight) return;
    _requestInFlight = true;

    try {
      final data = await widget.connection.requestFrame();
      if (!mounted || _completed || data.isEmpty) return;
      _handleBytes(data);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      _requestInFlight = false;
    }
  }

  void _handleBytes(Uint8List data) {
    _logSerial('RX chunk ${data.length} bytes: ${_hexBytes(data)}');
    _rxBuffer.addAll(data);
    _logSerial('RX buffer now ${_rxBuffer.length} bytes');

    while (_frames.length < ecuFrameTarget) {
      final payload = _takePayload();
      if (payload == null) break;

      try {
        final frame = EcuProtocol.parseFrame(payload);
        _logSerial(
          'Parsed frame ${_frames.length + 1}: ${frame.toDebugString()}',
        );
        setState(() {
          _latestFrame = frame;
          _frames.add(frame);
          _error = null;
        });
      } catch (error) {
        setState(() => _error = error.toString());
      }
    }

    if (_frames.length >= ecuFrameTarget && !_completed) {
      _completed = true;
      _timer?.cancel();
      unawaited(_showResult());
    }
  }

  Uint8List? _takePayload() {
    while (_rxBuffer.length >= ecuPacketLengthPrefixLength) {
      final bodyLength = (_rxBuffer[0] << 8) | _rxBuffer[1];
      if (bodyLength == ecuResponseBodyLength) break;

      _logSerial(
        'Discarding desync byte 0x${_rxBuffer.first.toRadixString(16).padLeft(2, '0').toUpperCase()}; '
        'prefix body length was $bodyLength, expected $ecuResponseBodyLength',
      );
      _rxBuffer.removeAt(0);
    }

    if (_rxBuffer.length < ecuResponsePacketLength) return null;

    final packet = Uint8List.fromList(
      _rxBuffer.sublist(0, ecuResponsePacketLength),
    );
    _rxBuffer.removeRange(0, ecuResponsePacketLength);

    try {
      final response = EcuProtocol.extractResponse(packet);
      _logSerial(
        'Response OK: body=$ecuResponseBodyLength bytes, status=${response.status}, '
        'payload=${response.payload.length} bytes, crc=0x${response.crc.toRadixString(16).padLeft(8, '0').toUpperCase()}',
      );
      return response.payload;
    } on FormatException catch (error) {
      _logSerial('Dropped malformed response: ${error.message}');
      return null;
    }
  }

  Future<void> _showResult() async {
    if (!_connectionDisposed) {
      widget.connection.dispose();
      _connectionDisposed = true;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final result = TestResult.fromFrames(_frames);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TestResultScreen(
          serialService: widget.serialService,
          device: widget.port.toLogDevice(),
          portName: widget.port.name,
          result: result,
          startedAt: _startedAt,
          completedAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _frames.length / ecuFrameTarget;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.port.name),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Text('115200 8N1')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatusStrip(
                          frames: _frames.length,
                          portName: widget.port.name,
                          error: _error,
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final columns =
                                  MediaQuery.sizeOf(context).width > 820
                                  ? 4
                                  : 2;
                              final rows = (EcuMetric.values.length / columns)
                                  .ceil();
                              final tileHeight =
                                  (constraints.maxHeight - (rows - 1) * 12) /
                                  rows;

                              return GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      mainAxisExtent: tileHeight.clamp(
                                        112,
                                        220,
                                      ),
                                    ),
                                itemCount: EcuMetric.values.length,
                                itemBuilder: (context, index) {
                                  final metric = EcuMetric.values[index];
                                  return MetricTile(
                                    metric: metric,
                                    latest: _latestFrame?.valueFor(metric),
                                    average: _averageFor(metric),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Frame collection',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('${_frames.length} / $ecuFrameTarget frames'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        minHeight: 10,
                        value: progress.clamp(0, 1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double? _averageFor(EcuMetric metric) {
    if (_frames.isEmpty) return null;
    final total = _frames.fold<double>(
      0,
      (sum, frame) => sum + frame.valueFor(metric),
    );
    return total / _frames.length;
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.metric,
    required this.latest,
    required this.average,
  });

  final EcuMetric metric;
  final double? latest;
  final double? average;

  @override
  Widget build(BuildContext context) {
    final latestText = latest == null ? '--' : metric.format(latest!);
    final averageText = average == null ? '--' : metric.format(average!);
    final inRange =
        average == null || (average! >= metric.min && average! <= metric.max);
    final color = inRange ? const Color(0xff2f6f5e) : const Color(0xffb42318);

    return Card(
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: FittedBox(
          alignment: Alignment.topLeft,
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 180,
            height: 142,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_metricIcon(metric), color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        metric.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    latestText,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Average $averageText'),
                const SizedBox(height: 4),
                Text(
                  'Target ${metric.rangeLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _metricIcon(EcuMetric metric) {
    return switch (metric) {
      EcuMetric.rpm => Icons.speed,
      EcuMetric.coolant => Icons.thermostat,
      EcuMetric.map => Icons.compress,
      EcuMetric.acceleratorPedal => Icons.pedal_bike,
    };
  }
}

class TestResultScreen extends StatefulWidget {
  const TestResultScreen({
    super.key,
    required this.serialService,
    required this.device,
    required this.portName,
    required this.result,
    required this.startedAt,
    required this.completedAt,
  });

  final SerialService serialService;
  final TestLogDevice device;
  final String portName;
  final TestResult result;
  final DateTime startedAt;
  final DateTime completedAt;

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  late final Future<SavedTestLog> _saveLogFuture;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _saveLogFuture = TestLogWriter().save(
      device: widget.device,
      result: widget.result,
      startedAt: widget.startedAt,
      completedAt: widget.completedAt,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final passed = widget.result.passed;
    final background = passed
        ? const Color(0xff087443)
        : const Color(0xffb42318);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.portName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => UartSelectionScreen(
                            serialService: widget.serialService,
                          ),
                        ),
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('New Test'),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        passed ? Icons.check_circle : Icons.cancel,
                        color: Colors.white,
                        size: 112,
                      ),
                      const SizedBox(height: 24),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          passed ? 'PASS' : 'FAIL',
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 104,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${widget.result.frames.length} frames collected',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      _LogSaveStatus(saveLogFuture: _saveLogFuture),
                      if (!passed) ...[
                        const SizedBox(height: 28),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Failure reason',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  for (final reason
                                      in widget.result.failureReasons)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.error_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              reason,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 10,
                children: [
                  for (final metric in EcuMetric.values)
                    _ResultChip(
                      label: metric.label,
                      value: widget.result.averages[metric] == null
                          ? '--'
                          : metric.format(widget.result.averages[metric]!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogSaveStatus extends StatelessWidget {
  const _LogSaveStatus({required this.saveLogFuture});

  final Future<SavedTestLog> saveLogFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SavedTestLog>(
      future: saveLogFuture,
      builder: (context, snapshot) {
        final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.88),
        );

        if (snapshot.connectionState != ConnectionState.done) {
          return Text('Saving log...', style: textStyle);
        }

        if (snapshot.hasError) {
          return Text(
            'Log save failed: ${snapshot.error}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textStyle,
          );
        }

        final log = snapshot.data!;
        return Text(
          'Log saved: ${log.file.path}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textStyle,
        );
      },
    );
  }
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          '$label $value',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.frames,
    required this.portName,
    required this.error,
  });

  final int frames;
  final String portName;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasError ? const Color(0xfffff0f0) : const Color(0xffedf7f3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError ? const Color(0xffffb3b3) : const Color(0xffb7dfcf),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              hasError ? Icons.warning_amber : Icons.sync,
              color: hasError
                  ? const Color(0xffb42318)
                  : const Color(0xff087443),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasError
                    ? error!
                    : 'Collecting output-channel frames from $portName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text('$frames / $ecuFrameTarget'),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}
