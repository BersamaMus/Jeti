import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';
import 'installed.dart';
import 'releases.dart';
import 'setup_runner.dart';
import 'version.dart';

/// Jeti's own releases and installer, for updating itself.
const jetiRepo = 'BersamaMus/Jeti';
const jetiInstaller = 'Jeti-Setup.exe';

/// The AppId in installer\jeti.iss.
const jetiAppId = '36B8D607-D548-4D10-88B8-9527F9C574D1';

enum AppStatus { checking, notInstalled, updateAvailable, upToDate }

enum TaskStage { waiting, downloading, closing, installing }

/// What Jeti is doing to an app right now.
class AppTask {
  AppTask(this.stage);

  TaskStage stage;

  /// The download's progress, 0 to 1.
  double? progress;
}

/// An app in the list, with what Jeti knows about it.
class AppEntry {
  AppEntry(this.app);

  final CatalogApp app;

  /// The app's icon, saved from the catalog's link.
  File? icon;
  InstalledApp? installed;
  Release? latest;

  /// Why [latest] couldn't be found, when it couldn't.
  String? checkError;
  bool checking = false;
  AppTask? task;

  /// Why the last install or update failed.
  String? error;

  AppStatus get status {
    if (installed == null) return latest == null && checking ? AppStatus.checking : AppStatus.notInstalled;
    final current = installed!.version;
    final newest = latest?.version;
    if (newest == null) return checking ? AppStatus.checking : AppStatus.upToDate;
    return current == null || current < newest ? AppStatus.updateAvailable : AppStatus.upToDate;
  }

  /// The installed exe's full path.
  String? get exePath {
    final folder = installed?.folder;
    if (folder == null || folder.isEmpty) return null;
    return folder.endsWith('\\') ? '$folder${app.exe}' : '$folder\\${app.exe}';
  }
}

/// The app list, and installing, updating and removing what's in it.
class AppsController extends ChangeNotifier {
  AppsController({required this.catalogSource});

  /// A URL or file path for the catalog.
  final String catalogSource;

  List<AppEntry> entries = [];
  bool loading = false;

  /// Why the catalog couldn't be loaded, when there's nothing to show.
  String? loadError;

  /// True when showing the saved catalog because the website was unreachable.
  bool catalogFromCache = false;

  Version? jetiVersion;

  /// A newer Jeti, when there is one and this copy was installed (not a build
  /// run from the project, which has nothing to update).
  Release? jetiUpdate;

  /// The Jeti update's download progress while it's downloading.
  double? jetiUpdateProgress;
  String? jetiUpdateError;

  /// Asked before closing a running app to update it; true to go ahead.
  Future<bool> Function(CatalogApp app)? confirmClose;

  // Installs run one after another, never two installers at once.
  Future<void> _queue = Future.value();
  final _uninstallWatches = <String, Timer>{};

  List<AppEntry> get updatable => entries.where((e) => e.status == AppStatus.updateAvailable).toList();

  bool get busy => entries.any((e) => e.task != null) || jetiUpdateProgress != null;

  /// Loads the catalog, then checks what's installed and what's newest.
  Future<void> refresh() async {
    if (loading || busy) return;
    loading = true;
    loadError = null;
    notifyListeners();

    try {
      final catalog = await Catalog.load(catalogSource);
      catalogFromCache = catalog.fromCache;
      final previous = {for (final e in entries) e.app.id: e};
      entries = [
        for (final app in catalog.apps)
          AppEntry(app)
            ..icon = previous[app.id]?.icon
            ..latest = previous[app.id]?.latest
            ..checking = true,
      ];
    } catch (_) {
      loadError = "Couldn't load the list of apps. Check your connection and try again.";
      loading = false;
      notifyListeners();
      return;
    }
    refreshInstalled();
    loading = false;
    notifyListeners();

    await Future.wait([for (final e in entries) ...[_check(e), _loadIcon(e)], _checkJeti()]);
  }

