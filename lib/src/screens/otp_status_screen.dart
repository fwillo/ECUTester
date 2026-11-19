part of '../../main.dart';

const _otpGreen = Color(0xff087443);
const _otpRed = Color(0xffb42318);
const _otpAmber = Color(0xffb54708);
const _otpGrey = Color(0xff667085);

class OtpStatusScreen extends StatefulWidget {
  const OtpStatusScreen({
    super.key,
    required this.executablePath,
    required this.interface,
  });

  final String executablePath;
  final DebugInterface interface;

  @override
  State<OtpStatusScreen> createState() => _OtpStatusScreenState();
}

class _OtpStatusScreenState extends State<OtpStatusScreen> {
  OtpState? _state;
  DateTime? _readAt;
  String? _error;
  String _transcript = '';
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final programmer = OtpProgrammer(
      executablePath: widget.executablePath,
      interface: widget.interface,
    );
    try {
      if (!await File(widget.executablePath).exists()) {
        throw OtpException(
          'STM32CubeProgrammer CLI not found: ${widget.executablePath}',
        );
      }
      final state = await programmer.readOtp();
      if (!mounted) return;
      setState(() {
        _state = state;
        _readAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _transcript = programmer.transcript;
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyAsText() async {
    final state = _state;
    if (state == null) return;
    await Clipboard.setData(ClipboardData(text: state.toText()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('OTP status copied as text.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Status'),
        actions: [
          IconButton(
            tooltip: 'Copy as text',
            onPressed: _state == null || _loading ? null : _copyAsText,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Read again',
            onPressed: _loading ? null : _read,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Hardware revision OTP blocks',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(_subtitle(), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 22),
                if (_loading && _state == null)
                  const _OtpLoading()
                else ...[
                  if (_error != null) ...[
                    _ProgrammingNotice(
                      icon: Icons.error_outline,
                      color: _otpRed,
                      text: 'Reading the OTP area failed: $_error',
                    ),
                    const SizedBox(height: 18),
                    if (_transcript.trim().isNotEmpty)
                      _OtpTranscript(text: _transcript),
                  ],
                  if (_state != null) ...[
                    if (_loading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    _OtpSummary(state: _state!),
                    const SizedBox(height: 18),
                    _OtpBlockTable(state: _state!),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final base =
        'Read from 0x1FF0F000 via ${widget.interface.cliValue}. '
        'The firmware uses the last valid block.';
    final readAt = _readAt;
    if (readAt == null) return base;
    final time = [
      readAt.hour,
      readAt.minute,
      readAt.second,
    ].map((v) => v.toString().padLeft(2, '0')).join(':');
    return '$base Last read at $time.';
  }
}

class _OtpLoading extends StatelessWidget {
  const _OtpLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Reading OTP area with STM32CubeProgrammer...'),
        ],
      ),
    );
  }
}

class _OtpSummary extends StatelessWidget {
  const _OtpSummary({required this.state});

  final OtpState state;

  @override
  Widget build(BuildContext context) {
    final blocks = state.blocks;
    final effective = state.effective;
    final nextFree = state.nextFreeBlock;
    int count(OtpBlockKind kind) => blocks.where((b) => b.kind == kind).length;
    final locked = blocks.where((b) => b.locked).length;

    final tiles = [
      _OtpSummaryTile(
        icon: Icons.verified_outlined,
        color: effective != null
            ? _otpGreen
            : (state.anyProgrammed ? _otpRed : _otpGrey),
        label: 'Firmware shows',
        value:
            effective?.revision ??
            (state.anyProgrammed ? 'INVALID' : 'UNPROGRAMMED'),
        detail: effective != null
            ? 'Block ${effective.index}'
            : 'No valid block found',
      ),
      _OtpSummaryTile(
        icon: Icons.edit_note,
        color: nextFree != null ? _otpGreen : _otpAmber,
        label: 'Next write goes to',
        value: nextFree != null ? 'Block $nextFree' : 'No free block',
        detail: nextFree != null
            ? _hexAddr(otpBase + nextFree * otpBlockSize)
            : 'OTP area is full',
      ),
      _OtpSummaryTile(
        icon: Icons.grid_view,
        color: _otpGrey,
        label: 'Blocks',
        value:
            '${count(OtpBlockKind.valid)} valid · '
            '${count(OtpBlockKind.invalid)} invalid',
        detail:
            '${count(OtpBlockKind.erased)} erased · $locked of '
            '$otpBlockCount locked',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tile in tiles) ...[tile, const SizedBox(height: 8)],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OtpSummaryTile extends StatelessWidget {
  const _OtpSummaryTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpBlockTable extends StatelessWidget {
  const _OtpBlockTable({required this.state});

  final OtpState state;

  @override
  Widget build(BuildContext context) {
    final blocks = state.blocks;
    final effectiveIndex = state.effective?.index;
    final nextFree = state.nextFreeBlock;
    final headerStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _OtpRowLayout(
              block: Text('Block', style: headerStyle),
              address: Text('Address', style: headerStyle),
              lock: Text('Lock', style: headerStyle),
              status: Text('Status', style: headerStyle),
              content: Text('Content', style: headerStyle),
            ),
          ),
          for (final block in blocks) ...[
            const Divider(height: 1),
            _OtpBlockRow(
              block: block,
              inUse: block.index == effectiveIndex,
              nextWrite: block.index == nextFree,
            ),
          ],
        ],
      ),
    );
  }
}

/// Fixed column widths so header and rows line up.
class _OtpRowLayout extends StatelessWidget {
  const _OtpRowLayout({
    required this.block,
    required this.address,
    required this.lock,
    required this.status,
    required this.content,
  });

  final Widget block;
  final Widget address;
  final Widget lock;
  final Widget status;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 56, child: block),
        SizedBox(width: 120, child: address),
        SizedBox(width: 100, child: lock),
        SizedBox(width: 110, child: status),
        Expanded(child: content),
      ],
    );
  }
}

class _OtpBlockRow extends StatelessWidget {
  const _OtpBlockRow({
    required this.block,
    required this.inUse,
    required this.nextWrite,
  });

  final OtpBlockStatus block;
  final bool inUse;
  final bool nextWrite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mono = textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final (statusLabel, statusColor) = switch (block.kind) {
      OtpBlockKind.valid => ('Valid', _otpGreen),
      OtpBlockKind.invalid => ('Invalid', _otpRed),
      OtpBlockKind.erased => ('Erased', _otpGrey),
    };

    final Widget content = switch (block.kind) {
      OtpBlockKind.valid => Text(
        block.revision!,
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      OtpBlockKind.invalid => Text(
        block.reason!,
        style: textTheme.bodyMedium?.copyWith(color: _otpRed),
      ),
      OtpBlockKind.erased => Text(
        block.locked ? 'Locked while erased, unusable' : '',
        style: textTheme.bodyMedium?.copyWith(color: muted),
      ),
    };

    return Container(
      color: inUse ? _otpGreen.withValues(alpha: 0.06) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OtpRowLayout(
            block: Text(block.index.toString(), style: textTheme.titleMedium),
            address: Text(_hexAddr(block.address), style: mono),
            lock: Row(
              children: [
                Icon(
                  block.locked ? Icons.lock : Icons.lock_open,
                  size: 18,
                  color: block.locked ? null : muted,
                ),
                const SizedBox(width: 6),
                Text(
                  block.locked ? 'Locked' : 'Open',
                  style: textTheme.bodyMedium?.copyWith(
                    color: block.locked ? null : muted,
                  ),
                ),
              ],
            ),
            status: Align(
              alignment: Alignment.centerLeft,
              child: _OtpBadge(label: statusLabel, color: statusColor),
            ),
            content: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                content,
                if (inUse)
                  const _OtpBadge(
                    label: 'Used by firmware',
                    color: _otpGreen,
                    icon: Icons.check,
                  ),
                if (nextWrite)
                  const _OtpBadge(
                    label: 'Next write',
                    color: _otpAmber,
                    icon: Icons.arrow_forward,
                  ),
              ],
            ),
          ),
          if (block.kind == OtpBlockKind.invalid) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff1f2421),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      otpHexdump(block.bytes, block.address, indent: ''),
                      style: textTheme.bodySmall?.copyWith(
                        color: const Color(0xffe8f1ea),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OtpBadge extends StatelessWidget {
  const _OtpBadge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpTranscript extends StatelessWidget {
  const _OtpTranscript({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff1f2421),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text.trimRight(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xffe8f1ea),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

String _hexAddr(int address) =>
    '0x${address.toRadixString(16).toUpperCase().padLeft(8, '0')}';
