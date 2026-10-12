import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Where Jeti finds the apps it offers: the website builds it from its project
/// pages (src/pages/apps.json.ts in the website).
const defaultCatalog = 'https://bersamamus.com/apps.json';

/// One app from the catalog.
class CatalogApp {
  CatalogApp({
    required this.id,
    required this.title,
    required this.tagline,
    required this.icon,
    required this.page,
    required this.repo,
    required this.appId,
    required this.installer,
    required this.exe,
  });

  factory CatalogApp.fromJson(Map<String, dynamic> json) => CatalogApp(
    id: json['id'] as String,
    title: json['title'] as String,
    tagline: json['tagline'] as String? ?? '',
    icon: json['icon'] as String?,
    page: json['page'] as String?,
    repo: json['repo'] as String,
    appId: json['appId'] as String,
    installer: json['installer'] as String,
    exe: json['exe'] as String,
  );

  final String id;
  final String title;
  final String tagline;

  /// A PNG's URL.
  final String? icon;

  /// The app's page on the website.
  final String? page;

  /// The GitHub repo its releases are in, as owner/name.
  final String repo;

  /// Its Inno Setup AppId, without braces.
  final String appId;

  /// The release asset to download, e.g. Blimp-Setup.exe.
  final String installer;

  /// Its exe's file name in the install folder.
  final String exe;
}

/// The catalog and where it came from.
class Catalog {
  Catalog(this.apps, {required this.fromCache});

  final List<CatalogApp> apps;

  /// True when the catalog couldn't be fetched and this is the copy saved
  /// the last time it was.
  final bool fromCache;

  static List<CatalogApp> parse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final app in json['apps'] as List) CatalogApp.fromJson(app as Map<String, dynamic>),
    ];
  }

  /// Fetches the catalog from [source], a URL or a file path (for testing
  /// against a local build of the website). Falls back to the saved copy when
  /// that fails, and throws only when there isn't one either.
  static Future<Catalog> load(String source) async {
    final cache = File('${(await getApplicationSupportDirectory()).path}\\catalog.json');
    try {
      final String body;
      if (source.startsWith('http://') || source.startsWith('https://')) {
        final response = await http.get(Uri.parse(source)).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(source));
        body = response.body;
      } else {
        body = await File(source).readAsString();
      }
      final apps = parse(body);
      await cache.writeAsString(body).catchError((_) => cache);
      return Catalog(apps, fromCache: false);
    } catch (_) {
      if (!await cache.exists()) rethrow;
      return Catalog(parse(await cache.readAsString()), fromCache: true);
    }
  }
}
