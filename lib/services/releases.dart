import 'dart:convert';

import 'package:http/http.dart' as http;

import 'version.dart';

/// An app's latest release on GitHub, and the installer in it.
class Release {
  Release({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    required this.size,
    required this.sha256,
    required this.pageUrl,
  });

  final Version version;

  /// The release's description, in Markdown.
  final String notes;
  final Uri downloadUrl;
  final int size;

  /// The installer's SHA-256 hash in hex, as GitHub lists it, to check the
  /// download against. Null for older releases GitHub has no hash for.
  final String? sha256;
  final Uri pageUrl;
}

/// Why a release couldn't be found.
class ReleaseException implements Exception {
  ReleaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Asks GitHub for [repo]'s latest release (pre-releases and drafts are left
/// out) and finds [installer] in it.
///
/// Without signing in, GitHub allows 60 of these an hour from one connection.
Future<Release> fetchLatestRelease(String repo, String installer, {http.Client? client}) async {
  final uri = Uri.https('api.github.com', '/repos/$repo/releases/latest');
  final http.Response response;
  final c = client ?? http.Client();
  try {
    response = await c
        .get(uri, headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Jeti'})
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    throw ReleaseException("Couldn't reach GitHub");
  } finally {
    if (client == null) c.close();
  }

  if (response.statusCode == 404) throw ReleaseException('No releases yet');
  if ((response.statusCode == 403 || response.statusCode == 429) &&
      response.headers['x-ratelimit-remaining'] == '0') {
    final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    final minutes = reset == null
        ? null
        : (DateTime.fromMillisecondsSinceEpoch(reset * 1000).difference(DateTime.now()).inMinutes + 1);
    throw ReleaseException(
      minutes == null ? 'Checked too often; try again later' : 'Checked too often; try again in $minutes min',
    );
  }
  if (response.statusCode != 200) throw ReleaseException('GitHub answered ${response.statusCode}');

  return parseRelease(jsonDecode(response.body) as Map<String, dynamic>, installer);
}

Release parseRelease(Map<String, dynamic> json, String installer) {
  final tag = json['tag_name'] as String? ?? '';
  final version = Version.tryParse(tag);
  if (version == null) throw ReleaseException('The latest release ($tag) has no version number');

  final assets = (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
  final asset = assets.where((a) => (a['name'] as String).toLowerCase() == installer.toLowerCase()).firstOrNull;
  if (asset == null) throw ReleaseException('The latest release has no $installer');

  final digest = asset['digest'] as String?;
  return Release(
    version: version,
    notes: (json['body'] as String? ?? '').trim(),
    downloadUrl: Uri.parse(asset['browser_download_url'] as String),
    size: asset['size'] as int? ?? 0,
    sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
    pageUrl: Uri.parse(json['html_url'] as String),
  );
}
