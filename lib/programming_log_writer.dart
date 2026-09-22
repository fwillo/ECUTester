import 'dart:io';

import 'initial_programming.dart';
import 'test_log_writer.dart';

class SavedProgrammingLog {
  const SavedProgrammingLog({
    required this.file,
    required this.index,
    required this.deviceDirectory,
  });

  final File file;
  final int index;
  final Directory deviceDirectory;
}

class ProgrammingLogWriter {
  ProgrammingLogWriter({Directory? baseDirectory})
    : baseDirectory = baseDirectory ?? TestLogWriter.defaultBaseDirectory();

  final Directory baseDirectory;

  Future<SavedProgrammingLog> save(ProgrammingResult result) async {
    final deviceDirectory = Directory(
      '${baseDirectory.path}/${_sanitizePathSegment(result.deviceId)}',
    );
    await deviceDirectory.create(recursive: true);

    final index = await _nextIndex(deviceDirectory);
    final file = File(
      '${deviceDirectory.path}/programming_${index.toString().padLeft(4, '0')}.csv',
    );

    await file.writeAsString(
      _buildCsv(index: index, result: result),
      flush: true,
    );

    return SavedProgrammingLog(
      file: file,
      index: index,
      deviceDirectory: deviceDirectory,
    );
  }

  Future<int> _nextIndex(Directory deviceDirectory) async {
    final matcher = RegExp(r'^programming_(\d{4})\.csv$');
    var highest = 0;

    await for (final entity in deviceDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = matcher.firstMatch(name);
      if (match == null) continue;

      final index = int.tryParse(match.group(1)!);
      if (index != null && index > highest) {
        highest = index;
      }
    }

    return highest + 1;
  }

  String _buildCsv({required int index, required ProgrammingResult result}) {
    final buffer = StringBuffer()
      ..writeln('# BremerECU Production Tester Programming')
      ..writeln('# Log index,${_csv(index.toString())}')
      ..writeln('# Started at,${_csv(result.startedAt.toIso8601String())}')
      ..writeln('# Completed at,${_csv(result.completedAt.toIso8601String())}')
      ..writeln('# Result,${result.succeeded ? 'PASS' : 'FAIL'}')
      ..writeln('# Device ID,${_csv(result.deviceId)}')
      ..writeln('# UID read command,${_csv(result.uidReadCommandLine)}')
      ..writeln(
        '# UID read exit code,${_csv(result.uidReadExitCode.toString())}',
      )
      ..writeln('# Programming command,${_csv(result.commandLine)}')
      ..writeln('# Programming exit code,${_csv(result.exitCode.toString())}')
      ..writeln()
      ..writeln('section,stream,line')
      ..write(_outputRows('uid_read', 'stdout', result.uidReadStdout))
      ..write(_outputRows('uid_read', 'stderr', result.uidReadStderr))
      ..write(_outputRows('programming', 'stdout', result.stdout))
      ..write(_outputRows('programming', 'stderr', result.stderr));
    return buffer.toString();
  }
}

String _outputRows(String section, String stream, String output) {
  final buffer = StringBuffer();
  final lines = output.trimRight().split(RegExp(r'\r?\n'));
  if (lines.length == 1 && lines.single.isEmpty) return '';

  for (final line in lines) {
    buffer.writeln('${_csv(section)},${_csv(stream)},${_csv(line)}');
  }
  return buffer.toString();
}

String _sanitizePathSegment(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? 'unknown_device' : sanitized;
}

String _csv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