  /// Shows the icon saved last time straight away, then fetches it again in
  /// case it changed (or failed before). Without a connection the saved one stays.
  Future<void> _loadIcon(AppEntry entry) async {
    final url = entry.app.icon;
    if (url == null) return;
    final file = File('${(await getApplicationSupportDirectory()).path}\\icons\\${entry.app.id}.png');
    if (entry.icon == null && await file.exists()) {
      entry.icon = file;
      notifyListeners();
    }
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
      if (await file.exists() && listEquals(await file.readAsBytes(), response.bodyBytes)) return;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      // The image cache knows the file by its path, so it's told it changed.
      await FileImage(file).evict();
      entry.icon = file;
      notifyListeners();
    } catch (_) {
      // Keeps the saved icon, or the app's first letter.
    }
  }

  /// Rereads what's installed, e.g. after an app is installed or removed
  /// outside Jeti. Cheap: it only reads the registry.
  void refreshInstalled() {
    for (final e in entries) {
      if (e.task == null) e.installed = findInstalled(e.app.appId);
    }
    notifyListeners();
  }

  Future<void> _check(AppEntry entry) async {
    try {
      entry.latest = await fetchLatestRelease(entry.app.repo, entry.app.installer);
      entry.checkError = null;
    } on ReleaseException catch (e) {
      entry.checkError = e.message;
    } finally {
      entry.checking = false;
      notifyListeners();
    }
  }

  Future<void> _checkJeti() async {
    try {
      jetiVersion ??= Version.tryParse((await PackageInfo.fromPlatform()).version);
      if (findInstalled(jetiAppId) == null) return;
      final latest = await fetchLatestRelease(jetiRepo, jetiInstaller);
      if (jetiVersion != null && jetiVersion! < latest.version) {
        jetiUpdate = latest;
        notifyListeners();
      }
    } catch (_) {
      // Jeti's own update is a nicety; the apps matter more.
    }
  }

  /// Installs [entry]'s latest version, or updates it to it.
  Future<void> install(AppEntry entry) async {
    if (entry.task != null || entry.latest == null) return;
    entry.task = AppTask(TaskStage.waiting);
    entry.error = null;
    notifyListeners();

    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      await _install(entry);
    } on SetupException catch (e) {
      entry.error = e.message;
    } catch (e) {
      entry.error = 'Something went wrong: $e';
    } finally {
      entry.task = null;
      entry.installed = findInstalled(entry.app.appId);
      notifyListeners();
      done.complete();
    }
  }

  Future<void> _install(AppEntry entry) async {
    final task = entry.task!;
    final release = entry.latest!;
    final installed = findInstalled(entry.app.appId);

    task
      ..stage = TaskStage.downloading
      ..progress = 0;
    notifyListeners();
    final setup = await downloadInstaller(
      release,
      entry.app.installer,
      onProgress: (p) {
        task.progress = p;
        notifyListeners();
      },
    );

    // An open app can't be replaced, so it's closed first, with the person's
    // say-so, and opened again once it's updated.
    var reopen = false;
    if (installed != null && await isRunning(entry.app.exe)) {
      if (!(await confirmClose?.call(entry.app) ?? false)) {
        await setup.delete().catchError((_) => setup);
        return;
      }
      task.stage = TaskStage.closing;
      notifyListeners();
      await closeApp(entry.app.exe);
      reopen = true;
    }

    task.stage = TaskStage.installing;
    notifyListeners();
    await runInstaller(setup, allUsers: installed?.allUsers ?? false);

    entry.installed = findInstalled(entry.app.appId);
    if (reopen && entry.exePath != null) await openApp(entry.exePath!).catchError((_) {});
  }

  /// Updates every app that has an update, one after another.
  Future<void> updateAll() => Future.wait([for (final e in updatable) install(e)]);

  Future<void> open(AppEntry entry) async {
    final exe = entry.exePath;
    if (exe == null) return;
    try {
      await openApp(exe);
      entry.error = null;
    } catch (_) {
      entry.error = "${entry.app.title} couldn't be opened. Try updating it to repair it.";
    }
    notifyListeners();
  }

  /// Starts the app's uninstaller, then watches for it to be gone. The
  /// uninstaller hands off to a copy of itself, so its exit says nothing.
  Future<void> uninstall(AppEntry entry) async {
    final command = entry.installed?.uninstallCommand;
    if (command == null) return;
    try {
      await runUninstaller(command);
    } catch (_) {
      entry.error = "The uninstaller couldn't start.";
      notifyListeners();
      return;
    }
    _uninstallWatches[entry.app.id]?.cancel();
    var ticks = 0;
    _uninstallWatches[entry.app.id] = Timer.periodic(const Duration(seconds: 2), (timer) {
      // Gives up after 10 minutes, e.g. when the uninstall was cancelled.
      if (findInstalled(entry.app.appId) == null || ++ticks > 300) {
        timer.cancel();
        _uninstallWatches.remove(entry.app.id);
        refreshInstalled();
      }
    });
  }

  /// Downloads the new Jeti and hands over to its installer, which closes this
  /// one, updates it and opens the new one.
  Future<void> updateJeti() async {
    final release = jetiUpdate;
    if (release == null || busy) return;
    jetiUpdateProgress = 0;
    jetiUpdateError = null;
    notifyListeners();
    try {
      final setup = await downloadInstaller(
        release,
        jetiInstaller,
        onProgress: (p) {
          jetiUpdateProgress = p;
          notifyListeners();
        },
      );
      final allUsers = findInstalled(jetiAppId)?.allUsers ?? false;
      await Process.start(setup.path, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        allUsers ? '/ALLUSERS' : '/CURRENTUSER',
        // Tells jeti.iss to open Jeti again when it's done.
        '/RELAUNCH=1',
      ], mode: ProcessStartMode.detached);
      exit(0);
    } on SetupException catch (e) {
      jetiUpdateError = e.message;
    } catch (_) {
      jetiUpdateError = "Jeti's update couldn't start.";
    }
    jetiUpdateProgress = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _uninstallWatches.values) {
      t.cancel();
    }
    super.dispose();
  }
}
