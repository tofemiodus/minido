import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS()
extension type _InstallWindow(web.Window _window) implements web.Window {
  external JSBoolean isStandalonePwa();
  external JSBoolean canPromptInstall();
  external JSBoolean isIosSafari();
  external JSPromise<JSBoolean> persistStorage();
  external void triggerInstallPrompt();
}

bool get isStandalonePwa => _InstallWindow(web.window).isStandalonePwa().toDart;

bool get canPromptInstall =>
    _InstallWindow(web.window).canPromptInstall().toDart;

bool get isIosSafari => _InstallWindow(web.window).isIosSafari().toDart;

Future<bool> persistStorage() async =>
    (await _InstallWindow(web.window).persistStorage().toDart).toDart;

void triggerInstallPrompt() =>
    _InstallWindow(web.window).triggerInstallPrompt();

void Function() listenForInstallPrompt(void Function() callback) {
  final listener = ((web.Event _) => callback()).toJS;
  web.window.addEventListener('minido-install-prompt-available', listener);
  return () => web.window.removeEventListener(
    'minido-install-prompt-available',
    listener,
  );
}
