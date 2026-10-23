part of '../../main.dart';

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
    _rxBuffer.addAll(data);

    while (_frames.length < ecuFrameTarget) {
      final payload = _takePayload();
      if (payload == null) break;

      try {
        final frame = EcuProtocol.parseFrame(payload);
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
    final inRange = average == null || metric.isPassing(average!);
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
      EcuMetric.vBatt => Icons.battery_charging_full,
      EcuMetric.iat => Icons.air,
    };
  }
}
