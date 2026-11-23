// Hardware revision in the STM32F767 OTP area.
//
// Port of fw-custom-hellenbremen/bin/make_hw_rev_otp.py. Block layout, must
// match DpecmOtpBlock in the firmware's board_config.cpp:
//   bytes  0..3   magic "DPHW"
//   byte   4      layout version (1)
//   bytes  5..20  hardware revision, printable ASCII, padded with 0x00
//   bytes 21..23  OpenBLT version MAJOR, MINOR, PATCH (uint8 each)
//   bytes 24..27  manufacturer, 4 ASCII characters (always "WEYT")
//   bytes 28..31  programming date, Unix time (uint32, UTC), little-endian
//   bytes 32..59  reserved (0x00)
//   bytes 60..63  CRC32 (zlib) over bytes 0..59, little-endian
//
// Bytes 21..31 were reserved (0x00) in older blocks; the layout version stays
// 1, so older firmware still accepts new blocks. All-zero fields mean "not
// recorded".
//
// The firmware uses the last valid block, so new data is always written
// to the first erased block after the last programmed one, then locked. The
// lock bytes live in a 32-byte chunk at 0x1FF0F400; CubeProgrammer only writes
// the OTP area in 32-byte aligned chunks, so the whole chunk is rewritten from
// the read-back with 0x00 at the block being locked.

import 'dart:io';
import 'dart:typed_data';

import 'initial_programming.dart';

const int otpBase = 0x1FF0F000;
const int otpSize = 0x420;
const int otpLockOffset = 0x400;
const int otpLockBase = otpBase + otpLockOffset;
const int otpLockChunkSize = 32;
const int otpBlockSize = 64;
const int otpBlockCount = 16;
const int otpRevisionSize = 16;
const List<int> otpMagic = [0x44, 0x50, 0x48, 0x57]; // "DPHW"
const int otpLayoutVersion = 1;
const int otpOpenBltOffset = 21;
const int otpManufacturerOffset = 24;
const int otpManufacturerSize = 4;
const int otpDateOffset = 28;

/// Recorded in every new block; there is no input for it.
const String otpManufacturer = 'WEYT';
const String defaultOpenBltVersion = '1.16.0';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, [
      OutputCallback? onOutput,
    ]);

/// Returns an error message, or null if [revision] can be written to OTP.
String? validateHwRevision(String revision) {
  if (revision.trim().isEmpty) {
    return 'Enter a HW revision string, for example "Rev 1.14", or tick '
        '"Skip HW revision OTP write".';
  }
  if (revision.length > otpRevisionSize) {
    return 'HW revision string must be at most $otpRevisionSize characters, '
        'for example "Rev 1.14".';
  }
  if (!revision.codeUnits.every(_isPrintableAscii)) {
    return 'HW revision string may only contain printable ASCII characters.';
  }
  return null;
}

/// Parses "MAJOR.MINOR.PATCH" with each part 0..255, or returns null.
List<int>? parseOpenBltVersion(String text) {
  final parts = text.trim().split('.');
  if (parts.length != 3) return null;
  final values = <int>[];
  for (final part in parts) {
    if (!RegExp(r'^[0-9]{1,3}$').hasMatch(part)) return null;
    final value = int.parse(part);
    if (value > 255) return null;
    values.add(value);
  }
  return values;
}

/// Returns an error message, or null if [version] can be written to OTP.
String? validateOpenBltVersion(String version) {
  if (parseOpenBltVersion(version) != null) return null;
  return 'Enter the OpenBLT version as MAJOR.MINOR.PATCH with each part '
      '0 to 255, for example "$defaultOpenBltVersion".';
}

/// CRC-32 as computed by zlib.crc32.
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Uint8List buildOtpBlock(
  String revision, {
  required List<int> openBltVersion,
  required String manufacturer,
  required DateTime programmedAt,
}) {
  final block = Uint8List(otpBlockSize);
  block.setAll(0, otpMagic);
  block[4] = otpLayoutVersion;
  block.setAll(5, revision.codeUnits);
  block.setAll(otpOpenBltOffset, openBltVersion);
  block.setAll(otpManufacturerOffset, manufacturer.codeUnits);
  final data = ByteData.sublistView(block);
  // Unix time is UTC by definition, whatever the local time zone is.
  data.setUint32(
    otpDateOffset,
    programmedAt.millisecondsSinceEpoch ~/ 1000,
    Endian.little,
  );
  data.setUint32(
    otpBlockSize - 4,
    crc32(block.sublist(0, otpBlockSize - 4)),
    Endian.little,
  );
  return block;
}

