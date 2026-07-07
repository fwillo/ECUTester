part of '../../main.dart';

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
