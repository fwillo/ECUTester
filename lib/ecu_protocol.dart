import 'dart:typed_data';

import 'package:crc32_checksum/crc32_checksum.dart';

const int ecuDataOffset = 0;
const int ecuDataLength = 1397;
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
      iatC: data.getInt16(18, Endian.little) * 0.01,
      acceleratorPedalPercent: data.getInt16(26, Endian.little) * 0.01,
      mapKpa: data.getUint16(34, Endian.little) * (1 / 30),
      vBatt: data.getUint16(40, Endian.little) * 0.001,
      jssStateRaw: data.getInt8(1396),
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
    required this.vBatt,
    required this.jssStateRaw,
    required this.iatC,
  });

  final double rpm;
  final double coolantC;
  final double mapKpa;
  final double acceleratorPedalPercent;
  final double vBatt;
  final int jssStateRaw;
  final double iatC;

  double valueFor(EcuMetric metric) {
    return switch (metric) {
      EcuMetric.rpm => rpm,
      EcuMetric.coolant => coolantC,
      EcuMetric.map => mapKpa,
      EcuMetric.acceleratorPedal => acceleratorPedalPercent,
      EcuMetric.vBatt => vBatt,
      EcuMetric.jssState => jssStateRaw.toDouble(),
      EcuMetric.iat => iatC,
    };
  }

  String toDebugString() {
    return [
      'RPM=${rpm.toStringAsFixed(0)}',
      'CLT=${coolantC.toStringAsFixed(2)} C',
      'MAP=${mapKpa.toStringAsFixed(2)} kPa',
      'Pedal=${acceleratorPedalPercent.toStringAsFixed(2)} %',
      'VBatt=${vBatt.toStringAsFixed(3)} V',
      'JSS=${jssStateRaw.toDouble().toStringAsFixed(2)}',
      'IAT=${iatC.toStringAsFixed(2)} C',
    ].join(', ');
  }
}

enum EcuMetric {
  rpm('RPM', 'RPM', 990, 1010, 0),
  coolant('CLT', 'C', 66.6, 67.0, 1),
  map('MAP', 'kPa', 45.4, 45.8, 1),
  acceleratorPedal('Accelerator Pedal', '%', 13.5, 13.9, 1),
  vBatt('VBatt', 'V', 11, 13, 2, minInclusive: false, maxInclusive: false),
  jssState('JSS State', '', 0, 0, 2),
  iat('IAT', 'C', 5, 6, 1, minInclusive: false, maxInclusive: false);

  const EcuMetric(
    this.label,
    this.unit,
    this.min,
    this.max,
    this.decimals, {
    this.minInclusive = true,
    this.maxInclusive = true,
  });

  final String label;
  final String unit;
  final double min;
  final double max;
  final int decimals;
  final bool minInclusive;
  final bool maxInclusive;

  bool isPassing(double value) {
    final aboveMin = minInclusive ? value >= min : value > min;
    final belowMax = maxInclusive ? value <= max : value < max;
    return aboveMin && belowMax;
  }

  String format(double value) {
    final formatted = value.toStringAsFixed(decimals);
    return unit.isEmpty ? formatted : '$formatted $unit';
  }

  String get rangeLabel {
    final minOperator = minInclusive ? '>=' : '>';
    final maxOperator = maxInclusive ? '<=' : '<';
    final formatted =
        '$minOperator ${min.toStringAsFixed(decimals)} and '
        '$maxOperator ${max.toStringAsFixed(decimals)}';
    return unit.isEmpty ? formatted : '$formatted $unit';
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
      if (!metric.isPassing(average)) {
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
