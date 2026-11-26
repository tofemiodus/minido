bool get isStandalonePwa => false;

bool get canPromptInstall => false;

bool get isIosSafari => false;

Future<bool> persistStorage() async => false;

Future<String> minidoPromptInstall() async => 'unavailable';

void Function() listenForInstallPrompt(void Function(String) callback) => () {};
