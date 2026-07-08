import 'dart:io';

import 'ecu_protocol.dart';

class TestLogDevice {
  const TestLogDevice({
    required this.portName,
    this.description,
    this.manufacturer,
    this.productName,
    this.serialNumber,
    this.vendorId,
    this.productId,
  });

  final String portName;
  final String? description;
  final String? manufacturer;
  final String? productName;
  final String? serialNumber;
  final int? vendorId;
  final int? productId;

  String get displayName {
    final parts = [
      productName,
      manufacturer,
      serialNumber == null ? null : 'SN $serialNumber',
      portName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? portName : parts.join(' | ');
  }

  String get directoryName {
    final stableId = serialNumber?.trim().isNotEmpty == true
        ? serialNumber!.trim()
        : [
            _hexId('vid', vendorId),
            _hexId('pid', productId),
            portName,
          ].whereType<String>().join('_');
    return _sanitizePathSegment(stableId);
  }
}

class SavedTestLog {
  const SavedTestLog({
    required this.file,
    required this.index,
    required this.deviceDirectory,
  });

  final File file;
  final int index;
  final Directory deviceDirectory;
}

class TestLogWriter {
  TestLogWriter({Directory? baseDirectory})
    : baseDirectory = baseDirectory ?? defaultBaseDirectory();

  final Directory baseDirectory;

  static Directory defaultBaseDirectory() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.trim().isEmpty) {
      return Directory('BremerECU Production Tester Logs');
    }
    return Directory('$home/Documents/BremerECU Production Tester Logs');
  }

  Future<SavedTestLog> save({
    required TestLogDevice device,
    required TestResult result,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    final deviceDirectory = Directory(
      '${baseDirectory.path}/${device.directoryName}',
    );
    await deviceDirectory.create(recursive: true);

    final index = await _nextIndex(deviceDirectory);
    final file = File(
      '${deviceDirectory.path}/test_${index.toString().padLeft(4, '0')}.csv',
    );

    await file.writeAsString(
      _buildCsv(
        index: index,
        device: device,
        result: result,
        startedAt: startedAt,
        completedAt: completedAt ?? DateTime.now(),
      ),
      flush: true,
    );

    return SavedTestLog(
      file: file,
      index: index,
      deviceDirectory: deviceDirectory,
    );
  }

  Future<int> _nextIndex(Directory deviceDirectory) async {
    final matcher = RegExp(r'^test_(\d{4})\.csv$');
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

  String _buildCsv({
    required int index,
    required TestLogDevice device,
    required TestResult result,
    required DateTime completedAt,
    DateTime? startedAt,
  }) {
    final buffer = StringBuffer()
      ..writeln('# BremerECU Production Tester')
      ..writeln('# Log index,${_csv(index.toString())}')
      ..writeln('# Started at,${_csv(startedAt?.toIso8601String() ?? '')}')
      ..writeln('# Completed at,${_csv(completedAt.toIso8601String())}')
      ..writeln('# Result,${result.passed ? 'PASS' : 'FAIL'}')
      ..writeln('# Device,${_csv(device.displayName)}')
      ..writeln('# Port,${_csv(device.portName)}')
      ..writeln('# VID,${_csv(_hexId('', device.vendorId) ?? '')}')
      ..writeln('# PID,${_csv(_hexId('', device.productId) ?? '')}')
      ..writeln('# Serial,${_csv(device.serialNumber ?? '')}');

    if (result.failureReasons.isNotEmpty) {
      buffer.writeln(
        '# Failure reasons,${_csv(result.failureReasons.join(' | '))}',
      );
    }

    buffer.writeln('# Averages');
    for (final metric in EcuMetric.values) {
      final average = result.averages[metric];
      buffer.writeln(
        '# ${_csv(metric.label)},${average == null ? '' : average.toStringAsFixed(4)},${_csv(metric.unit)},${_csv(metric.rangeLabel)}',
      );
    }

    buffer.writeln(
      ['frame', ...EcuMetric.values.map(_metricColumnName)].join(','),
    );
    for (var i = 0; i < result.frames.length; i++) {
      final frame = result.frames[i];
      buffer.writeln(
        [
          i + 1,
          for (final metric in EcuMetric.values)
            _metricCsvValue(frame.valueFor(metric), metric),
        ].join(','),
      );
    }

    return buffer.toString();
  }
}

String _metricColumnName(EcuMetric metric) {
  return switch (metric) {
    EcuMetric.rpm => 'rpm',
    EcuMetric.coolant => 'clt_c',
    EcuMetric.map => 'map_kpa',
    EcuMetric.acceleratorPedal => 'accelerator_pedal_percent',
    EcuMetric.vBatt => 'vbatt_v',
    EcuMetric.jssState => 'jss_state',
    EcuMetric.iat => 'iat_c',
  };
}

String _metricCsvValue(double value, EcuMetric metric) {
  return value.toStringAsFixed(4);
}

String? _hexId(String prefix, int? value) {
  if (value == null) return null;
  final hex = value.toRadixString(16).padLeft(4, '0').toUpperCase();
  return prefix.isEmpty ? hex : '${prefix}_$hex';
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
