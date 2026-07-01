import 'dart:typed_data';

import 'package:crc32_checksum/crc32_checksum.dart';

const int ecuDataOffset = 0;
const int ecuDataLength = 38;
const int ecuResponseStatusLength = 1;
const int ecuResponseBodyLength = ecuResponseStatusLength + ecuDataLength;
const int ecuPacketLengthPrefixLength = 2;
const int ecuPacketCrcLength = 4;
const int ecuResponsePacketLength =
    ecuPacketLengthPrefixLength + ecuResponseBodyLength + ecuPacketCrcLength;
const int ecuFrameTarget = 100;

class EcuProtocol {
  static Uint8List makeDataRequest({
    int offset = ecuDataOffset,
    int length = ecuDataLength,
  }) {
    final command = <int>[0x4f];

    command.addAll(
      Uint8List(2)..buffer.asByteData().setInt16(0, offset, Endian.little),
    );
    command.addAll(
      Uint8List(2)..buffer.asByteData().setInt16(0, length, Endian.little),
    );
    command.addAll(
      Uint8List(4)
        ..buffer.asByteData().setInt32(0, Crc32.calculate(command), Endian.big),
    );

    return Uint8List.fromList([0x00, 0x05, ...command]);
  }

  static EcuFrame parseFrame(Uint8List payload) {
    if (payload.length != ecuDataLength) {
      throw FormatException(
        'Expected exactly $ecuDataLength bytes, got ${payload.length}.',
      );
    }

    final data = ByteData.sublistView(payload);
    return EcuFrame(
      rpm: data.getUint16(4, Endian.little).toDouble(),
      coolantC: data.getInt16(16, Endian.little) * 0.01,
      acceleratorPedalPercent: data.getInt16(26, Endian.little) * 0.01,
      mapKpa: data.getUint16(34, Endian.little) * (1 / 30),
    );
  }

  static EcuResponse extractResponse(Uint8List packet) {
    if (packet.length != ecuResponsePacketLength) {
      throw FormatException(
        'Expected response packet length $ecuResponsePacketLength, got ${packet.length}.',
      );
    }

    final data = ByteData.sublistView(packet);
    final bodyLength = data.getUint16(0, Endian.big);
    if (bodyLength != ecuResponseBodyLength) {
      throw FormatException(
        'Expected response body length $ecuResponseBodyLength, got $bodyLength.',
      );
    }

    final bodyStart = ecuPacketLengthPrefixLength;
    final bodyEnd = bodyStart + bodyLength;
    final body = Uint8List.fromList(packet.sublist(bodyStart, bodyEnd));
    final actualCrc = data.getUint32(bodyEnd, Endian.big);
    final expectedCrc = Crc32.calculate(body);
    if (actualCrc != expectedCrc) {
      throw FormatException(
        'Response CRC mismatch: expected 0x${expectedCrc.toRadixString(16).padLeft(8, '0')}, '
        'got 0x${actualCrc.toRadixString(16).padLeft(8, '0')}.',
      );
    }

    return EcuResponse(
      status: body.first,
      payload: Uint8List.fromList(body.sublist(ecuResponseStatusLength)),
      crc: actualCrc,
    );
  }
}

class EcuResponse {
  const EcuResponse({
    required this.status,
    required this.payload,
    required this.crc,
  });

  final int status;
  final Uint8List payload;
  final int crc;
}

class EcuFrame {
  const EcuFrame({
    required this.rpm,
    required this.coolantC,
    required this.mapKpa,
    required this.acceleratorPedalPercent,
  });

  final double rpm;
  final double coolantC;
  final double mapKpa;
  final double acceleratorPedalPercent;

  double valueFor(EcuMetric metric) {
    return switch (metric) {
      EcuMetric.rpm => rpm,
      EcuMetric.coolant => coolantC,
      EcuMetric.map => mapKpa,
      EcuMetric.acceleratorPedal => acceleratorPedalPercent,
    };
  }

  String toDebugString() {
    return [
      'RPM=${rpm.toStringAsFixed(0)}',
      'CLT=${coolantC.toStringAsFixed(2)} C',
      'MAP=${mapKpa.toStringAsFixed(2)} kPa',
      'Pedal=${acceleratorPedalPercent.toStringAsFixed(2)} %',
    ].join(', ');
  }
}

enum EcuMetric {
  rpm('RPM', 'RPM', 990, 1010, 0),
  coolant('CLT', 'C', 66.0, 67.5, 1),
  map('MAP', 'kPa', 39.5, 40.5, 1),
  acceleratorPedal('Accelerator Pedal', '%', 11, 13, 1);

  const EcuMetric(this.label, this.unit, this.min, this.max, this.decimals);

  final String label;
  final String unit;
  final double min;
  final double max;
  final int decimals;

  String format(double value) {
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  String get rangeLabel {
    return '${min.toStringAsFixed(decimals)}-${max.toStringAsFixed(decimals)} $unit';
  }
}

class TestResult {
  const TestResult({
    required this.frames,
    required this.averages,
    required this.failureReasons,
  });

  factory TestResult.fromFrames(List<EcuFrame> frames) {
    if (frames.isEmpty) {
      return const TestResult(
        frames: [],
        averages: {},
        failureReasons: ['No frames were collected.'],
      );
    }

    final averages = <EcuMetric, double>{};
    for (final metric in EcuMetric.values) {
      final sum = frames.fold<double>(
        0,
        (total, frame) => total + frame.valueFor(metric),
      );
      averages[metric] = sum / frames.length;
    }

    final failureReasons = <String>[];
    for (final metric in EcuMetric.values) {
      final average = averages[metric]!;
      if (average < metric.min || average > metric.max) {
        failureReasons.add(
          '${metric.label} average ${metric.format(average)} outside ${metric.rangeLabel}',
        );
      }
    }

    return TestResult(
      frames: List.unmodifiable(frames),
      averages: Map.unmodifiable(averages),
      failureReasons: List.unmodifiable(failureReasons),
    );
  }

  final List<EcuFrame> frames;
  final Map<EcuMetric, double> averages;
  final List<String> failureReasons;

  bool get passed => failureReasons.isEmpty;
}
