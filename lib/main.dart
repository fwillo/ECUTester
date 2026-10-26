import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'ecu_protocol.dart';
import 'initial_programming.dart';
import 'programming_log_writer.dart';
import 'programming_settings.dart';
import 'test_log_writer.dart';

part 'src/serial_transport.dart';
part 'src/screens/initial_programming_screen.dart';
part 'src/screens/uart_selection_screen.dart';
part 'src/screens/data_collection_screen.dart';
part 'src/screens/test_result_screen.dart';
part 'src/widgets/shared_widgets.dart';

const int targetUsbVendorId = 0x0483;
const int targetUsbProductId = 0x5740;
const bool serialDebugLogging = true;

void _logSerial(String message) {
  if (serialDebugLogging) {
    debugPrint('[ECU] $message');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(EcuTesterApp(serialService: LibSerialPortService()));
}

class EcuTesterApp extends StatelessWidget {
  const EcuTesterApp({super.key, required this.serialService});

  final SerialService serialService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BremerECU Production Tester',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f6f5e),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff5f7f4),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: InitialProgrammingScreen(serialService: serialService),
    );
  }
}
