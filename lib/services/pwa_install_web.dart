import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS()
extension type _InstallWindow(web.Window _window) implements web.Window {
  external JSBoolean isStandalonePwa();
  external JSBoolean canPromptInstall();
  external void triggerInstallPrompt();
}

bool get isStandalonePwa => _InstallWindow(web.window).isStandalonePwa().toDart;

bool get canPromptInstall =>
    _InstallWindow(web.window).canPromptInstall().toDart;

void triggerInstallPrompt() =>
    _InstallWindow(web.window).triggerInstallPrompt();
