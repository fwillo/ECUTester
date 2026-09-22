import 'dart:io';

import 'package:ecutester/initial_programming.dart';
import 'package:ecutester/programming_log_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves iteratively numbered programming logs per device id', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ecutester_programming_logs_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final writer = ProgrammingLogWriter(baseDirectory: temp);
    final result = ProgrammingResult(
      deviceId: '002900313334510B38313936',
      startedAt: DateTime.utc(2026, 7, 9, 8),
      completedAt: DateTime.utc(2026, 7, 9, 8, 1),
      uidReadCommandLine: 'STM32_Programmer_CLI -c port=SWD -r32 0x1FF0F420 12',
      uidReadExitCode: 0,
      uidReadStdout: '0x1FF0F420 : 00290031 3334510B 38313936',
      uidReadStderr: '',
      commandLine:
          'STM32_Programmer_CLI -c port=SWD -w firmware.bin 0x08000000',
      exitCode: 0,
      stdout: 'Download verified successfully',
      stderr: '',
    );

    final first = await writer.save(result);
    final second = await writer.save(result);

    expect(first.index, 1);
    expect(second.index, 2);
    expect(
      first.file.path,
      endsWith('002900313334510B38313936/programming_0001.csv'),
    );
    expect(
      second.file.path,
      endsWith('002900313334510B38313936/programming_0002.csv'),
    );

    final csv = await first.file.readAsString();
    expect(csv, contains('# Result,PASS'));
    expect(csv, contains('# Device ID,"002900313334510B38313936"'));
    expect(
      csv,
      contains('"programming","stdout","Download verified successfully"'),
    );
  });
}
