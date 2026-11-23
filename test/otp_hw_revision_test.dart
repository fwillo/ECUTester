import 'dart:io';
import 'dart:typed_data';

import 'package:ecutester/initial_programming.dart';
import 'package:ecutester/otp_hw_revision.dart';
import 'package:flutter_test/flutter_test.dart';

// Reference data produced by fw-custom-hellenbremen/bin/make_hw_rev_otp.py:
// build_block('Rev 1.14', (1, 16, 0), 'WEYT', 1795442400)
const _rev114BlockHex =
    '445048570152657620312e3134000000000000000001100057455954e046046b'
    '00000000000000000000000000000000000000000000000000000000e82cdf02';

// 2026-11-23 14:00:00 UTC
final _programmedAt = DateTime.fromMillisecondsSinceEpoch(
  1795442400 * 1000,
  isUtc: true,
);

// Block 0 is an older block (new fields still 0x00), block 2 a new one.
const _referenceStatus = '''OTP block  address     lock    content
   0       0x1FF0F000  locked  valid 'Rev 1.14'
   1       0x1FF0F040  locked  INVALID: CRC mismatch: stored 0x3AE23154, computed 0xC5E23154
       0x1FF0F040  44 50 48 57 01 52 65 76 20 31 2e 32 32 00 00 00  DPHW.Rev 1.22...
       0x1FF0F050  00 00 00 00 00 01 10 00 57 45 59 54 e0 46 04 6b  ........WEYT.F.k
       0x1FF0F060  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
       0x1FF0F070  00 00 00 00 00 00 00 00 00 00 00 00 54 31 e2 3a  ............T1.:
   2       0x1FF0F080  locked  valid 'Rev 1.15', OpenBLT 1.16.0, WEYT, 2026-11-23 14:00:00 UTC
   3       0x1FF0F0C0  locked  erased
   4       0x1FF0F100  -       INVALID: magic is 00 01 02 03, expected 44 50 48 57 ('DPHW')
       0x1FF0F100  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................
       0x1FF0F110  10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f  ................
       0x1FF0F120  20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f   !"#\$%&'()*+,-./
       0x1FF0F130  30 31 32 33 34 35 36 37 38 39 3a 3b 3c 3d 3e 3f  0123456789:;<=>?
   5       0x1FF0F140  -       erased
   6       0x1FF0F180  -       erased
   7       0x1FF0F1C0  -       erased
   8       0x1FF0F200  -       erased
   9       0x1FF0F240  -       erased
  10       0x1FF0F280  -       erased
  11       0x1FF0F2C0  -       erased
  12       0x1FF0F300  -       erased
  13       0x1FF0F340  -       erased
  14       0x1FF0F380  -       erased
  15       0x1FF0F3C0  -       erased
Firmware shows: 'Rev 1.15' (block 2)''';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _newBlock(String revision) => buildOtpBlock(
  revision,
  openBltVersion: [1, 16, 0],
  manufacturer: 'WEYT',
  programmedAt: _programmedAt,
);

