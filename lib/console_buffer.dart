/// Collects streamed console output the way a terminal shows it: '\n' starts
/// a new line, a lone '\r' returns to the start of the line so the next text
/// overwrites it (used by CubeProgrammer's progress bar), '\r\n' is a newline.
class ConsoleBuffer {
  final _lines = <String>[''];
  var _pendingCarriageReturn = false;

  bool get isEmpty => _lines.length == 1 && _lines.single.isEmpty;

  String get text => _lines.join('\n');

  void clear() {
    _lines
      ..clear()
      ..add('');
    _pendingCarriageReturn = false;
  }

  void write(String chunk) {
    final current = StringBuffer(_lines.removeLast());
    for (var i = 0; i < chunk.length; i++) {
      final char = chunk[i];
      if (char == '\n') {
        _pendingCarriageReturn = false;
        _lines.add(current.toString());
        current.clear();
        continue;
      }
      if (_pendingCarriageReturn) {
        _pendingCarriageReturn = false;
        current.clear();
      }
      if (char == '\r') {
        _pendingCarriageReturn = true;
      } else {
        current.write(char);
      }
    }
    _lines.add(current.toString());
  }
}
