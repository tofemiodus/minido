import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS()
extension type _InstallWindow(web.Window _window) implements web.Window {
  external JSBoolean isStandalonePwa();
  external JSBoolean canPromptInstall();
  external JSBoolean isIosSafari();
  external JSPromise<JSBoolean> persistStorage();
  external JSPromise<JSString> minidoPromptInstall();
}

bool get isStandalonePwa => _InstallWindow(web.window).isStandalonePwa().toDart;

bool get canPromptInstall =>
    _InstallWindow(web.window).canPromptInstall().toDart;

bool get isIosSafari => _InstallWindow(web.window).isIosSafari().toDart;

Future<bool> persistStorage() async =>
    (await _InstallWindow(web.window).persistStorage().toDart).toDart;

Future<String> minidoPromptInstall() async =>
    (await _InstallWindow(web.window).minidoPromptInstall().toDart).toDart;

void Function() listenForInstallPrompt(void Function(String) callback) {
  final listener = ((web.Event event) => callback(event.type)).toJS;
  web.window.addEventListener('minido-install-available', listener);
  web.window.addEventListener('minido-app-installed', listener);
  return () {
    web.window.removeEventListener('minido-install-available', listener);
    web.window.removeEventListener('minido-app-installed', listener);
  };
}
