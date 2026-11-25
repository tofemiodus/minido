bool get isStandalonePwa => false;

bool get canPromptInstall => false;

bool get isIosSafari => false;

Future<bool> persistStorage() async => false;

void triggerInstallPrompt() {}

void Function() listenForInstallPrompt(void Function() callback) => () {};
