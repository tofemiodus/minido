# Minido

Minido is an offline-first personal to-do app built with Flutter 3.50 and Dart
3.14. Tasks, subtasks, and the light/dark theme are stored locally with
`SharedPreferencesAsync`—on device/desktop preferences or browser local storage.
The app has no account, cloud sync, or backend service.

## Features

- Smart quick-add supports `!high`, `!med`/`!medium`, `!low`, `#tags`, `today`,
  and `tomorrow`; `/` focuses the quick-add field.
- List and three-column Kanban views, search, priority and tag filters,
  completion undo, and task editing with notes and subtasks.
- First launch includes removable sample tasks.
- JSON backup can be copied, downloaded in a browser, or shared/saved through
  the native platform share sheet. Backups can be restored by pasting JSON or
  choosing a `.json` file.
- Today Focus pins up to three tasks; one-tap snooze and undo make due-date
  changes easy to recover, with selectable offline reminder timing and due-time
  alerts on Android, iOS, and macOS.

## Download and run

Download the package for your device from the
[latest release](https://github.com/tofemiodus/minido/releases/latest).

- **Android:** Download `Minido-Android.apk` for a straightforward install on
  modern phones. Open the downloaded APK and confirm Install. Some
  browsers or Android settings may ask you to allow installs from that app;
  allow it only for the browser or file manager used to open the APK. Before
  reinstalling a newer release, export a JSON backup; this build uses debug
  signing, so Android may require removing the old app before installing the
  new one. `Minido-Android.aab` is for app-store publishing, not direct
  installation.
- **Windows 10/11 (x64):** Download `Minido-Windows-x64.zip`, open it in File
  Explorer, select **Extract All**, then open the extracted folder and
  double-click `minido.exe`. Keep the included `data` folder and DLL files
  beside the executable.
- **Web/PWA:** Open the hosted Minido website over HTTPS and use the browser's
  **Install** option or Minido's **Add to Home Screen** guide.
  `Minido-PWA-Web.zip` is for publishing Minido to a web host; it is not a desktop
  installer and cannot be launched by opening `index.html` directly.
- **Linux (Debian/Ubuntu):** Download `minido_amd64.deb` and open it with your
  software installer. On Fedora-compatible systems, use `minido-x86_64.rpm`.
  `Minido-Linux-x64.tar.gz` is the portable Linux bundle. Arch users can use
  the included `PKGBUILD` with an AUR/package helper.
- **macOS:** Download `Minido-macOS.zip`, open it, then move `Minido.app` to
  Applications. macOS may ask you to confirm opening an app downloaded from
  the internet. This build targets the architecture of the macOS release
  runner; it is not advertised as a universal binary.
- **iPhone/iPad:** `Minido-iOS-unsigned.ipa` is for users who already use an
  iOS sideloading tool such as AltStore or SideStore. It is unsigned and is not
  a normal App Store install; sideloading requires Apple device signing and
  periodic re-signing.

Tasks are stored locally on the device or in that browser's storage; there is
no account or cloud sync. Use **Export JSON** in the app to back up or move
tasks between devices or browser addresses.

### Install the Web app

Open the Web app over HTTPS or from `http://localhost`. Minido shows a
dismissible install banner when the browser supports installation; Chromium
offers a one-tap install button, while iPhone/iPad Safari shows the **Share →
Add to Home Screen** hint. Choose **How?** for the step-by-step guide, or
**Install on Other Devices** in an installed app. JSON Export and Smart Merge
can transfer tasks between the browser and installed app.

## Run and validate

```shell
flutter pub get
flutter run
flutter test
flutter analyze
flutter build web --wasm
```

Backups use schema version `1` and contain the task list and theme mode. The app
validates the full structure before replacing local data.

## Project structure

```text
lib/
  main.dart                 App entry point and application state
  data/                     Persistence implementations
  models/                   Task models and backup parsing
  services/                 Platform-specific backup operations
  src/dialogs/              Task and import dialogs
  src/views/                List, Kanban, cancelled, and statistics views
test/
  widget_test.dart          Parsing, backup, and widget coverage
```
