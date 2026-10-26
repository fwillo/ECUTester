part of '../../main.dart';

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
    this.infinite = false,
  });

  final int frames;
  final String portName;
  final String? error;
  final bool infinite;

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
            Text(infinite ? '$frames' : '$frames / $ecuFrameTarget'),
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
