import 'package:win32_registry/win32_registry.dart';

import 'version.dart';

/// An app as Windows has it installed.
class InstalledApp {
  InstalledApp({
    required this.version,
    required this.folder,
    required this.allUsers,
    required this.uninstallCommand,
  });

  final Version? version;

  /// The install folder, ending in a backslash.
  final String? folder;

  /// True when it was installed for everyone (in Program Files, which needs
  /// admin rights to update), false when just for this user.
  final bool allUsers;
  final String? uninstallCommand;
}

/// Finds the app Inno Setup installed under [appId], or null when it isn't.
///
/// Inno Setup records each app it installs under
/// ...\Uninstall\{AppId}_is1: in this user's registry when installed just for
/// them, or the machine's when installed for everyone.
InstalledApp? findInstalled(String appId) {
  final path = 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{$appId}_is1';
  for (final (root, allUsers) in [(CURRENT_USER, false), (LOCAL_MACHINE, true)]) {
    final RegistryKey key;
    try {
      key = root.open(path);
    } catch (_) {
      continue;
    }
    try {
      return InstalledApp(
        version: Version.tryParse(key.getString('DisplayVersion')),
        folder: key.getString('InstallLocation'),
        allUsers: allUsers,
        uninstallCommand: key.getString('UninstallString'),
      );
    } finally {
      key.close();
    }
  }
  return null;
}
