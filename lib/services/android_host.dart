import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'catalog.dart';
import 'host.dart';
import 'installed.dart';
import 'setup_runner.dart';
import 'version.dart';

/// Apps installed from their APKs through Android's package installer. The
/// other end of the channel is android\app\src\main\kotlin\...\MainActivity.kt.
class AndroidHost extends AppHost {
  static const _channel = MethodChannel('jeti/android');

  @override
  String get catalogKey => 'android';

  @override
  String get jetiAsset => 'Jeti.apk';

  @override
  String get jetiUpdateNote => 'Android asks you to confirm, then Jeti closes to update.';

  @override
  Future<InstalledApp?> findInstalled(CatalogApp app) async {
    final version = await _channel.invokeMethod<String>('installedVersion', {'package': app.package});
    if (version == null) return null;
    return InstalledApp(version: Version.tryParse(version), folder: null, allUsers: false, uninstallCommand: null);
  }

  @override
  bool canOpen(CatalogApp app, InstalledApp installed) => true;

  @override
  bool canUninstall(InstalledApp installed) => true;

  /// Android asks once whether Jeti may install apps, on a settings screen of
  /// its own. Jeti explains first, opens it, and checks again on coming back.
  @override
  Future<bool> ensureCanInstall(Future<bool> Function() ask) async {
    if (await _canInstall()) return true;
    if (!await ask()) return false;
    final back = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!back.isCompleted) back.complete();
      },
    );
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
      await back.future;
    } finally {
      listener.dispose();
    }
    return _canInstall();
  }

  Future<bool> _canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> install(
    CatalogApp app,
    File setup, {
    required InstalledApp? installed,
    required void Function(TaskStage stage) onStage,
    required Future<bool> Function(CatalogApp app) confirmClose,
  }) async {
    // Android closes the app itself to update it.
    onStage(TaskStage.installing);
    await _installApk(setup, app.title);
  }

  /// Hands [apk] to Android's installer and waits for its answer: after the
  /// person confirms, or straight away for an update to an app Jeti
  /// installed (Android 12 and up).
  Future<void> _installApk(File apk, String title) async {
    final Map<Object?, Object?> result;
    try {
      result = await _channel.invokeMethod<Map<Object?, Object?>>('install', {'path': apk.path}) ?? const {};
    } on PlatformException catch (e) {
      throw SetupException("The install couldn't start: ${e.message}");
    }
    final message = result['message'] as String?;
    switch (result['status']) {
      case 'installed':
        return;
      case 'cancelled':
        throw SetupException('The install was cancelled.');
      case 'conflict':
        throw SetupException(
          'The $title on this phone came from somewhere else, so it can\'t be updated from here. '
          'Uninstall it, then install it again from Jeti (your settings in it are lost).',
        );
      case 'incompatible':
        throw SetupException("$title doesn't run on this phone's version of Android.");
      case 'storage':
        throw SetupException("There isn't enough space on this phone. Free some up and try again.");
      case 'blocked':
        throw SetupException('Android blocked the install${message == null ? '' : ' ($message)'}.');
      case 'invalid':
        throw SetupException("The download isn't a working app. Try again.");
      case 'busy':
        throw SetupException('Another install is still waiting for you. Finish that one first.');
      default:
        throw SetupException('The install failed${message == null ? '' : ' ($message)'}.');
    }
  }

  @override
  Future<void> open(CatalogApp app, InstalledApp installed) async {
    final opened = await _channel.invokeMethod<bool>('open', {'package': app.package});
    if (opened != true) throw StateError('No launcher activity');
  }

  @override
  Future<void> uninstall(CatalogApp app, InstalledApp installed) =>
      _channel.invokeMethod<void>('uninstall', {'package': app.package});

  @override
  bool get hasAppInfo => true;

  /// Android's own page for the app, with its storage, permissions and so on.
  @override
  Future<void> openAppInfo(CatalogApp app) => _channel.invokeMethod<void>('appInfo', {'package': app.package});

  /// A debug build is one run from the project; anything else was installed.
  @override
  Future<bool> isJetiInstalled() async => !kDebugMode;

  @override
  Future<void> installJeti(File setup) => _installApk(setup, 'Jeti');
}
