import 'package:ecutester/initial_programming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds STM32CubeProgrammer arguments for SWD binary programming', () {
    const request = ProgrammingRequest(
      executablePath: '/Applications/ST/STM32_Programmer_CLI',
      firmwarePath: '/tmp/initial.bin',
      interface: DebugInterface.swd,
      flashAddress: '0x08000000',
    );

    expect(Stm32CubeProgrammer.buildArguments(request), [
      '-c',
      'port=SWD',
      'mode=UR',
      '-w',
      '/tmp/initial.bin',
      '0x08000000',
      '-v',
      '-rst',
    ]);
  });

  test('builds STM32CubeProgrammer arguments for STM32F767 UID read', () {
    const request = ProgrammingRequest(
      executablePath: '/Applications/ST/STM32_Programmer_CLI',
      firmwarePath: '/tmp/initial.bin',
      interface: DebugInterface.swd,
      flashAddress: '0x08000000',
    );

    expect(Stm32CubeProgrammer.buildUniqueIdReadArguments(request), [
      '-c',
      'port=SWD',
      'mode=UR',
      '-r32',
      '0x1FF0F420',
      '12',
    ]);
  });

  test('formats command line with quoted paths', () {
    final command = Stm32CubeProgrammer.formatCommand(
      '/Applications/ST Tools/STM32_Programmer_CLI',
      ['-w', '/tmp/initial firmware.bin', '0x08000000'],
    );

    expect(
      command,
      "'/Applications/ST Tools/STM32_Programmer_CLI' -w "
      "'/tmp/initial firmware.bin' 0x08000000",
    );
  });

  test('strips ANSI formatting from CLI output', () {
    expect(
      stripAnsiEscapeCodes(
        '\x1B[36m\x1B[01mSTM32CubeProgrammer\x1B[39;49m\x1B[0m\n'
        '\x1B[00;31mError: No debug probe detected.\x1B[39;49m\x1B[0m',
      ),
      'STM32CubeProgrammer\nError: No debug probe detected.',
    );
  });

  test('extracts STM32F767 unique ID from CubeProgrammer memory dump', () {
    const output = '''
Reading 32-bit memory content
  Size          : 12 Bytes
  Address       : 0x1FF0F420
0x1FF0F420 : 00290031 3334510B 38313936
''';

    expect(
      extractUniqueIdFromCubeProgrammerOutput(output),
      '002900313334510B38313936',
    );
  });

  test('extracts STM32F767 unique ID from split CubeProgrammer rows', () {
    const output = '''
0x1FF0F420 : 00290031
0x1FF0F424 : 3334510B
0x1FF0F428 : 38313936
''';

    expect(
      extractUniqueIdFromCubeProgrammerOutput(output),
      '002900313334510B38313936',
    );
  });
}
