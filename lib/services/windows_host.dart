import 'dart:io';

import 'catalog.dart';
import 'host.dart';
import 'installed.dart';
import 'setup_runner.dart';

/// The AppId in installer\jeti.iss.
const jetiAppId = '36B8D607-D548-4D10-88B8-9527F9C574D1';

/// Apps installed by their Inno Setup installers, and found in the registry.
class WindowsHost extends AppHost {
  @override
  String get catalogKey => 'apps';

  @override
  String get jetiAsset => 'Jeti-Setup.exe';

  @override
  String get jetiUpdateNote => 'It updates in a moment and opens again.';

  @override
  Future<InstalledApp?> findInstalled(CatalogApp app) async => findInstalledWindows(app.appId!);

  @override
  bool canOpen(CatalogApp app, InstalledApp installed) => exePathIn(installed.folder, app.exe) != null;

  @override
  bool canUninstall(InstalledApp installed) => installed.uninstallCommand != null;

  @override
  Future<void> install(
    CatalogApp app,
    File setup, {
    required InstalledApp? installed,
    required void Function(TaskStage stage) onStage,
    required Future<bool> Function(CatalogApp app) confirmClose,
  }) async {
    final exe = app.exe!;
    // An open app can't be replaced, so it's closed first, with the person's
    // say-so, and opened again once it's updated.
    var reopen = false;
    if (installed != null && await isRunning(exe)) {
      if (!await confirmClose(app)) {
        await setup.delete().catchError((_) => setup);
        return;
      }
      onStage(TaskStage.closing);
      await closeApp(exe);
      reopen = true;
    }

    onStage(TaskStage.installing);
    await runInstaller(setup, allUsers: installed?.allUsers ?? false);

    final path = exePathIn(findInstalledWindows(app.appId!)?.folder, exe);
    if (reopen && path != null) await openApp(path).catchError((_) {});
  }

  @override
  Future<void> open(CatalogApp app, InstalledApp installed) => openApp(exePathIn(installed.folder, app.exe)!);

  @override
  Future<void> uninstall(CatalogApp app, InstalledApp installed) => runUninstaller(installed.uninstallCommand!);

  @override
  Future<bool> isJetiInstalled() async => findInstalledWindows(jetiAppId) != null;

  @override
  Future<void> installJeti(File setup) async {
    final allUsers = findInstalledWindows(jetiAppId)?.allUsers ?? false;
    try {
      await Process.start(setup.path, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        allUsers ? '/ALLUSERS' : '/CURRENTUSER',
        // Tells jeti.iss to open Jeti again when it's done.
        '/RELAUNCH=1',
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      throw SetupException("Jeti's update couldn't start.");
    }
    exit(0);
  }
}

/// The exe's full path in [folder], an install folder.
String? exePathIn(String? folder, String? exe) {
  if (folder == null || folder.isEmpty || exe == null) return null;
  return folder.endsWith('\\') ? '$folder$exe' : '$folder\\$exe';
}
