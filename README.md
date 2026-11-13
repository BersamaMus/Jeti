# Jeti

The launcher that installs and updates BersamaMus apps on Windows and Android. Built with Flutter.

```sh
flutter run -d windows                                            # against bersamamus.com/apps.json
flutter run -d windows --dart-entrypoint-args=--catalog=C:\BersamaMusWebsite\dist\apps.json
flutter run -d emulator-5554 --dart-define=JETI_CATALOG=http://10.0.2.2:4321/apps.json   # the site's npm run dev
flutter test
powershell -File installer\build_installer.ps1                    # build\installer\Jeti-Setup-<version>.exe
flutter build apk --release                                       # build\app\outputs\flutter-apk\app-release.apk
dart run tool/make_icon.dart                                      # redraws the icon, Windows and Android
```

Everything that differs between the two is in `lib/services/windows_host.dart` and
`lib/services/android_host.dart` (with `MainActivity.kt` for the Android calls
Flutter doesn't have).

## How it knows what's outdated

- **Which apps:** `bersamamus.com/apps.json`, which the website builds from every
  project with a `windows:` block (the `apps` list) or an `android:` block (the
  `android` list; see the website's README). A new app needs no new Jeti. The
  last copy is saved, for when the site can't be reached.
- **What's newest:** each app's latest GitHub release (`/releases/latest`, so
  pre-releases are skipped), and the installer or APK named in the catalog in it.
- **What's installed:** on Windows, the version Inno Setup recorded under
  `Uninstall\{AppId}_is1`, in this user's registry or the machine's. On Android,
  the versionName of the app's `package`.

On Windows, Install and Update download the installer, check it against the
SHA-256 GitHub lists for it, close the app if it's open (asking first, and
reopening it after) and run it silently, for just this user or for everyone, as
it was before.

On Android they download the APK (checked the same way) and hand it to Android's
package installer, which asks the person to confirm. The first time, Android
also asks them to let Jeti install apps; Jeti explains and opens that setting.
On Android 12 and up, apps Jeti installed then update without asking again.
Jeti 1.0 for Windows only reads the `apps` list, so the `android` list doesn't
disturb it.

## Releasing

1. Raise `version` in `pubspec.yaml`, both the name and the number after the `+`
   (Android won't install a build whose number isn't higher).
2. Run `installer\build_installer.ps1` and `flutter build apk --release`.
3. Make a release on [BersamaMus/Jeti](https://github.com/BersamaMus/Jeti) tagged
   `v<version>` and attach the installer renamed to `Jeti-Setup.exe` and the APK
   renamed to `Jeti.apk`. Every installed Jeti then offers to update itself, and
   the website's download buttons point at them.

The APK is signed with the key `android/key.properties` describes (not in git),
`C:\Users\musta\jeti-release.jks`. **Keep a backup of both.** An APK signed with
any other key can't update an installed Jeti; people would have to uninstall it
first. Without `key.properties`, release builds are signed with the debug key,
which is fine for trying them out but must not be published.

The apps release the same way: tag `v<version>`, attach `<App>-Setup.exe` and,
for an Android app, its APK.