/// Validates a block with the same rules as the firmware.
/// Returns the revision on success; otherwise [reason] says why it is invalid.
({String? revision, String? reason}) checkOtpBlock(Uint8List block) {
  ({String? revision, String? reason}) invalid(String reason) =>
      (revision: null, reason: reason);

  final magic = block.sublist(0, 4);
  if (!_bytesEqual(magic, otpMagic)) {
    return invalid(
      "magic is ${_hexBytes(magic)}, expected ${_hexBytes(otpMagic)} ('DPHW')",
    );
  }
  if (block[4] != otpLayoutVersion) {
    return invalid('layout version is ${block[4]}, expected $otpLayoutVersion');
  }
  final stored = ByteData.sublistView(
    block,
  ).getUint32(otpBlockSize - 4, Endian.little);
  final computed = crc32(block.sublist(0, otpBlockSize - 4));
  if (stored != computed) {
    return invalid(
      'CRC mismatch: stored 0x${_hex32(stored)}, computed 0x${_hex32(computed)}',
    );
  }
  var end = 5 + otpRevisionSize;
  while (end > 5 && block[end - 1] == 0) {
    end--;
  }
  final text = block.sublist(5, end);
  if (text.isEmpty) return invalid('revision text is empty');
  if (!text.every(_isPrintableAscii)) {
    return invalid(
      'revision text is not printable ASCII followed by 0x00 padding: '
      '${_hexBytes(text)}',
    );
  }
  return (revision: String.fromCharCodes(text), reason: null);
}

/// Revision, OpenBLT version and manufacturer. A block with the same identity
/// as the one in use is not written again (the date is not compared).
Uint8List otpBlockIdentity(Uint8List block) =>
    Uint8List.sublistView(block, 5, otpDateOffset);

/// OpenBLT version, manufacturer and date of a block; null if not recorded.
({String? openBltVersion, String? manufacturer, DateTime? programmedAt})
decodeOtpExtras(Uint8List block) {
  final version = block.sublist(otpOpenBltOffset, otpOpenBltOffset + 3);
  var end = otpManufacturerOffset + otpManufacturerSize;
  while (end > otpManufacturerOffset && block[end - 1] == 0) {
    end--;
  }
  final manufacturer = block.sublist(otpManufacturerOffset, end);
  final seconds = ByteData.sublistView(
    block,
  ).getUint32(otpDateOffset, Endian.little);
  return (
    openBltVersion: version.every((v) => v == 0) ? null : version.join('.'),
    manufacturer: manufacturer.isEmpty
        ? null
        : String.fromCharCodes(
            manufacturer.map((c) => _isPrintableAscii(c) ? c : 0x2E),
          ),
    programmedAt: seconds == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
  );
}

/// "2026-11-23 14:00:00 UTC"
String formatOtpDate(DateTime date) {
  final utc = date.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)} UTC';
}

enum OtpBlockKind { erased, valid, invalid }

class OtpBlockStatus {
  const OtpBlockStatus({
    required this.index,
    required this.bytes,
    required this.locked,
    required this.kind,
    this.revision,
    this.reason,
    this.openBltVersion,
    this.manufacturer,
    this.programmedAt,
  });

  final int index;
  final Uint8List bytes;
  final bool locked;
  final OtpBlockKind kind;
  final String? revision;
  final String? reason;
  final String? openBltVersion;
  final String? manufacturer;
  final DateTime? programmedAt;

  int get address => otpBase + index * otpBlockSize;

  /// "OpenBLT 1.16.0, WEYT, 2026-11-23 14:00:00 UTC"; fields not recorded
  /// are left out, like `make_hw_rev_otp.py`.
  String get extrasText => [
    if (openBltVersion != null) 'OpenBLT $openBltVersion',
    ?manufacturer,
    if (programmedAt != null) formatOtpDate(programmedAt!),
  ].join(', ');
}

