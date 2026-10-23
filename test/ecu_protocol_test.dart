import 'dart:typed_data';

import 'package:crc32_checksum/crc32_checksum.dart';
import 'package:ecutester/ecu_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the output-channel data request', () {
    final request = EcuProtocol.makeDataRequest();

    expect(request.length, 11);
    expect(request.sublist(0, 7), [0x00, 0x05, 0x4f, 0x00, 0x00, 0x75, 0x05]);

    final crc = ByteData.sublistView(request).getUint32(7, Endian.big);
    expect(crc, Crc32.calculate(request.sublist(2, 7)));
  });

  test('parses the selected output-channel fields', () {
    final payload = Uint8List(ecuDataLength);
    ByteData.sublistView(payload)
      ..setUint16(4, 1050, Endian.little)
      ..setInt16(16, 6500, Endian.little)
      ..setInt16(18, 550, Endian.little)
      ..setInt16(26, 3500, Endian.little)
      ..setUint16(34, 1800, Endian.little)
      ..setUint16(40, 12250, Endian.little);

    final frame = EcuProtocol.parseFrame(payload);

    expect(frame.rpm, 1050);
    expect(frame.coolantC, 65);
    expect(frame.acceleratorPedalPercent, 35);
    expect(frame.mapKpa, 60);
    expect(frame.vBatt, 12.25);
    expect(frame.iatC, 5.5);
  });

  test('extracts a logged response packet', () {
    final body = Uint8List(ecuResponseBodyLength);
    body[0] = 0;
    body.setRange(1, body.length, Uint8List(ecuDataLength));
    final crc = Crc32.calculate(body);
    final packet = _responsePacket(body, crc);

    final response = EcuProtocol.extractResponse(packet);

    expect(response.status, 0);
    expect(response.payload.length, ecuDataLength);
    expect(response.crc, crc);
  });

  test('summarizes passing and failing averages', () {
    final passFrames = List.generate(
      ecuFrameTarget,
      (_) => const EcuFrame(
        rpm: 1000,
        coolantC: 66.8,
        mapKpa: 45.6,
        acceleratorPedalPercent: 13.7,
        vBatt: 12,
        iatC: 5.5,
      ),
    );

    expect(TestResult.fromFrames(passFrames).passed, isTrue);

    final failFrames = List.generate(
      ecuFrameTarget,
      (_) => const EcuFrame(
        rpm: 900,
        coolantC: 66.8,
        mapKpa: 45.6,
        acceleratorPedalPercent: 13.7,
        vBatt: 12,
        iatC: 5.5,
      ),
    );

    final result = TestResult.fromFrames(failFrames);
    expect(result.passed, isFalse);
    expect(result.failureReasons.single, contains('RPM average 900 RPM'));
  });
}

Uint8List _responsePacket(Uint8List body, int crc) {
  final packet = Uint8List(ecuResponsePacketLength);
  final data = ByteData.sublistView(packet);
  data.setUint16(0, body.length, Endian.big);
  packet.setRange(
    ecuPacketLengthPrefixLength,
    ecuPacketLengthPrefixLength + body.length,
    body,
  );
  data.setUint32(ecuPacketLengthPrefixLength + body.length, crc, Endian.big);
  return packet;
}
