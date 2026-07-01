# BremerECU Production Tester

BremerECU Production Tester is a Flutter desktop application for final PCBA production testing over UART. It connects to a BremerECU-compatible board, samples selected ECU output channels, shows live measurements during collection, then produces a clear PASS or FAIL result for the operator.

The tool is designed for a production bench: select the detected tester UART, watch live values while the sample set is collected, and record the result with a numbered CSV log for traceability.

## Features

- Lists only the intended USB serial device: VID `0483`, PID `5740`.
- Connects at `115200 8N1`.
- Requests ECU output-channel data at 10 Hz.
- Collects `100` frames per test.
- Shows a live dashboard for:
  - RPM
  - CLT
  - MAP
  - Accelerator Pedal
- Validates averages against configured production limits.
- Displays a high-visibility PASS/FAIL result screen.
- Shows failure reasons when a metric is outside range.
- Saves every completed test as an iteratively numbered CSV log per connected device.

## Test Limits

The current pass criteria are configured in [lib/ecu_protocol.dart](lib/ecu_protocol.dart):

| Metric | Passing average range |
| --- | ---: |
| RPM | `990-1010 RPM` |
| CLT | `66.0-67.5 C` |
| MAP | `39.5-40.5 kPa` |
| Accelerator Pedal | `11.0-13.0 %` |

A test passes only when all metric averages are inside their configured ranges.

## Operator Workflow

1. Connect the PCBA/tester UART to the Mac.
2. Start the application.
3. Select the listed UART device.
4. Wait while the live dashboard collects 100 frames.
5. Read the final PASS or FAIL result.
6. If the result is FAIL, review the displayed failure reasons.

The result screen also shows the saved CSV path for the completed test.

## Log Files

Each completed test is saved automatically as a CSV file under:

```text
~/Documents/BremerECU Production Tester Logs/<device>/test_0001.csv
```

Subsequent tests for the same device are saved as:

```text
test_0002.csv
test_0003.csv
...
```

The device folder uses the USB serial number when available. If no serial number is exposed, the app falls back to VID, PID, and port name.

Each CSV contains:

- log index
- start and completion timestamps
- PASS/FAIL result
- device metadata
- failure reasons, if any
- metric averages
- all collected frame values

The log-writing code lives in [lib/test_log_writer.dart](lib/test_log_writer.dart).

## Serial Protocol

The app sends the ECU output-channel request command `O` with offset `0` and length `38`.

Request format:

```text
00 05 4F <offset:u16-le> <length:u16-le> <crc32:u32-be>
```

Response format currently handled by the app:

```text
<body length:u16-be> <status:u8> <38-byte output payload> <crc32:u32-be>
```

For the configured request, the expected response is:

```text
00 27 <39-byte body> <4-byte CRC>
```

The response CRC is validated before any metrics are parsed.

## Development

Install Flutter and ensure macOS desktop support is enabled. This project uses:

- `flutter_libserialport`
- `crc32_checksum`

Fetch dependencies:

```bash
flutter pub get
```

Run on macOS:

```bash
flutter run -d macos
```

Build a debug macOS app:

```bash
flutter build macos --debug
```

Build a release macOS app:

```bash
flutter build macos --release
```

Run checks:

```bash
flutter analyze
flutter test
```

## macOS Notes

The app name shown in the macOS title bar is configured in:

```text
macos/Runner/Configs/AppInfo.xcconfig
```

The macOS sandbox is disabled for this tool because serial device access requires direct access to `/dev/cu.*` or `/dev/tty.*` devices.

`flutter_libserialport` currently emits a Flutter warning about Swift Package Manager support. The app builds through CocoaPods.

## Project Structure

```text
lib/main.dart             UI, serial device selection, live collection, result screen
lib/ecu_protocol.dart     ECU request/response protocol, frame parsing, pass/fail rules
lib/test_log_writer.dart  CSV log persistence and per-device numbering
test/                     Protocol and log writer tests
macos/                    macOS desktop runner configuration
```
