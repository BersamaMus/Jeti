# Jeti

The launcher that installs and updates BersamaMus apps on Windows. Built with Flutter.

```sh
flutter run -d windows                                            # against bersamamus.com/apps.json
flutter run -d windows --dart-entrypoint-args=--catalog=C:\BersamaMusWebsite\dist\apps.json
flutter test
powershell -File installer\build_installer.ps1                    # build\installer\Jeti-Setup-<version>.exe
dart run tool/make_icon.dart                                      # redraws the icon
```

## How it knows what's outdated

- **Which apps:** `bersamamus.com/apps.json`, which the website builds from every
  project with a `windows:` block (see the website's README). A new app needs no
  new Jeti. The last copy is saved, for when the site can't be reached.
- **What's newest:** each app's latest GitHub release (`/releases/latest`, so
  pre-releases are skipped), and the installer named in the catalog in it.
- **What's installed:** the version Inno Setup recorded under
  `Uninstall\{AppId}_is1`, in this user's registry or the machine's.

Install and Update download the installer, check it against the SHA-256 GitHub
lists for it, close the app if it's open (asking first, and reopening it after)
and run it silently, for just this user or for everyone, as it was before.

## Releasing

1. Raise `version` in `pubspec.yaml`.
2. Run `installer\build_installer.ps1`.
3. Make a release on [BersamaMus/Jeti](https://github.com/BersamaMus/Jeti) tagged
   `v<version>` and attach the installer renamed to `Jeti-Setup.exe`. Every
   installed Jeti then offers to update itself.

The apps release the same way: tag `v<version>`, attach `<App>-Setup.exe`.
