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
        coolantC: 66.8,
        mapKpa: 45.6,
        acceleratorPedalPercent: 13.7,
        vBatt: 12,
        jssStateRaw: 0,
        iatC: 5.5,
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
    expect(
      csv,
      contains(
        'frame,rpm,clt_c,map_kpa,accelerator_pedal_percent,vbatt_v,jss_state,iat_c',
      ),
    );
    expect(
      csv,
      contains('1,1000.0000,66.8000,45.6000,13.7000,12.0000,0.0000,5.5000'),
    );
  });
}
