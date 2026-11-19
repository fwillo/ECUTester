import 'dart:io';

import 'package:ecutester/initial_programming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streams output while the process runs and strips ANSI codes', () async {
    final chunks = <String>[];
    final result = await runStreamingProcess('/bin/sh', [
      '-c',
      r'printf "\033[32mfirst\033[0m\n"; sleep 0.3; printf "second\n" >&2',
    ], chunks.add);

    expect(result.exitCode, 0);
    expect(chunks.length, greaterThanOrEqualTo(2));
    expect(chunks.join(), 'first\nsecond\n');
    expect(stripAnsiEscapeCodes(result.stdout as String), 'first\n');
    expect(result.stderr, 'second\n');
  }, skip: Platform.isWindows ? 'needs /bin/sh' : false);
}
