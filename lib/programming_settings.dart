import 'dart:convert';
import 'dart:io';

class ProgrammingSettings {
  const ProgrammingSettings({
    this.firmwarePath = '',
    this.calibrationPath = '',
  });

  final String firmwarePath;
  final String calibrationPath;

  factory ProgrammingSettings.fromJson(Map<String, dynamic> json) {
    return ProgrammingSettings(
      firmwarePath: json['firmwarePath'] as String? ?? '',
      calibrationPath: json['calibrationPath'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'firmwarePath': firmwarePath, 'calibrationPath': calibrationPath};
  }
}

class ProgrammingSettingsStore {
  ProgrammingSettingsStore({File? file}) : file = file ?? defaultFile();

  final File file;

  static File defaultFile() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final String directory;
    if (Platform.isMacOS) {
      directory = '$home/Library/Application Support';
    } else if (Platform.isWindows) {
      directory = env['APPDATA'] ?? home;
    } else {
      directory = env['XDG_CONFIG_HOME'] ?? '$home/.config';
    }
    return File('$directory/BremerECU Production Tester/settings.json');
  }

  Future<ProgrammingSettings> load() async {
    try {
      if (!await file.exists()) return const ProgrammingSettings();
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const ProgrammingSettings();
      return ProgrammingSettings.fromJson(json);
    } on FormatException {
      return const ProgrammingSettings();
    } on FileSystemException {
      return const ProgrammingSettings();
    }
  }

  Future<void> save(ProgrammingSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
