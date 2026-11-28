import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// OptiWear Güvenli Cihaz İçi Token Saklama Servisi
/// - Android: Donanım destekli EncryptedSharedPreferences (AES-256-GCM + Android Keystore)
/// - iOS: Keychain Services (first_unlock_this_device)
class SecureStorageService {
  static const _keyAccessToken = 'optiwear_access_token';
  static const _keyRefreshToken = 'optiwear_refresh_token';
  static const _keyUserEmail = 'optiwear_user_email';
  static const _keyUserFullName = 'optiwear_user_full_name';
  static const _keyOnboardingPrefix = 'optiwear_onboarding_completed_';
  static const _keyCustomApiBaseUrl = 'optiwear_custom_api_base_url';

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

  String _normalizeUserKey(String userIdentifier) {
    final cleaned = userIdentifier.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_@.-]'),
          '_',
        );
    return '$_keyOnboardingPrefix${cleaned.isEmpty ? "default" : cleaned}';
  }

  /// Kullanıcı bazlı tanıtım eğitimi (onboarding) tamamlandı/atlandı kontrolü
  Future<bool> hasCompletedOnboarding(String userIdentifier) async {
    final val = await _storage.read(key: _normalizeUserKey(userIdentifier));
    return val == 'true';
  }

  /// Kullanıcı bazlı tanıtım eğitimi (onboarding) durumunu kalıcı olarak günceller
  Future<void> setOnboardingCompleted(
    String userIdentifier, {
    bool completed = true,
  }) async {
    final key = _normalizeUserKey(userIdentifier);
    if (completed) {
      await _storage.write(key: key, value: 'true');
    } else {
      await _storage.delete(key: key);
    }
  }

  /// İsteğe bağlı özel/bulut sunucu adresi saklama
  Future<String?> getCustomApiBaseUrl() =>
      _storage.read(key: _keyCustomApiBaseUrl);

  Future<void> setCustomApiBaseUrl(String? url) async {
    final cleaned = (url ?? '').trim();
    if (cleaned.isEmpty) {
      await _storage.delete(key: _keyCustomApiBaseUrl);
    } else {
      await _storage.write(key: _keyCustomApiBaseUrl, value: cleaned);
    }
  }
}
