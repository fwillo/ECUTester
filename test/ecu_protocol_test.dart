import 'dart:typed_data';

import 'package:crc32_checksum/crc32_checksum.dart';
import 'package:ecutester/ecu_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the output-channel data request', () {
    final request = EcuProtocol.makeDataRequest();

    expect(request.length, 11);
    expect(request.sublist(0, 7), [0x00, 0x05, 0x4f, 0x00, 0x00, 0x26, 0x00]);

    final crc = ByteData.sublistView(request).getUint32(7, Endian.big);
    expect(crc, Crc32.calculate(request.sublist(2, 7)));
  });

  test('parses the selected output-channel fields', () {
    final payload = Uint8List(ecuDataLength);
    ByteData.sublistView(payload)
      ..setUint16(4, 1050, Endian.little)
      ..setInt16(16, 6500, Endian.little)
      ..setInt16(26, 3500, Endian.little)
      ..setUint16(34, 1800, Endian.little);

    final frame = EcuProtocol.parseFrame(payload);

    expect(frame.rpm, 1050);
    expect(frame.coolantC, 65);
    expect(frame.acceleratorPedalPercent, 35);
    expect(frame.mapKpa, 60);
  });

  test('extracts a logged response packet', () {
    final packet = Uint8List.fromList([
      0x00,
      0x27,
      0x00,
      0x00,
      0x00,
      0x21,
      0x02,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x22,
      0x00,
      0xE8,
      0x0C,
      0xC9,
      0x0C,
      0xB1,
      0xFF,
      0xBB,
      0xF4,
      0xB1,
      0xFF,
      0xD5,
      0xF6,
      0x77,
      0x13,
      0x00,
      0x00,
      0xE5,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x33,
      0x07,
      0x00,
      0x0C,
      0x59,
      0xDF,
      0x84,
      0xC9,
    ]);

    final response = EcuProtocol.extractResponse(packet);

    expect(response.status, 0);
    expect(response.payload.length, ecuDataLength);
    expect(response.crc, 0x59DF84C9);
  });

  test('summarizes passing and failing averages', () {
    final passFrames = List.generate(
      ecuFrameTarget,
      (_) => const EcuFrame(
        rpm: 1000,
        coolantC: 66.5,
        mapKpa: 40,
        acceleratorPedalPercent: 12,
      ),
    );

    expect(TestResult.fromFrames(passFrames).passed, isTrue);

    final failFrames = List.generate(
      ecuFrameTarget,
      (_) => const EcuFrame(
        rpm: 900,
        coolantC: 66.5,
        mapKpa: 40,
        acceleratorPedalPercent: 12,
      ),
    );

    final result = TestResult.fromFrames(failFrames);
    expect(result.passed, isFalse);
    expect(result.failureReasons.single, contains('RPM average 900 RPM'));
  });
}
