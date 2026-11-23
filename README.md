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

## Download and run

Download the Android, Windows, or Web package from the
[latest release](https://github.com/tofemiodus/minido/releases/latest).

- **Android:** Download `app-arm64-v8a-release.apk` for virtually every modern
  phone (2018 and newer). Open the downloaded APK and confirm Install. Some
  browsers or Android settings may ask you to allow installs from that app;
  allow it only for the browser or file manager used to open the APK. Android
  updates with a Minido package use the same file and package name.
- **Android older ARM devices:** Download `app-armeabi-v7a-release.apk`.
- **Android emulators / x86 devices:** Download `app-x86_64-release.apk`.
- **Windows 10/11 (x64):** Download and extract the Windows x64 ZIP, then run
  `minido.exe` from the extracted folder. Keep the included `data`
  folder and DLL files beside the executable.
- **Web:** Download and extract the Web ZIP. From the extracted folder, run
  `python -m http.server 8000`, then open
  `http://localhost:8000` in a modern browser. Serve the folder over HTTP;
  opening `index.html` directly as a file is not supported.

Tasks are stored locally on the device or in that browser's storage; there is
no account or cloud sync. Use **Export JSON** in the app to back up or move
tasks between devices or browser addresses.

### Install the Web app

Open the Web app over HTTPS or from `http://localhost`, then choose **Install
App** from the overflow menu. If the browser does not offer a native install
prompt, follow the in-app steps: Safari on iOS uses **Share → Add to Home
Screen**; Chrome on Android uses **Install app** or **Add to home screen**;
desktop browsers use the install icon in the address bar. JSON Export and
Smart Merge can transfer tasks between the browser and installed app.

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