class OtpState {
  OtpState(List<int> dump) : dump = Uint8List.fromList(dump) {
    if (dump.length != otpSize) {
      throw OtpException(
        'OTP dump has ${dump.length} bytes, expected $otpSize.',
      );
    }
  }

  final Uint8List dump;

  Uint8List block(int index) => Uint8List.sublistView(
    dump,
    index * otpBlockSize,
    (index + 1) * otpBlockSize,
  );

  Uint8List get lockChunk => Uint8List.sublistView(
    dump,
    otpLockOffset,
    otpLockOffset + otpLockChunkSize,
  );

  bool isErased(int index) => block(index).every((byte) => byte == 0xFF);

  bool isLocked(int index) => lockChunk[index] == 0x00;

  String? revision(int index) => checkOtpBlock(block(index)).revision;

  OtpBlockStatus status(int index) {
    final locked = isLocked(index);
    if (isErased(index)) {
      return OtpBlockStatus(
        index: index,
        bytes: block(index),
        locked: locked,
        kind: OtpBlockKind.erased,
      );
    }
    final check = checkOtpBlock(block(index));
    final valid = check.revision != null;
    final extras = decodeOtpExtras(block(index));
    return OtpBlockStatus(
      index: index,
      bytes: block(index),
      locked: locked,
      kind: valid ? OtpBlockKind.valid : OtpBlockKind.invalid,
      revision: check.revision,
      reason: check.reason,
      openBltVersion: valid ? extras.openBltVersion : null,
      manufacturer: valid ? extras.manufacturer : null,
      programmedAt: valid ? extras.programmedAt : null,
    );
  }

  List<OtpBlockStatus> get blocks => [
    for (var i = 0; i < otpBlockCount; i++) status(i),
  ];

  bool get anyProgrammed =>
      Iterable.generate(otpBlockCount).any((i) => !isErased(i));

  /// The last valid block, which is what the firmware reports.
  ({int index, String revision})? get effective {
    for (var i = otpBlockCount - 1; i >= 0; i--) {
      final rev = revision(i);
      if (rev != null) return (index: i, revision: rev);
    }
    return null;
  }

  /// First unlocked block after the last programmed one, or null if none.
  int? get nextFreeBlock {
    var lastUsed = -1;
    for (var i = 0; i < otpBlockCount; i++) {
      if (!isErased(i)) lastUsed = i;
    }
    for (var i = lastUsed + 1; i < otpBlockCount; i++) {
      if (!isLocked(i)) return i;
    }
    return null;
  }

  /// "'Rev 1.21' (block 10)", "INVALID" or "UNPROGRAMMED".
  String get firmwareSummary {
    final eff = effective;
    if (eff != null) return "'${eff.revision}' (block ${eff.index})";
    return anyProgrammed ? 'INVALID' : 'UNPROGRAMMED';
  }

  /// Same text as `make_hw_rev_otp.py --status`.
  String toText() {
    final buffer = StringBuffer('OTP block  address     lock    content\n');
    for (final block in blocks) {
      final content = switch (block.kind) {
        OtpBlockKind.erased => 'erased',
        OtpBlockKind.valid =>
          "valid '${block.revision}'"
              '${block.extrasText.isEmpty ? '' : ', ${block.extrasText}'}',
        OtpBlockKind.invalid => 'INVALID: ${block.reason}',
      };
      final lock = (block.locked ? 'locked' : '-').padRight(6);
      buffer.writeln(
        '  ${block.index.toString().padLeft(2)}       '
        '0x${_hex32(block.address)}  $lock  $content',
      );
      if (block.kind == OtpBlockKind.invalid) {
        buffer.writeln(otpHexdump(block.bytes, block.address));
      }
    }
    buffer.write('Firmware shows: $firmwareSummary');
    return buffer.toString();
  }
}

String otpHexdump(List<int> data, int address, {String indent = '       '}) {
  final lines = <String>[];
  for (var offset = 0; offset < data.length; offset += 16) {
    final row = data.sublist(offset, (offset + 16).clamp(0, data.length));
    final ascii = String.fromCharCodes(
      row.map((c) => _isPrintableAscii(c) ? c : 0x2E),
    );
    lines.add(
      '${indent}0x${_hex32(address + offset)}  '
      '${_hexBytes(row).toLowerCase().padRight(47)}  $ascii',
    );
  }
  return lines.join('\n');
}

