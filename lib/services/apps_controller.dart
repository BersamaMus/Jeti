import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';
import 'host.dart';
import 'installed.dart';
import 'releases.dart';
import 'setup_runner.dart';
import 'version.dart';

export 'host.dart' show TaskStage;

/// Jeti's own releases, for updating itself.
const jetiRepo = 'BersamaMus/Jeti';

enum AppStatus { checking, notInstalled, updateAvailable, upToDate }

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

  // Counts reads of [installed], so only the newest one is kept.
  int _installedReads = 0;
}

/// The app list, and installing, updating and removing what's in it.
class AppsController extends ChangeNotifier {
  AppsController({required this.catalogSource, AppHost? host}) : host = host ?? AppHost.current;

  /// A URL or file path for the catalog.
  final String catalogSource;
  final AppHost host;

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

  /// Asked before sending the person to Android's setting that lets Jeti
  /// install apps; true to go there.
  Future<bool> Function()? confirmAllowInstalls;

  // Installs run one after another, never two installers at once.
  Future<void> _queue = Future.value();
  final _uninstallWatches = <String, Timer>{};

  List<AppEntry> get updatable => entries.where((e) => e.status == AppStatus.updateAvailable).toList();

  bool get busy => entries.any((e) => e.task != null) || jetiUpdateProgress != null;

  bool canOpen(AppEntry entry) => entry.installed != null && host.canOpen(entry.app, entry.installed!);

  bool canUninstall(AppEntry entry) => entry.installed != null && host.canUninstall(entry.installed!);

  /// Loads the catalog, then checks what's installed and what's newest.
  Future<void> refresh() async {
    if (loading || busy) return;
    loading = true;
    loadError = null;
    notifyListeners();

    try {
      final catalog = await Catalog.load(catalogSource, list: host.catalogKey);
      catalogFromCache = catalog.fromCache;
      final previous = {for (final e in entries) e.app.id: e};
      entries = [
        for (final app in catalog.apps)
          AppEntry(app)
            ..icon = previous[app.id]?.icon
            ..latest = previous[app.id]?.latest
            ..installed = previous[app.id]?.installed
            ..checking = true,
      ];
    } catch (_) {
      loadError = "Couldn't load the list of apps. Check your connection and try again.";
      loading = false;
      notifyListeners();
      return;
    }
    await refreshInstalled();
    loading = false;
    notifyListeners();

    await Future.wait([
      for (final e in entries) ...[_check(e), _loadIcon(e)],
      _checkJeti(),
    ]);
  }

  /// Shows the icon saved last time straight away, then fetches it again in
  /// case it changed (or failed before). Without a connection the saved one stays.
  Future<void> _loadIcon(AppEntry entry) async {
    final url = entry.app.icon;
    if (url == null) return;
    final file = File(p.join((await getApplicationSupportDirectory()).path, 'icons', '${entry.app.id}.png'));
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
  /// outside Jeti. Cheap: it only asks the registry, or Android.
  Future<void> refreshInstalled() async {
    for (final e in entries) {
      if (e.task == null) await _reread(e);
    }
    notifyListeners();
  }

  /// Reads what's installed into [entry]. When reads overlap (a refresh while
  /// an install finishes), the one started last wins.
  Future<void> _reread(AppEntry entry) async {
    final read = ++entry._installedReads;
    final found = await _findInstalled(entry.app);
    if (read == entry._installedReads) entry.installed = found;
  }

  Future<InstalledApp?> _findInstalled(CatalogApp app) async {
    try {
      return await host.findInstalled(app);
    } catch (_) {
      return null;
    }
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
      if (!await host.isJetiInstalled()) return;
      final latest = await fetchLatestRelease(jetiRepo, host.jetiAsset);
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
    entry.error = null;
    try {
      await _ensureCanInstall();
    } on SetupException catch (e) {
      entry.error = e.message;
      notifyListeners();
      return;
    } catch (_) {
      entry.error = "Couldn't check whether Jeti may install apps. Try again.";
      notifyListeners();
      return;
    }
    if (entry.task != null) return;
    entry.task = AppTask(TaskStage.waiting);
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
      // Read before the task ends, so the card never shows the old version
      // with nothing going on (and an Update button that would reinstall).
      await _reread(entry);
      entry.task = null;
      notifyListeners();
      done.complete();
    }
  }

  Future<void> _install(AppEntry entry) async {
    final task = entry.task!;
    final release = entry.latest!;

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

    await host.install(
      entry.app,
      setup,
      installed: await _findInstalled(entry.app),
      onStage: (stage) {
        task.stage = stage;
        notifyListeners();
      },
      confirmClose: (app) async => await confirmClose?.call(app) ?? false,
    );
  }

  /// Throws when Jeti may not install apps, after asking. Installs started
  /// together (Update all) wait on the same question.
  Future<void> _ensureCanInstall() async {
    final asking = _allowInstalls ??= host
        .ensureCanInstall(() async => await confirmAllowInstalls?.call() ?? false)
        .whenComplete(() => _allowInstalls = null);
    if (!await asking) throw SetupException("Jeti isn't allowed to install apps yet. Allow it, then try again.");
  }

  Future<bool>? _allowInstalls;

  /// Updates every app that has an update, one after another.
  Future<void> updateAll() => Future.wait([for (final e in updatable) install(e)]);

  Future<void> open(AppEntry entry) async {
    if (!canOpen(entry)) return;
    try {
      await host.open(entry.app, entry.installed!);
      entry.error = null;
    } catch (_) {
      entry.error = "${entry.app.title} couldn't be opened. Try updating it to repair it.";
    }
    notifyListeners();
  }

  bool hasAppInfo(AppEntry entry) => entry.installed != null && host.hasAppInfo;

  Future<void> openAppInfo(AppEntry entry) async {
    if (!hasAppInfo(entry)) return;
    try {
      await host.openAppInfo(entry.app);
    } catch (_) {
      entry.error = "Android's page for ${entry.app.title} couldn't be opened.";
      notifyListeners();
    }
  }

  /// Starts the app's uninstaller, then watches for it to be gone: the person
  /// confirms in the uninstaller first, and on Windows it hands off to a copy
  /// of itself, so it finishing says nothing.
  Future<void> uninstall(AppEntry entry) async {
    if (!canUninstall(entry)) return;
    try {
      await host.uninstall(entry.app, entry.installed!);
    } catch (_) {
      entry.error = "The uninstaller couldn't start.";
      notifyListeners();
      return;
    }
    _uninstallWatches[entry.app.id]?.cancel();
    var ticks = 0;
    _uninstallWatches[entry.app.id] = Timer.periodic(const Duration(seconds: 2), (timer) async {
      // Gives up after 10 minutes, e.g. when the uninstall was cancelled.
      if (await _findInstalled(entry.app) == null || ++ticks > 300) {
        timer.cancel();
        _uninstallWatches.remove(entry.app.id);
        await refreshInstalled();
      }
    });
  }

  /// Downloads the new Jeti and hands over to it, which replaces this one.
  Future<void> updateJeti() async {
    final release = jetiUpdate;
    if (release == null || busy) return;
    jetiUpdateProgress = 0;
    jetiUpdateError = null;
    notifyListeners();
    try {
      await _ensureCanInstall();
      final setup = await downloadInstaller(
        release,
        host.jetiAsset,
        onProgress: (p) {
          jetiUpdateProgress = p;
          notifyListeners();
        },
      );
      await host.installJeti(setup);
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
