import 'dart:io';

enum DebugInterface {
  swd('SWD'),
  jtag('JTAG');

  const DebugInterface(this.cliValue);

  final String cliValue;
}

class ProgrammingRequest {
  const ProgrammingRequest({
    required this.executablePath,
    required this.firmwarePath,
    required this.interface,
    required this.flashAddress,
  });

  final String executablePath;
  final String firmwarePath;
  final DebugInterface interface;
  final String flashAddress;
}

class ProgrammingResult {
  const ProgrammingResult({
    required this.commandLine,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String commandLine;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

class Stm32CubeProgrammer {
  const Stm32CubeProgrammer();

  Future<ProgrammingResult> program(ProgrammingRequest request) async {
    final executablePath = request.executablePath.trim();
    final firmwarePath = request.firmwarePath.trim();
    final flashAddress = request.flashAddress.trim();

    if (executablePath.isEmpty) {
      throw const FormatException('Select the STM32CubeProgrammer CLI path.');
    }
    if (firmwarePath.isEmpty) {
      throw const FormatException('Select the initial firmware binary path.');
    }
    if (flashAddress.isEmpty) {
      throw const FormatException('Enter a flash address.');
    }
    if (!RegExp(r'^0x[0-9A-Fa-f]+$').hasMatch(flashAddress)) {
      throw const FormatException('Flash address must look like 0x08000000.');
    }

    final executable = File(executablePath);
    if (!await executable.exists()) {
      throw FormatException(
        'STM32CubeProgrammer CLI not found: $executablePath',
      );
    }

    final firmware = File(firmwarePath);
    if (!await firmware.exists()) {
      throw FormatException('Firmware binary not found: $firmwarePath');
    }

    final arguments = buildArguments(request);
    final result = await Process.run(executablePath, arguments);

    return ProgrammingResult(
      commandLine: formatCommand(executablePath, arguments),
      exitCode: result.exitCode,
      stdout: stripAnsiEscapeCodes(result.stdout.toString()),
      stderr: stripAnsiEscapeCodes(result.stderr.toString()),
    );
  }

  static List<String> buildArguments(ProgrammingRequest request) {
    return [
      '-c',
      'port=${request.interface.cliValue}',
      'mode=UR',
      '-w',
      request.firmwarePath.trim(),
      request.flashAddress.trim(),
      '-v',
      '-rst',
    ];
  }

  static String defaultExecutablePath() {
    if (Platform.isMacOS) {
      return '/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI';
    }
    if (Platform.isWindows) {
      return r'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe';
    }
    return '/opt/st/stm32cubeprogrammer/bin/STM32_Programmer_CLI';
  }

  static String formatCommand(String executablePath, List<String> arguments) {
    return [
      _shellQuote(executablePath),
      ...arguments.map(_shellQuote),
    ].join(' ');
  }
}

String stripAnsiEscapeCodes(String value) {
  return value.replaceAll(RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])'), '');
}

String _shellQuote(String value) {
  if (value.isEmpty) return "''";
  if (!RegExp(r'''[\s'"\\]''').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}
