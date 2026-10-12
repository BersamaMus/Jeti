/// A version like 1.0.1, from a release tag (v1.0.1) or the registry (1.0.1).
///
/// Only the numbers count: a pre-release or build suffix (-rc1, +2) is ignored,
/// since Jeti only ever offers full releases.
class Version implements Comparable<Version> {
  Version(this.parts);

  final List<int> parts;

  /// Null when [text] doesn't start with a number (after an optional v).
  static Version? tryParse(String? text) {
    final match = RegExp(r'^\s*[vV]?(\d+(?:\.\d+)*)').firstMatch(text ?? '');
    if (match == null) return null;
    return Version(match.group(1)!.split('.').map(int.parse).toList());
  }

  @override
  int compareTo(Version other) {
    // Missing parts count as 0, so 1.0 and 1.0.0 are the same version.
    final length = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  bool operator <(Version other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(parts.reversed.skipWhile((p) => p == 0));

  @override
  String toString() => parts.join('.');
}
