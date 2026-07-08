part of '../../main.dart';

class InitialProgrammingScreen extends StatefulWidget {
  const InitialProgrammingScreen({super.key, required this.serialService});

  final SerialService serialService;

  @override
  State<InitialProgrammingScreen> createState() =>
      _InitialProgrammingScreenState();
}

class _InitialProgrammingScreenState extends State<InitialProgrammingScreen> {
  final _programmerPathController = TextEditingController(
    text: Stm32CubeProgrammer.defaultExecutablePath(),
  );
  final _firmwarePathController = TextEditingController();
  final _flashAddressController = TextEditingController(text: '0x08000000');
  final _programmer = const Stm32CubeProgrammer();

  var _debugInterface = DebugInterface.swd;
  var _programming = false;
  ProgrammingResult? _lastResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _programmerPathController.addListener(_clearProgrammingResult);
    _firmwarePathController.addListener(_clearProgrammingResult);
    _flashAddressController.addListener(_clearProgrammingResult);
  }

  @override
  void dispose() {
    _programmerPathController.removeListener(_clearProgrammingResult);
    _firmwarePathController.removeListener(_clearProgrammingResult);
    _flashAddressController.removeListener(_clearProgrammingResult);
    _programmerPathController.dispose();
    _firmwarePathController.dispose();
    _flashAddressController.dispose();
    super.dispose();
  }

  void _clearProgrammingResult() {
    if (_programming || (_lastResult == null && _error == null)) return;
    setState(() {
      _lastResult = null;
      _error = null;
    });
  }

  Future<void> _pickProgrammerPath() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Executable', extensions: ['exe']),
        const XTypeGroup(label: 'All files'),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _programmerPathController.text = file.path);
  }

  Future<void> _pickFirmwarePath() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Firmware binary', extensions: ['bin']),
        const XTypeGroup(label: 'All files'),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _firmwarePathController.text = file.path);
  }

  Future<void> _programDevice() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _programming = true;
      _error = null;
      _lastResult = null;
    });

    try {
      final result = await _programmer.program(
        ProgrammingRequest(
          executablePath: _programmerPathController.text,
          firmwarePath: _firmwarePathController.text,
          interface: _debugInterface,
          flashAddress: _flashAddressController.text,
        ),
      );
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _error = result.succeeded
            ? null
            : 'STM32CubeProgrammer exited with code ${result.exitCode}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _programming = false);
      }
    }
  }

  void _continueToTesting() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            UartSelectionScreen(serialService: widget.serialService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final programmed = _lastResult?.succeeded == true;

    return Scaffold(
      appBar: AppBar(title: const Text('BremerECU Production Tester')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Initial Programming',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connect the TC2030 cable to program a bare board, or continue directly to the UART production test for an already programmed device.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 920;
                        final imagePanel = _ConnectionImagePanel(
                          height: wide ? double.infinity : 300,
                        );
                        final programmingPanel = _buildProgrammingPanel(
                          context,
                          programmed: programmed,
                        );

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: imagePanel),
                              const SizedBox(width: 18),
                              Expanded(child: programmingPanel),
                            ],
                          );
                        }

                        return ListView(
                          children: [
                            imagePanel,
                            const SizedBox(height: 18),
                            SizedBox(height: 680, child: programmingPanel),
                          ],
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
    );
  }

  Widget _buildProgrammingPanel(
    BuildContext context, {
    required bool programmed,
  }) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'STM32CubeProgrammer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _PathField(
              controller: _programmerPathController,
              label: 'CLI executable',
              icon: Icons.terminal,
              enabled: !_programming,
              onBrowse: _programming ? null : _pickProgrammerPath,
              onReset: _programming
                  ? null
                  : () {
                      setState(() {
                        _programmerPathController.text =
                            Stm32CubeProgrammer.defaultExecutablePath();
                      });
                    },
            ),
            const SizedBox(height: 14),
            _PathField(
              controller: _firmwarePathController,
              label: 'Initial firmware binary',
              icon: Icons.memory,
              enabled: !_programming,
              onBrowse: _programming ? null : _pickFirmwarePath,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final interfaceSelector = SegmentedButton<DebugInterface>(
                  segments: const [
                    ButtonSegment(
                      value: DebugInterface.swd,
                      label: Text('SWD'),
                      icon: Icon(Icons.cable),
                    ),
                    ButtonSegment(
                      value: DebugInterface.jtag,
                      label: Text('JTAG'),
                      icon: Icon(Icons.settings_ethernet),
                    ),
                  ],
                  selected: {_debugInterface},
                  onSelectionChanged: _programming
                      ? null
                      : (selection) {
                          setState(() {
                            _debugInterface = selection.single;
                            _lastResult = null;
                            _error = null;
                          });
                        },
                );
                final addressField = TextField(
                  controller: _flashAddressController,
                  enabled: !_programming,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Flash address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                );

                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      addressField,
                      const SizedBox(height: 12),
                      interfaceSelector,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: addressField),
                    const SizedBox(width: 12),
                    interfaceSelector,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              _ProgrammingNotice(
                icon: Icons.error_outline,
                color: const Color(0xffb42318),
                text: _error!,
              ),
              const SizedBox(height: 12),
            ] else if (programmed) ...[
              const _ProgrammingNotice(
                icon: Icons.check_circle_outline,
                color: Color(0xff087443),
                text: 'Initial firmware programmed and verified.',
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final programButton = FilledButton.icon(
                  onPressed: _programming ? null : _programDevice,
                  icon: _programming
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_programming ? 'Programming...' : 'Program'),
                );
                final testButton = OutlinedButton.icon(
                  onPressed: _programming ? null : _continueToTesting,
                  icon: const Icon(Icons.chevron_right),
                  label: Text(
                    programmed
                        ? 'Continue to UART Test'
                        : 'Test Already Programmed',
                  ),
                );

                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      programButton,
                      const SizedBox(height: 10),
                      testButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: programButton),
                    const SizedBox(width: 12),
                    Expanded(child: testButton),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(child: _ProgramOutput(result: _lastResult)),
          ],
        ),
      ),
    );
  }
}

class _ConnectionImagePanel extends StatelessWidget {
  const _ConnectionImagePanel({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.cable,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connect TC2030 to the bare board',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xffeef2ee),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'TCAnschliessen.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Text(
                          'TCAnschliessen.png could not be loaded.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onBrowse,
    this.onReset,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onBrowse;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReset != null)
              IconButton(
                tooltip: 'Use default path',
                onPressed: enabled ? onReset : null,
                icon: const Icon(Icons.restart_alt),
              ),
            IconButton(
              tooltip: 'Choose file',
              onPressed: enabled ? onBrowse : null,
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgrammingNotice extends StatelessWidget {
  const _ProgrammingNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgramOutput extends StatelessWidget {
  const _ProgramOutput({required this.result});

  final ProgrammingResult? result;

  @override
  Widget build(BuildContext context) {
    final output = result == null
        ? 'Programmer output will appear here.'
        : [
            result!.commandLine,
            '',
            if (result!.stdout.trim().isNotEmpty) result!.stdout.trimRight(),
            if (result!.stderr.trim().isNotEmpty) result!.stderr.trimRight(),
          ].join('\n');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff1f2421),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: SelectableText(
            output,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xffe8f1ea),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