class OtpException implements Exception {
  const OtpException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum OtpWriteAction { written, lockedExisting, alreadyPresent }

class OtpWriteResult {
  const OtpWriteResult({
    required this.action,
    required this.blockIndex,
    required this.revision,
    required this.openBltVersion,
    required this.finalState,
  });

  final OtpWriteAction action;
  final int blockIndex;
  final String revision;
  final String openBltVersion;
  final OtpState finalState;

  String get _what => "'$revision' (OpenBLT $openBltVersion, $otpManufacturer)";

  String get summary => switch (action) {
    OtpWriteAction.written =>
      'HW revision $_what written to OTP block $blockIndex and locked.',
    OtpWriteAction.lockedExisting =>
      'OTP block $blockIndex already held $_what; it is now locked.',
    OtpWriteAction.alreadyPresent =>
      'OTP block $blockIndex already holds $_what and is locked.',
  };
}

/// Reads and programs the OTP area through STM32_Programmer_CLI.
/// Every command and message is recorded in [transcript].
class OtpProgrammer {
  OtpProgrammer({
    required this.executablePath,
    required this.interface,
    ProcessRunner? runProcess,
    this.onOutput,
    this.retryDelay = const Duration(seconds: 2),
  }) : _runProcess = runProcess ?? runStreamingProcess;

  final String executablePath;

  /// Receives commands, CLI output and messages while they happen.
  final OutputCallback? onOutput;
  final DebugInterface interface;
  final Duration retryDelay;
  final ProcessRunner _runProcess;
  final _transcript = StringBuffer();

  String get transcript => _transcript.toString();

  /// Failures while connecting: the CLI did not touch the target, so a retry
  /// is always safe.
  static const connectErrors = [
    'DEV_TARGET_NOT_HALTED',
    'DEV_TARGET_RESET_ERR',
    'Unable to read device id',
    'No STM32 target found',
    'DEV_CONNECT_ERR',
  ];

  void _log(String message) {
    _transcript.writeln(message);
    onOutput?.call('$message\n');
  }

  Future<String> _run(List<String> arguments, {int attempts = 3}) async {
    final command = [
      '-c',
      'port=${interface.cliValue}',
      'mode=UR',
      ...arguments,
    ];
    final commandLine = Stm32CubeProgrammer.formatCommand(
      executablePath,
      command,
    );
    for (var attempt = 1; ; attempt++) {
      _log(commandLine);
      onOutput?.call('\n');
      // The runner streams the CLI output to [onOutput] itself.
      final result = await _runProcess(executablePath, command, onOutput);
      final output = stripAnsiEscapeCodes('${result.stdout}${result.stderr}');
      if (output.trim().isNotEmpty) _transcript.writeln(output.trimRight());
      _transcript.writeln();
      onOutput?.call(output.endsWith('\n') ? '\n' : '\n\n');
      if (result.exitCode == 0 && !output.contains('Error:')) return output;

      final connectFailed = connectErrors.any(output.contains);
      if (!connectFailed || attempt >= attempts) {
        throw OtpException(
          'STM32CubeProgrammer command failed (exit code ${result.exitCode}): '
          '$commandLine',
        );
      }
      _log(
        'Connection to target failed (attempt $attempt/$attempts), retrying...',
      );
      await Future<void>.delayed(retryDelay);
    }
  }

