import 'dart:io';

import 'otp_hw_revision.dart';

const int stm32f767UniqueIdAddress = 0x1FF0F420;
const int stm32UniqueIdByteLength = 12;
const int calibrationPrimaryAddress = 0x08100000;
const int calibrationBackupAddress = 0x08140000;
const int calibrationSectorSize = 0x40000;

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
    required this.calibrationPath,
    required this.interface,
    required this.flashAddress,
    required this.hwRevision,
    required this.openBltVersion,
    this.skipHwRevision = false,
  });

  final String executablePath;
  final String firmwarePath;
  final String calibrationPath;
  final DebugInterface interface;
  final String flashAddress;

  /// Written to the first free OTP block after programming and verification,
  /// together with [openBltVersion], the manufacturer and the current date.
  final String hwRevision;

  /// "MAJOR.MINOR.PATCH", e.g. "1.16.0".
  final String openBltVersion;

  /// Skips the OTP write entirely (no validation, nothing written).
  final bool skipHwRevision;
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
    this.hwRevision = '',
    this.openBltVersion = '',
    this.hwRevisionSkipped = false,
    this.otpTranscript = '',
    this.otpResult,
    this.otpError,
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
  final String hwRevision;
  final String openBltVersion;
  final bool hwRevisionSkipped;
  final String otpTranscript;
  final OtpWriteResult? otpResult;
  final String? otpError;

  bool get flashSucceeded => exitCode == 0;
  bool get succeeded => flashSucceeded && otpError == null;
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

  /// Runs UID read, programming and the OTP step. CLI output is forwarded
  /// to [onOutput] while the commands run.
  Future<ProgrammingResult> program(
    ProgrammingRequest request, {
    OutputCallback? onOutput,
  }) async {
    void emit(String text) => onOutput?.call(text);

    final executablePath = request.executablePath.trim();
    final firmwarePath = request.firmwarePath.trim();
    final calibrationPath = request.calibrationPath.trim();
    final flashAddress = request.flashAddress.trim();

    if (executablePath.isEmpty) {
      throw const FormatException('Select the STM32CubeProgrammer CLI path.');
    }
    if (firmwarePath.isEmpty) {
      throw const FormatException('Select the initial firmware binary path.');
    }
    if (calibrationPath.isEmpty) {
      throw const FormatException(
        'Select the default calibration binary path.',
      );
    }
    if (flashAddress.isEmpty) {
      throw const FormatException('Enter a flash address.');
    }
    if (!RegExp(r'^0x[0-9A-Fa-f]+$').hasMatch(flashAddress)) {
      throw const FormatException('Flash address must look like 0x08000000.');
    }
    final otpInputError = request.skipHwRevision
        ? null
        : validateHwRevision(request.hwRevision) ??
              validateOpenBltVersion(request.openBltVersion);
    if (otpInputError != null) {
      throw FormatException(otpInputError);
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

    final calibration = File(calibrationPath);
    if (!await calibration.exists()) {
      throw FormatException('Calibration binary not found: $calibrationPath');
    }

    validateFlashLayout(
      firmwareAddress: int.parse(flashAddress.substring(2), radix: 16),
      firmwareLength: await firmware.length(),
      calibrationLength: await calibration.length(),
    );

    final startedAt = DateTime.now();
    final uidReadArguments = buildUniqueIdReadArguments(request);
    final uidReadCommandLine = formatCommand(executablePath, uidReadArguments);
    emit('$uidReadCommandLine\n\n');
    final uidReadProcessResult = await runStreamingProcess(
      executablePath,
      uidReadArguments,
      onOutput,
    );
    final uidReadStdout = stripAnsiEscapeCodes(
      uidReadProcessResult.stdout.toString(),
    );
    final uidReadStderr = stripAnsiEscapeCodes(
      uidReadProcessResult.stderr.toString(),
    );
    final deviceId = extractUniqueIdFromCubeProgrammerOutput(uidReadStdout);
    if (uidReadProcessResult.exitCode != 0 || deviceId == null) {
      throw UniqueIdReadException(
        commandLine: uidReadCommandLine,
        exitCode: uidReadProcessResult.exitCode,
        stdout: uidReadStdout,
        stderr: uidReadStderr,
      );
    }

    emit('\nDevice ID: $deviceId\n\n');

    final arguments = buildArguments(request);
    final commandLine = formatCommand(executablePath, arguments);
    emit('$commandLine\n\n');
    final result = await runStreamingProcess(
      executablePath,
      arguments,
      onOutput,
    );

    // Only after programming and verification succeeded: write the hardware
    // revision to OTP.
    OtpWriteResult? otpResult;
    String? otpError;
    var otpTranscript = '';
    if (result.exitCode == 0 && request.skipHwRevision) {
      emit('\n--- HW revision OTP ---\n\nSkipped: disabled by the user.\n');
    } else if (result.exitCode == 0) {
      emit('\n--- HW revision OTP ---\n\n');
      final otp = OtpProgrammer(
        executablePath: executablePath,
        interface: request.interface,
        onOutput: onOutput,
      );
      try {
        otpResult = await otp.programHwRevision(
          request.hwRevision,
          openBltVersion: request.openBltVersion,
        );
      } catch (error) {
        otpError = error.toString();
        emit('\nOTP error: $otpError\n');
      }
      otpTranscript = otp.transcript;
    }

    return ProgrammingResult(
      deviceId: deviceId,
      startedAt: startedAt,
      completedAt: DateTime.now(),
      uidReadCommandLine: uidReadCommandLine,
      uidReadExitCode: uidReadProcessResult.exitCode,
      uidReadStdout: uidReadStdout,
      uidReadStderr: uidReadStderr,
      commandLine: commandLine,
      exitCode: result.exitCode,
      stdout: stripAnsiEscapeCodes(result.stdout.toString()),
      stderr: stripAnsiEscapeCodes(result.stderr.toString()),
      hwRevision: request.skipHwRevision ? '' : request.hwRevision,
      openBltVersion: request.skipHwRevision ? '' : request.openBltVersion,
      hwRevisionSkipped: request.skipHwRevision,
      otpTranscript: otpTranscript,
      otpResult: otpResult,
      otpError: otpError,
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
      '-w',
      request.calibrationPath.trim(),
      _hexAddress(calibrationPrimaryAddress),
      '-v',
      '-w',
      request.calibrationPath.trim(),
      _hexAddress(calibrationBackupAddress),
      '-v',
      '-rst',
    ];
  }

  static void validateFlashLayout({
    required int firmwareAddress,
    required int firmwareLength,
    required int calibrationLength,
  }) {
    if (firmwareLength == 0) {
      throw const FormatException('Firmware binary is empty.');
    }
    if (calibrationLength == 0) {
      throw const FormatException('Calibration binary is empty.');
    }
    if (calibrationLength > calibrationSectorSize) {
      throw FormatException(
        'Calibration binary is $calibrationLength bytes, but a calibration '
        'sector holds only $calibrationSectorSize bytes.',
      );
    }

    final firmwareEnd = firmwareAddress + firmwareLength;
    final calibrationEnd = calibrationBackupAddress + calibrationSectorSize;
    if (firmwareAddress < calibrationEnd &&
        firmwareEnd > calibrationPrimaryAddress) {
      throw FormatException(
        'Firmware ${_hexAddress(firmwareAddress)}-${_hexAddress(firmwareEnd - 1)} '
        'overlaps the calibration sectors '
        '${_hexAddress(calibrationPrimaryAddress)}-${_hexAddress(calibrationEnd - 1)}.',
      );
    }
  }

  static List<String> buildUniqueIdReadArguments(ProgrammingRequest request) {
    return [
      '-c',
      'port=${request.interface.cliValue}',
      'mode=UR',
      '-r32',
      _hexAddress(stm32f767UniqueIdAddress),
      stm32UniqueIdByteLength.toString(),
    ];
  }

  static String defaultExecutablePath() {
    if (Platform.isMacOS) {
      return '/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/Resources/bin/STM32_Programmer_CLI';
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

final _ansiEscape = RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])');

String stripAnsiEscapeCodes(String value) {
  return value.replaceAll(_ansiEscape, '');
}

typedef OutputCallback = void Function(String text);

/// Like [Process.run], but forwards stdout and stderr to [onOutput] while
/// the process runs (with ANSI escape codes removed).
Future<ProcessResult> runStreamingProcess(
  String executable,
  List<String> arguments, [
  OutputCallback? onOutput,
]) async {
  final process = await Process.start(executable, arguments);
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutChunker = _AnsiChunker();
  final stderrChunker = _AnsiChunker();

  void forward(String text) {
    if (text.isNotEmpty) onOutput?.call(text);
  }

  final stdoutDone = process.stdout.transform(systemEncoding.decoder).forEach((
    chunk,
  ) {
    stdoutBuffer.write(chunk);
    forward(stdoutChunker.add(chunk));
  });
  final stderrDone = process.stderr.transform(systemEncoding.decoder).forEach((
    chunk,
  ) {
    stderrBuffer.write(chunk);
    forward(stderrChunker.add(chunk));
  });

  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  forward(stdoutChunker.flush());
  forward(stderrChunker.flush());

  return ProcessResult(
    process.pid,
    exitCode,
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}

/// Strips ANSI escape codes from a chunked stream, holding back an escape
/// sequence that is split across two chunks.
class _AnsiChunker {
  var _pending = '';

  String add(String chunk) {
    var text = _pending + chunk;
    _pending = '';
    final escape = text.lastIndexOf('\x1B');
    if (escape >= 0) {
      final tail = text.substring(escape);
      if (tail.length < 32 && _ansiEscape.matchAsPrefix(tail) == null) {
        _pending = tail;
        text = text.substring(0, escape);
      }
    }
    return stripAnsiEscapeCodes(text);
  }

  String flush() {
    final text = stripAnsiEscapeCodes(_pending);
    _pending = '';
    return text;
  }
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

String _hexAddress(int address) {
  return '0x${address.toRadixString(16).toUpperCase().padLeft(8, '0')}';
}

String _shellQuote(String value) {
  if (value.isEmpty) return "''";
  if (!RegExp(r'''[\s'"\\]''').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}
