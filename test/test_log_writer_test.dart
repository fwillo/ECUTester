import 'dart:io';

import 'package:ecutester/ecu_protocol.dart';
import 'package:ecutester/test_log_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves iteratively numbered logs per device', () async {
    final temp = await Directory.systemTemp.createTemp('ecutester_logs_');
    addTearDown(() => temp.delete(recursive: true));

    final writer = TestLogWriter(baseDirectory: temp);
    const device = TestLogDevice(
      portName: '/dev/cu.usbmodem-test',
      serialNumber: 'ABC123',
      vendorId: 0x0483,
      productId: 0x5740,
    );
    final result = TestResult.fromFrames([
      const EcuFrame(
        rpm: 1000,
        coolantC: 66.5,
        mapKpa: 40,
        acceleratorPedalPercent: 12,
      ),
    ]);

    final first = await writer.save(device: device, result: result);
    final second = await writer.save(device: device, result: result);

    expect(first.index, 1);
    expect(second.index, 2);
    expect(first.file.path, endsWith('ABC123/test_0001.csv'));
    expect(second.file.path, endsWith('ABC123/test_0002.csv'));
    expect(await first.file.exists(), isTrue);

    final csv = await first.file.readAsString();
    expect(csv, contains('# Result,PASS'));
    expect(csv, contains('frame,rpm,clt_c,map_kpa,accelerator_pedal_percent'));
    expect(csv, contains('1,1000.0000,66.5000,40.0000,12.0000'));
  });
}
