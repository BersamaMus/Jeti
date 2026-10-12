import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'releases.dart';

/// Why an install or update failed, worded for the person using Jeti.
class SetupException implements Exception {
  SetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads [release]'s installer into Jeti's temp folder as [fileName], and
/// checks it against the hash GitHub lists for it. [onProgress] gets 0 to 1.
Future<File> downloadInstaller(
  Release release,
  String fileName, {
  required void Function(double progress) onProgress,
}) async {
  final folder = Directory('${(await getTemporaryDirectory()).path}\\Jeti');
  await folder.create(recursive: true);
  final file = File('${folder.path}\\$fileName');

  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', release.downloadUrl));
    if (response.statusCode != 200) {
      throw SetupException('The download failed (HTTP ${response.statusCode})');
    }
    final total = response.contentLength ?? release.size;
    var received = 0;
    final sink = file.openWrite();
    final hashOutput = _DigestSink();
    final hasher = sha256.startChunkedConversion(hashOutput);
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
    } finally {
      await sink.close();
      hasher.close();
    }

    if (release.sha256 != null && hashOutput.value.toString() != release.sha256) {
      await file.delete().catchError((_) => file);
      throw SetupException("The download didn't match the release (it may have been damaged on the way). Try again.");
    }
    return file;
  } on SetupException {
    rethrow;
  } catch (_) {
    await file.delete().catchError((_) => file);
    throw SetupException("The download didn't finish. Check your connection and try again.");
  } finally {
    client.close();
  }
}

/// Runs an Inno Setup installer without its wizard and waits for it.
///
/// [allUsers] installs into Program Files for everyone, which Windows asks
/// for admin rights for; otherwise it goes into this user's folder, which
/// needs none. An update keeps the app where it already is.
Future<void> runInstaller(File setup, {required bool allUsers, List<String> extraArgs = const []}) async {
  final ProcessResult result;
  try {
    result = await Process.run(setup.path, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      // Closes whatever still has the app's files open (e.g. Vessel's
      // thumbnail workers), rather than failing.
      '/CLOSEAPPLICATIONS',
      allUsers ? '/ALLUSERS' : '/CURRENTUSER',
      ...extraArgs,
    ]);
  } on ProcessException {
    // Windows refuses to start it, e.g. when its admin prompt is declined.
    throw SetupException(allUsers ? 'It needs admin rights to update, which weren\'t given.' : "The installer couldn't start.");
  } finally {
    // The installer is only needed once.
    setup.delete().catchError((_) => setup);
  }
  // Inno Setup's exit codes: 0 done, 2 cancelled before installing, 5 cancelled
  // while installing; anything else is a failure.
  switch (result.exitCode) {
    case 0:
      return;
    case 2 || 5:
      throw SetupException('The installer was cancelled.');
    default:
      throw SetupException('The installer failed (code ${result.exitCode}).');
  }
}

/// Whether a program named [exe] is running.
Future<bool> isRunning(String exe) async {
  final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq $exe', '/FO', 'CSV', '/NH']);
  return (result.stdout as String).toLowerCase().contains('"${exe.toLowerCase()}"');
}

/// Closes every running [exe]. It's forced: Blimp only hides in the tray when
/// asked to close, and its installer won't update it while it's there.
Future<void> closeApp(String exe) async {
  await Process.run('taskkill', ['/F', '/IM', exe]);
  // Gives Windows a moment to let go of its files.
  for (var i = 0; i < 20 && await isRunning(exe); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

/// Opens [exePath] on its own, so it stays open whatever happens to Jeti.
Future<void> openApp(String exePath) async {
  await Process.start(exePath, [], mode: ProcessStartMode.detached, workingDirectory: File(exePath).parent.path);
}

/// Runs an uninstall command as Windows lists it, e.g. "C:\...\unins000.exe".
/// The uninstaller asks for confirmation itself.
Future<void> runUninstaller(String command) async {
  final match = RegExp(r'^\s*"([^"]+)"\s*(.*)$').firstMatch(command);
  final exe = match?.group(1) ?? command.trim();
  final args = (match?.group(2) ?? '').split(' ').where((a) => a.isNotEmpty).toList();
  await Process.start(exe, args, mode: ProcessStartMode.detached);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
