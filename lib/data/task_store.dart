import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TaskStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesTaskStore implements TaskStore {
  SharedPreferencesTaskStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _storageKey = 'minido.backup.v1';
  static const _snapshotPrefix = 'minido.backup.snapshot.';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(_storageKey);

  @override
  Future<void> write(String value) async {
    await _preferences.setString(_storageKey, value);
    await _rotateSnapshots(value);
  }

  Future<void> _rotateSnapshots(String current) async {
    final s0 = await _preferences.getString('${_snapshotPrefix}0');
    final s1 = await _preferences.getString('${_snapshotPrefix}1');
    if (s1 != null) {
      await _preferences.setString('${_snapshotPrefix}2', s1);
    }
    if (s0 != null) {
      await _preferences.setString('${_snapshotPrefix}1', s0);
    }
    await _preferences.setString('${_snapshotPrefix}0', current);
  }
}

class MemoryTaskStore implements TaskStore {
  MemoryTaskStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
