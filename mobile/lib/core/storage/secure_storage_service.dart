import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// OptiWear Güvenli Cihaz İçi Token Saklama Servisi
/// - Android: Donanım destekli EncryptedSharedPreferences (AES-256-GCM + Android Keystore)
/// - iOS: Keychain Services (first_unlock_this_device)
class SecureStorageService {
  static const _keyAccessToken = 'optiwear_access_token';
  static const _keyRefreshToken = 'optiwear_refresh_token';
  static const _keyUserEmail = 'optiwear_user_email';
  static const _keyUserFullName = 'optiwear_user_full_name';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    String? email,
    String? fullName,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    if (email != null) {
      await _storage.write(key: _keyUserEmail, value: email);
    }
    if (fullName != null) {
      await _storage.write(key: _keyUserFullName, value: fullName);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<String?> getUserFullName() => _storage.read(key: _keyUserFullName);

  Future<void> clearSession() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserEmail);
    await _storage.delete(key: _keyUserFullName);
  }
}