Uint8List _referenceDump() {
  final dump = Uint8List(otpSize)..fillRange(0, otpSize, 0xFF);
  dump.setAll(
    0,
    buildOtpBlock(
      'Rev 1.14',
      openBltVersion: [0, 0, 0],
      manufacturer: '',
      programmedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
  );
  final corrupt = _newBlock('Rev 1.22');
  corrupt[63] ^= 0xFF;
  dump.setAll(64, corrupt);
  dump.setAll(128, _newBlock('Rev 1.15'));
  dump.setAll(256, List.generate(64, (i) => i));
  for (var i = 0; i < 4; i++) {
    dump[otpLockOffset + i] = 0;
  }
  return dump;
}

/// Simulates STM32_Programmer_CLI on an OTP area: -u dumps it to a file,
/// -w ANDs a file into it (OTP bits can only go from 1 to 0).
class _FakeCli {
  _FakeCli(this.otp);

  final Uint8List otp;
  final commands = <List<String>>[];

  /// Drops one bit of every data block write, like a bad OTP cell.
  bool corruptWrites = false;

  Future<ProcessResult> call(
    String executable,
    List<String> args, [
    OutputCallback? onOutput,
  ]) async {
    commands.add(args);
    final u = args.indexOf('-u');
    if (u >= 0) {
      await File(args[u + 3]).writeAsBytes(otp);
      return ProcessResult(0, 0, 'Upload done', '');
    }
    final w = args.indexOf('-w');
    if (w >= 0) {
      final data = await File(args[w + 1]).readAsBytes();
      final offset = int.parse(args[w + 2].substring(2), radix: 16) - otpBase;
      for (var i = 0; i < data.length; i++) {
        otp[offset + i] &= data[i];
      }
      if (corruptWrites && offset < otpLockOffset) otp[offset + 6] &= 0xFE;
      return ProcessResult(0, 0, 'Download verified successfully', '');
    }
    return ProcessResult(0, 1, '', 'Error: unexpected command');
  }
}

void main() {
  test('builds the same block as make_hw_rev_otp.py', () {
    expect(_hex(_newBlock('Rev 1.14')), _rev114BlockHex);
  });

  test('stores the date as Unix time regardless of the time zone', () {
    final local = _programmedAt.toLocal();
    expect(
      _hex(_newBlock('Rev 1.14')),
      _hex(
        buildOtpBlock(
          'Rev 1.14',
          openBltVersion: [1, 16, 0],
          manufacturer: 'WEYT',
          programmedAt: local,
        ),
      ),
    );
  });

  test('decodes the new fields and leaves older blocks empty', () {
    final state = OtpState(_referenceDump());
    final block = state.status(2);
    expect(block.openBltVersion, '1.16.0');
    expect(block.manufacturer, 'WEYT');
    expect(block.programmedAt, _programmedAt);
    expect(state.status(0).extrasText, isEmpty);
  });

  test('validates the OpenBLT version', () {
    expect(parseOpenBltVersion('1.16.0'), [1, 16, 0]);
    expect(validateOpenBltVersion('255.255.255'), isNull);
    expect(validateOpenBltVersion('1.256.0'), contains('1.16.0'));
    expect(validateOpenBltVersion('1.16'), isNotNull);
    expect(validateOpenBltVersion('1.16.0.1'), isNotNull);
    expect(validateOpenBltVersion('1.-1.0'), isNotNull);
    expect(validateOpenBltVersion(''), isNotNull);
  });

  test('status text matches make_hw_rev_otp.py --status', () {
    final state = OtpState(_referenceDump());
    expect(state.toText(), _referenceStatus);
    expect(state.nextFreeBlock, 5);
    expect(state.effective, (index: 2, revision: 'Rev 1.15'));
  });

  test('validates the HW revision string', () {
    expect(validateHwRevision('Rev 1.14'), isNull);
    expect(validateHwRevision(''), contains('Rev 1.14'));
    expect(validateHwRevision('   '), contains('Rev 1.14'));
    expect(validateHwRevision('x' * 17), isNotNull);
    expect(validateHwRevision('Rev ä'), isNotNull);
  });

  test('writes, verifies and locks the next free block', () async {
    final cli = _FakeCli(_referenceDump());
    final programmer = OtpProgrammer(
      executablePath: 'STM32_Programmer_CLI',
      interface: DebugInterface.swd,
      runProcess: cli.call,
    );

    final result = await programmer.programHwRevision(
      'Rev 1.16',
      openBltVersion: '1.16.0',
      programmedAt: _programmedAt,
    );

    expect(result.action, OtpWriteAction.written);
    expect(result.blockIndex, 5);
    expect(result.finalState.effective, (index: 5, revision: 'Rev 1.16'));
    expect(result.finalState.block(5), _newBlock('Rev 1.16'));
    expect(result.finalState.isLocked(5), isTrue);
    expect(result.finalState.isLocked(4), isFalse);
    expect(cli.commands.first.take(3), ['-c', 'port=SWD', 'mode=UR']);
  });

  test(
    'does nothing when revision, OpenBLT version and manufacturer match',
    () async {
      final cli = _FakeCli(_referenceDump());
      final programmer = OtpProgrammer(
        executablePath: 'STM32_Programmer_CLI',
        interface: DebugInterface.swd,
        runProcess: cli.call,
      );

      // A later date alone does not cause a new block.
      final result = await programmer.programHwRevision(
        'Rev 1.15',
        openBltVersion: '1.16.0',
        programmedAt: _programmedAt.add(const Duration(days: 3)),
      );

      expect(result.action, OtpWriteAction.alreadyPresent);
      expect(result.blockIndex, 2);
      expect(cli.commands, hasLength(1));
    },
  );

  test('writes a new block when only the OpenBLT version differs', () async {
    final cli = _FakeCli(_referenceDump());
    final programmer = OtpProgrammer(
      executablePath: 'STM32_Programmer_CLI',
      interface: DebugInterface.swd,
      runProcess: cli.call,
    );

    final result = await programmer.programHwRevision(
      'Rev 1.15',
      openBltVersion: '1.17.0',
    );

    expect(result.action, OtpWriteAction.written);
    expect(result.blockIndex, 5);
    expect(result.finalState.status(5).openBltVersion, '1.17.0');
  });

  test('stops before locking when the read-back does not match', () async {
    final cli = _FakeCli(_referenceDump())..corruptWrites = true;
    final programmer = OtpProgrammer(
      executablePath: 'STM32_Programmer_CLI',
      interface: DebugInterface.swd,
      runProcess: cli.call,
    );

    await expectLater(
      programmer.programHwRevision('Rev 1.16', openBltVersion: '1.16.0'),
      throwsA(isA<OtpException>()),
    );
    expect(OtpState(cli.otp).isLocked(5), isFalse);
  });
}
