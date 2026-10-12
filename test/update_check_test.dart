import 'package:flutter_test/flutter_test.dart';
import 'package:jeti/services/apps_controller.dart';
import 'package:jeti/services/catalog.dart';
import 'package:jeti/services/installed.dart';
import 'package:jeti/services/releases.dart';
import 'package:jeti/services/version.dart';

void main() {
  group('Version', () {
    Version v(String s) => Version.tryParse(s)!;

    test('reads release tags and registry versions', () {
      expect(v('v1.0.1').toString(), '1.0.1');
      expect(v('1.0.0').toString(), '1.0.0');
      expect(v('v1.0.0-rc1').toString(), '1.0.0');
      expect(Version.tryParse('latest'), isNull);
      expect(Version.tryParse(null), isNull);
    });

    test('compares number by number, not as text', () {
      expect(v('1.0.0') < v('1.0.1'), isTrue);
      expect(v('1.9.0') < v('1.10.0'), isTrue);
      expect(v('2.0') < v('1.99.99'), isFalse);
      expect(v('1.0'), v('1.0.0'));
    });
  });

  group('parseRelease', () {
    final json = {
      'tag_name': 'v1.0.1',
      'body': 'Fixes.',
      'html_url': 'https://github.com/BersamaMus/Blimp/releases/tag/v1.0.1',
      'assets': [
        {
          'name': 'Blimp-Setup.exe',
          'browser_download_url': 'https://github.com/BersamaMus/Blimp/releases/download/v1.0.1/Blimp-Setup.exe',
          'size': 17427361,
          'digest': 'sha256:CD03C3D1148908EDF8E3E7531BA509E41E60C48A3595315FBB0BE048847C554A',
        },
      ],
    };

    test('finds the installer and its hash', () {
      final release = parseRelease(json, 'blimp-setup.exe');
      expect(release.version.toString(), '1.0.1');
      expect(release.size, 17427361);
      expect(release.sha256, 'cd03c3d1148908edf8e3e7531ba509e41e60c48a3595315fbb0be048847c554a');
    });

    test('says so when the installer is missing', () {
      expect(() => parseRelease(json, 'Vessel-Setup.exe'), throwsA(isA<ReleaseException>()));
    });
  });

  group('AppEntry.status', () {
    AppEntry entry({String? installed, String? latest}) {
      final e = AppEntry(
        CatalogApp(
          id: 'blimp',
          title: 'Blimp',
          tagline: '',
          icon: null,
          page: null,
          repo: 'BersamaMus/Blimp',
          appId: 'X',
          installer: 'Blimp-Setup.exe',
          exe: 'blimp.exe',
        ),
      );
      if (installed != null) {
        e.installed = InstalledApp(
          version: Version.tryParse(installed),
          folder: r'C:\Apps\Blimp\',
          allUsers: false,
          uninstallCommand: null,
        );
      }
      if (latest != null) {
        e.latest = parseRelease({
          'tag_name': latest,
          'html_url': 'https://example.com',
          'assets': [
            {'name': 'Blimp-Setup.exe', 'browser_download_url': 'https://example.com/s.exe'},
          ],
        }, 'Blimp-Setup.exe');
      }
      return e;
    }

    test('an older install has an update', () {
      expect(entry(installed: '1.0.0', latest: 'v1.0.1').status, AppStatus.updateAvailable);
    });

    test('the latest install, or a newer one, is up to date', () {
      expect(entry(installed: '1.0.1', latest: 'v1.0.1').status, AppStatus.upToDate);
      expect(entry(installed: '1.1.0', latest: 'v1.0.1').status, AppStatus.upToDate);
    });

    test('an app that isn\'t installed can be installed', () {
      expect(entry(latest: 'v1.0.1').status, AppStatus.notInstalled);
    });

    test('finds the exe in the install folder', () {
      expect(entry(installed: '1.0.0').exePath, r'C:\Apps\Blimp\blimp.exe');
    });
  });
}
