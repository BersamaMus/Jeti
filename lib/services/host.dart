import 'dart:io';

import 'android_host.dart';
import 'catalog.dart';
import 'installed.dart';
import 'windows_host.dart';

enum TaskStage { waiting, downloading, closing, installing }

/// What installing, finding, opening and removing an app means on the
/// platform Jeti runs on: Inno Setup installers and the registry on Windows,
/// APKs and Android's package installer on Android.
abstract class AppHost {
  static final AppHost current = Platform.isAndroid ? AndroidHost() : WindowsHost();

  /// The list in apps.json with this platform's apps.
  String get catalogKey;

  /// Jeti's own download in its GitHub releases.
  String get jetiAsset;

  /// Under the "Jeti x.y is out" banner: what happens when it updates.
  String get jetiUpdateNote;

  /// How the app is installed here, or null when it isn't.
  Future<InstalledApp?> findInstalled(CatalogApp app);

  bool canOpen(CatalogApp app, InstalledApp installed);
  bool canUninstall(InstalledApp installed);

  /// Makes sure Jeti may install apps, asking the person (with [ask]) to allow
  /// it when the platform needs that. False when it still may not.
  Future<bool> ensureCanInstall(Future<bool> Function() ask) async => true;

  /// Installs the downloaded [setup] over [installed] (null for a fresh
  /// install) and deletes it. Throws a SetupException when it fails.
  ///
  /// [confirmClose] is asked before closing the app to update it; when it
  /// says no, nothing is installed.
  Future<void> install(
    CatalogApp app,
    File setup, {
    required InstalledApp? installed,
    required void Function(TaskStage stage) onStage,
    required Future<bool> Function(CatalogApp app) confirmClose,
  });

  /// Throws when the app couldn't be opened.
  Future<void> open(CatalogApp app, InstalledApp installed);

  /// Whether the platform has a page of its own for an installed app.
  bool get hasAppInfo => false;

  /// Opens the platform's page for the app; throws when it couldn't.
  Future<void> openAppInfo(CatalogApp app) async {}

  /// Starts removing the app; the person confirms in the platform's own
  /// dialog, so it may or may not be gone when this returns.
  Future<void> uninstall(CatalogApp app, InstalledApp installed);

  /// True when this Jeti was installed, rather than run from the project,
  /// which has nothing to update.
  Future<bool> isJetiInstalled();

  /// Hands over to the downloaded new Jeti, which replaces this one. Returns
  /// only if it couldn't (throwing a SetupException).
  Future<void> installJeti(File setup);
}
