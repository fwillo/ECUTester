import 'dart:io';

const int stm32f767UniqueIdAddress = 0x1FF0F420;
const int stm32UniqueIdByteLength = 12;

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
    required this.deviceId,
    required this.startedAt,
    required this.completedAt,
    required this.uidReadCommandLine,
    required this.uidReadExitCode,
    required this.uidReadStdout,
    required this.uidReadStderr,
    required this.commandLine,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String deviceId;
  final DateTime startedAt;
  final DateTime completedAt;
  final String uidReadCommandLine;
  final int uidReadExitCode;
  final String uidReadStdout;
  final String uidReadStderr;
  final String commandLine;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

class UniqueIdReadException implements Exception {
  const UniqueIdReadException({
    required this.commandLine,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String commandLine;
  final int exitCode;
  final String stdout;
  final String stderr;

  @override
  String toString() {
    final details = [
      'Unable to read STM32 unique ID before programming.',
      'Command: $commandLine',
      'Exit code: $exitCode',
      if (stdout.trim().isNotEmpty) stdout.trim(),
      if (stderr.trim().isNotEmpty) stderr.trim(),
    ].join('\n');
    return details;
  }
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

    final startedAt = DateTime.now();
    final uidReadArguments = buildUniqueIdReadArguments(request);
    final uidReadProcessResult = await Process.run(
      executablePath,
      uidReadArguments,
    );
    final uidReadStdout = stripAnsiEscapeCodes(
      uidReadProcessResult.stdout.toString(),
    );
    final uidReadStderr = stripAnsiEscapeCodes(
      uidReadProcessResult.stderr.toString(),
    );
    final uidReadCommandLine = formatCommand(executablePath, uidReadArguments);
    final deviceId = extractUniqueIdFromCubeProgrammerOutput(uidReadStdout);
    if (uidReadProcessResult.exitCode != 0 || deviceId == null) {
      throw UniqueIdReadException(
        commandLine: uidReadCommandLine,
        exitCode: uidReadProcessResult.exitCode,
        stdout: uidReadStdout,
        stderr: uidReadStderr,
      );
    }

    final arguments = buildArguments(request);
    final result = await Process.run(executablePath, arguments);

    return ProgrammingResult(
      deviceId: deviceId,
      startedAt: startedAt,
      completedAt: DateTime.now(),
      uidReadCommandLine: uidReadCommandLine,
      uidReadExitCode: uidReadProcessResult.exitCode,
      uidReadStdout: uidReadStdout,
      uidReadStderr: uidReadStderr,
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

  static List<String> buildUniqueIdReadArguments(ProgrammingRequest request) {
    return [
      '-c',
      'port=${request.interface.cliValue}',
      'mode=UR',
      '-r32',
      '0x${stm32f767UniqueIdAddress.toRadixString(16).toUpperCase()}',
      stm32UniqueIdByteLength.toString(),
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

String? extractUniqueIdFromCubeProgrammerOutput(String output) {
  final words = <String>[];

  for (final line in output.split(RegExp(r'\r?\n'))) {
    final rowMatch = RegExp(r'^\s*(?:0x)?([0-9A-Fa-f]{8})\b').firstMatch(line);
    if (rowMatch == null) continue;

    final rowAddress = int.tryParse(rowMatch.group(1)!, radix: 16);
    if (rowAddress == null ||
        rowAddress < stm32f767UniqueIdAddress ||
        rowAddress >= stm32f767UniqueIdAddress + stm32UniqueIdByteLength) {
      continue;
    }

    final dataStart = line.contains(':')
        ? line.split(':').skip(1).join(':')
        : line;
    for (final match in RegExp(
      r'(?:0x)?([0-9A-Fa-f]{8})\b',
    ).allMatches(dataStart)) {
      words.add(match.group(1)!.toUpperCase());
      if (words.length == 3) return words.join();
    }
  }

  return null;
}

String _shellQuote(String value) {
  if (value.isEmpty) return "''";
  if (!RegExp(r'''[\s'"\\]''').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}
