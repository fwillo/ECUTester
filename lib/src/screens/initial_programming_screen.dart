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
  final _calibrationPathController = TextEditingController();
  final _flashAddressController = TextEditingController(text: '0x08000000');
  final _hwRevisionController = TextEditingController(text: 'Rev 1.14');
  final _programmer = const Stm32CubeProgrammer();
  final _settingsStore = ProgrammingSettingsStore();

  var _debugInterface = DebugInterface.swd;
  var _programming = false;
  var _skipHwRevision = false;
  ProgrammingResult? _lastResult;
  final _console = ConsoleBuffer();
  Timer? _consoleRefresh;
  SavedProgrammingLog? _savedLog;
  String? _logError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _programmerPathController.addListener(_clearProgrammingResult);
    _firmwarePathController.addListener(_clearProgrammingResult);
    _calibrationPathController.addListener(_clearProgrammingResult);
    _flashAddressController.addListener(_clearProgrammingResult);
    _hwRevisionController.addListener(_clearProgrammingResult);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      if (_firmwarePathController.text.isEmpty) {
        _firmwarePathController.text = settings.firmwarePath;
      }
      if (_calibrationPathController.text.isEmpty) {
        _calibrationPathController.text = settings.calibrationPath;
      }
    });
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsStore.save(
        ProgrammingSettings(
          firmwarePath: _firmwarePathController.text.trim(),
          calibrationPath: _calibrationPathController.text.trim(),
        ),
      );
    } catch (error) {
      debugPrint('Saving programming settings failed: $error');
    }
  }

  @override
  void dispose() {
    _programmerPathController.removeListener(_clearProgrammingResult);
    _firmwarePathController.removeListener(_clearProgrammingResult);
    _calibrationPathController.removeListener(_clearProgrammingResult);
    _flashAddressController.removeListener(_clearProgrammingResult);
    _hwRevisionController.removeListener(_clearProgrammingResult);
    _programmerPathController.dispose();
    _firmwarePathController.dispose();
    _calibrationPathController.dispose();
    _flashAddressController.dispose();
    _hwRevisionController.dispose();
    _consoleRefresh?.cancel();
    super.dispose();
  }

  void _clearProgrammingResult() {
    if (_programming || (_lastResult == null && _error == null)) return;
    setState(() {
      _lastResult = null;
      _savedLog = null;
      _logError = null;
      _error = null;
      _console.clear();
    });
  }

  /// Adds live CLI output. Repaints at most every 50 ms, because the
  /// progress bar sends many small chunks.
  void _appendConsole(String text) {
    _console.write(text);
    _consoleRefresh ??= Timer(const Duration(milliseconds: 50), () {
      _consoleRefresh = null;
      if (mounted) setState(() {});
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
    await _saveSettings();
  }

  Future<void> _pickCalibrationPath() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Calibration binary', extensions: ['bin']),
        const XTypeGroup(label: 'All files'),
      ],
    );
    if (file == null || !mounted) return;
    setState(() => _calibrationPathController.text = file.path);
    await _saveSettings();
  }

  Future<void> _programDevice() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _programming = true;
      _error = null;
      _lastResult = null;
      _savedLog = null;
      _logError = null;
      _console.clear();
    });
    await _saveSettings();

    try {
      final result = await _programmer.program(
        ProgrammingRequest(
          executablePath: _programmerPathController.text,
          firmwarePath: _firmwarePathController.text,
          calibrationPath: _calibrationPathController.text,
          interface: _debugInterface,
          flashAddress: _flashAddressController.text,
          hwRevision: _hwRevisionController.text,
          skipHwRevision: _skipHwRevision,
        ),
        onOutput: _appendConsole,
      );
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _error = !result.flashSucceeded
            ? 'STM32CubeProgrammer exited with code ${result.exitCode}.'
            : result.otpError != null
            ? 'Firmware programmed and verified, but writing the HW revision '
                  'to OTP failed: ${result.otpError}'
            : null;
      });

      try {
        final savedLog = await ProgrammingLogWriter().save(result);
        if (!mounted) return;
        setState(() => _savedLog = savedLog);
      } catch (error) {
        if (!mounted) return;
        setState(() => _logError = error.toString());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _programming = false);
      }
    }
  }

  void _openOtpStatus() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtpStatusScreen(
          executablePath: _programmerPathController.text.trim(),
          interface: _debugInterface,
        ),
      ),
    );
  }

  void _continueToTesting() {
    Navigator.of(context).push(
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
                        const imagePanel = _ConnectionImagePanel();
                        final programmingPanel = _buildProgrammingPanel(
                          context,
                          programmed: programmed,
                        );
                        final output = _ProgramOutput(
                          text: _console.isEmpty
                              ? 'Programmer output will appear here.'
                              : _console.text,
                        );

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    imagePanel,
                                    const SizedBox(height: 18),
                                    Expanded(child: output),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(child: programmingPanel),
                            ],
                          );
                        }

                        return ListView(
                          children: [
                            imagePanel,
                            const SizedBox(height: 18),
                            SizedBox(height: 320, child: output),
                            const SizedBox(height: 18),
                            programmingPanel,
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
      // No bottom margin so the card ends level with the command output.
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: SingleChildScrollView(
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
            _PathField(
              controller: _calibrationPathController,
              label:
                  'Default calibration binary (0x08100000 + copy at 0x08140000)',
              icon: Icons.tune,
              enabled: !_programming,
              onBrowse: _programming ? null : _pickCalibrationPath,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _flashAddressController,
                    enabled: !_programming,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Flash address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<DebugInterface>(
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
                            _console.clear();
                          });
                        },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hwRevisionController,
                    enabled: !_programming && !_skipHwRevision,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'HW Revision string',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _programming ? null : _openOtpStatus,
                  icon: const Icon(Icons.memory),
                  label: const Text('OTP status'),
                ),
              ],
            ),
            CheckboxListTile(
              value: _skipHwRevision,
              onChanged: _programming
                  ? null
                  : (value) {
                      setState(() {
                        _skipHwRevision = value ?? false;
                        _lastResult = null;
                        _error = null;
                        _console.clear();
                      });
                    },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Skip HW revision OTP write'),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _programming ? null : _programDevice,
                    icon: _programming
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(
                      _programming ? 'Programming...' : 'Program',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _programming ? null : _continueToTesting,
                    icon: const Icon(Icons.chevron_right),
                    label: Text(
                      programmed
                          ? 'Continue to UART Test'
                          : 'Test Already Programmed',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ProgrammingNotice(
                icon: Icons.error_outline,
                color: const Color(0xffb42318),
                text: _error!,
              ),
            ] else if (programmed) ...[
              const SizedBox(height: 12),
              _ProgrammingNotice(
                icon: Icons.check_circle_outline,
                color: const Color(0xff087443),
                text:
                    'Initial firmware and default calibration programmed and '
                    'verified. ${_lastResult!.hwRevisionSkipped ? 'HW revision OTP write skipped.' : _lastResult!.otpResult?.summary ?? ''}',
              ),
            ],
            if (_savedLog != null) ...[
              const SizedBox(height: 12),
              _ProgrammingNotice(
                icon: Icons.description_outlined,
                color: const Color(0xff2f6f5e),
                text: 'Programming log saved: ${_savedLog!.file.path}',
              ),
            ] else if (_logError != null) ...[
              const SizedBox(height: 12),
              _ProgrammingNotice(
                icon: Icons.warning_amber,
                color: const Color(0xffb54708),
                text: 'Programming log save failed: $_logError',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionImagePanel extends StatelessWidget {
  const _ConnectionImagePanel();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.cable, color: Theme.of(context).colorScheme.primary),
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
          ColoredBox(
            color: const Color(0xffeef2ee),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.8,
                  child: Image.asset(
                    'TCAnschliessen.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Text(
                        'TCAnschliessen.png could not be loaded.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
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

class _ProgramOutput extends StatefulWidget {
  const _ProgramOutput({required this.text});

  final String text;

  @override
  State<_ProgramOutput> createState() => _ProgramOutputState();
}

class _ProgramOutputState extends State<_ProgramOutput> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ProgramOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == oldWidget.text || !_scrollController.hasClients) return;
    // Follow new output, unless the user scrolled up to read something.
    final position = _scrollController.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 24;
    if (!atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff1f2421),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: SelectableText(
            widget.text,
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
