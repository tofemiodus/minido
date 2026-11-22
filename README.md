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
