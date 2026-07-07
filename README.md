# BremerECU Production Tester

BremerECU Production Tester is a Flutter desktop application for initial PCBA programming and final production testing. It first guides the operator through TC2030 JTAG/SWD connection and flashes the initial firmware with STM32CubeProgrammer CLI. It then connects to a BremerECU-compatible board over UART, samples selected ECU output channels, shows live measurements during collection, and produces a clear PASS or FAIL result for the operator.

The tool is designed for a production bench: program the bare board, select the detected tester UART, watch live values while the sample set is collected, and record the result with a numbered CSV log for traceability.

## Features

- Lists only the intended USB serial device: VID `0483`, PID `5740`.
- Shows the TC2030 connection graphic before programming.
- Lets the operator select the `STM32_Programmer_CLI` executable, firmware binary, debug interface, and flash address.
- Programs via STM32CubeProgrammer CLI with verify and reset.
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

1. Connect the TC2030 cable to the bare board as shown in the application.
2. Start the application.
3. Select the STM32CubeProgrammer CLI executable if the default path is not correct.
4. Select the initial firmware `.bin` file.
5. Confirm the debug interface and flash address, then run programming.
6. After programming succeeds, connect the PCBA/tester UART and continue to the UART test.
7. Select the listed UART device.
8. Wait while the live dashboard collects 100 frames.
9. Read the final PASS or FAIL result.
10. If the result is FAIL, review the displayed failure reasons.

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
- `file_selector`

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

## GitHub Builds

The repository includes a GitHub Actions workflow at:

```text
.github/workflows/build-desktop.yml
```

It builds:

- macOS release app
- Windows x64 release app

Each workflow run uploads zipped build artifacts. In GitHub, open the workflow run and download them from the **Artifacts** section.

Pushing a version tag also creates a GitHub Release with the macOS and Windows zip files attached:

```bash
git tag v1.0.0
git push origin v1.0.0
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
lib/main.dart                  UI, initial programming, serial device selection, live collection, result screen
lib/initial_programming.dart   STM32CubeProgrammer CLI command building and execution
lib/ecu_protocol.dart          ECU request/response protocol, frame parsing, pass/fail rules
lib/test_log_writer.dart       CSV log persistence and per-device numbering
test/                     Protocol and log writer tests
macos/                    macOS desktop runner configuration
```
