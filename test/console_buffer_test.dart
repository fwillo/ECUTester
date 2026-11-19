import 'package:ecutester/console_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joins chunks and splits lines', () {
    final console = ConsoleBuffer()
      ..write('Erasing ')
      ..write('sector 0\nDone\n');
    expect(console.text, 'Erasing sector 0\nDone\n');
  });

  test('carriage return overwrites the line like a progress bar', () {
    final console = ConsoleBuffer()
      ..write('Download\n  10%\r')
      ..write('  50%\r 100%\n');
    expect(console.text, 'Download\n 100%\n');
  });

  test('CRLF split across chunks is a single newline', () {
    final console = ConsoleBuffer()
      ..write('line 1\r')
      ..write('\nline 2');
    expect(console.text, 'line 1\nline 2');
  });

  test('clear empties the buffer', () {
    final console = ConsoleBuffer()..write('text');
    console.clear();
    expect(console.isEmpty, isTrue);
  });
}
