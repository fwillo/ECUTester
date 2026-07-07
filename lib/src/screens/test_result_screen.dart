part of '../../main.dart';

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
                          builder: (_) => InitialProgrammingScreen(
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