  Future<T> _withTempDir<T>(Future<T> Function(Directory dir) action) async {
    final dir = await Directory.systemTemp.createTemp('ecutester_otp_');
    try {
      return await action(dir);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<OtpState> readOtp() {
    return _withTempDir((dir) async {
      final path = '${dir.path}${Platform.pathSeparator}otp_dump.bin';
      await _run(['-u', _hexAddress(otpBase), otpSize.toString(), path]);
      return OtpState(await File(path).readAsBytes());
    });
  }

  Future<void> _write(Uint8List data, int address) {
    return _withTempDir((dir) async {
      final path = '${dir.path}${Platform.pathSeparator}otp_write.bin';
      await File(path).writeAsBytes(data, flush: true);
      await _run(['-w', path, _hexAddress(address), '-v']);
    });
  }

  Future<OtpState> _writeLock(OtpState state, int blockIndex) async {
    final expected = Uint8List.fromList(state.lockChunk);
    expected[blockIndex] = 0x00;
    OtpException? writeError;
    try {
      await _write(expected, otpLockBase);
    } on OtpException catch (error) {
      // CubeProgrammer reports "failed to download Sector[0]" when the lock
      // chunk already contains a 0x00 (an earlier lock), although the new lock
      // byte is programmed. The read-back below decides.
      writeError = error;
    }
    final readBack = await readOtp();
    if (!_bytesEqual(readBack.lockChunk, expected)) {
      throw OtpException(
        'Locking OTP block $blockIndex failed: lock chunk reads '
        '${_hexBytes(readBack.lockChunk)}, expected ${_hexBytes(expected)}.'
        '${writeError != null ? ' $writeError' : ''}',
      );
    }
    if (writeError != null) {
      _log(
        'Note: STM32_Programmer_CLI reported an error, but the read-back '
        'shows the lock was written correctly.',
      );
    }
    return readBack;
  }

  /// Writes [revision], [openBltVersion], the manufacturer and the date of
  /// this run to the first free block after the last programmed one,
  /// verifies it and locks it, like `make_hw_rev_otp.py --yes`. Nothing is
  /// written if the block in use already holds the same revision, OpenBLT
  /// version and manufacturer.
  Future<OtpWriteResult> programHwRevision(
    String revision, {
    required String openBltVersion,
    DateTime? programmedAt,
  }) async {
    final validationError =
        validateHwRevision(revision) ?? validateOpenBltVersion(openBltVersion);
    if (validationError != null) throw OtpException(validationError);
    final version = parseOpenBltVersion(openBltVersion)!;
    final versionText = version.join('.');
    final block = buildOtpBlock(
      revision,
      openBltVersion: version,
      manufacturer: otpManufacturer,
      programmedAt: programmedAt ?? DateTime.now(),
    );
    final what = "'$revision', OpenBLT $versionText, $otpManufacturer";
    OtpWriteResult result(OtpWriteAction action, int index, OtpState state) =>
        OtpWriteResult(
          action: action,
          blockIndex: index,
          revision: revision,
          openBltVersion: versionText,
          finalState: state,
        );

    var state = await readOtp();
    _log(state.toText());
    _log('');

    final eff = state.effective;
    if (eff != null &&
        _bytesEqual(
          otpBlockIdentity(state.block(eff.index)),
          otpBlockIdentity(block),
        )) {
      if (state.isLocked(eff.index)) {
        _log(
          'Nothing to do: block ${eff.index} already holds $what '
          'and is locked.',
        );
        return result(OtpWriteAction.alreadyPresent, eff.index, state);
      }
      _log(
        'Block ${eff.index} already holds $what but is not locked; '
        'only locking it.',
      );
      state = await _writeLock(state, eff.index);
      _log('Block ${eff.index} locked.');
      _log('');
      _log(state.toText());
      return result(OtpWriteAction.lockedExisting, eff.index, state);
    }

    final blockIndex = state.nextFreeBlock;
    if (blockIndex == null) {
      throw const OtpException(
        'No free OTP block left after the last programmed one.',
      );
    }
    final blockAddress = otpBase + blockIndex * otpBlockSize;
    _log(
      'Plan: write $what to block $blockIndex at '
      '${_hexAddress(blockAddress)}, then lock it.',
    );

    await _write(block, blockAddress);
    state = await readOtp();
    final written = state.effective;
    if (!_bytesEqual(state.block(blockIndex), block) ||
        written?.index != blockIndex ||
        written?.revision != revision) {
      _log(state.toText());
      throw OtpException(
        'Read-back of OTP block $blockIndex does not match; block NOT locked.',
      );
    }
    _log('Block $blockIndex written and verified.');

    state = await _writeLock(state, blockIndex);
    _log('Block $blockIndex locked.');
    _log('');
    _log(state.toText());
    return result(OtpWriteAction.written, blockIndex, state);
  }
}

bool _isPrintableAscii(int c) => c >= 0x20 && c <= 0x7E;

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex32(int value) =>
    value.toRadixString(16).toUpperCase().padLeft(8, '0');

String _hexAddress(int address) => '0x${_hex32(address)}';

String _hexBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
