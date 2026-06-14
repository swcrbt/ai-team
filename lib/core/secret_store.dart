import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecretStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class FlutterSecretStore implements SecretStore {
  FlutterSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: _storageKey(key), value: value);
  }

  @override
  Future<String?> read(String key) {
    return _storage.read(key: _storageKey(key));
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: _storageKey(key));
  }
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

String _storageKey(String key) => 'ai_team.model.$key.api_key';
