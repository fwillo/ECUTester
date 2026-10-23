import 'dart:io';

import 'package:ecutester/programming_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves and loads firmware and calibration paths', () async {
    final temp = await Directory.systemTemp.createTemp('ecutester_settings_');
    addTearDown(() => temp.delete(recursive: true));

    final store = ProgrammingSettingsStore(
      file: File('${temp.path}/nested/settings.json'),
    );

    final empty = await store.load();
    expect(empty.firmwarePath, '');
    expect(empty.calibrationPath, '');

    await store.save(
      const ProgrammingSettings(
        firmwarePath: '/tmp/firmware.bin',
        calibrationPath: '/tmp/calibration page 1.bin',
      ),
    );

    final loaded = await store.load();
    expect(loaded.firmwarePath, '/tmp/firmware.bin');
    expect(loaded.calibrationPath, '/tmp/calibration page 1.bin');
  });

  test('falls back to empty paths for a corrupt settings file', () async {
    final temp = await Directory.systemTemp.createTemp('ecutester_settings_');
    addTearDown(() => temp.delete(recursive: true));

    final file = File('${temp.path}/settings.json');
    await file.writeAsString('{not json');

    final loaded = await ProgrammingSettingsStore(file: file).load();
    expect(loaded.firmwarePath, '');
    expect(loaded.calibrationPath, '');
  });
}
