import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage_service.dart';

class AuthService {
  final ApiClient apiClient;
  final SecureStorageService storage;

  AuthService({required this.apiClient, required this.storage});

  /// POST /auth/register
  /// Kullanıcıyı kaydeder ve 6 haneli e-posta OTP doğrulama sürecini başlatır.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
  }) async {
    final res = await apiClient.dio.post(
      '/auth/register',
      data: {
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
        'phone_number': phoneNumber.trim(),
      },
    );

    return Map<String, dynamic>.from(res.data as Map);
  }

  /// POST /auth/verify-email
  /// 6 haneli OTP kodunu doğrular, is_verified=True yapar ve JWT token'ları güvenli depoya kaydeder.
  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String otpCode,
  }) async {
    final res = await apiClient.dio.post(
      '/auth/verify-email',
      data: {
        'email': email.trim(),
        'otp_code': otpCode.trim(),
      },
    );

    final data = Map<String, dynamic>.from(res.data as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);

    await storage.saveSession(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      email: user['email'] as String?,
      fullName: user['full_name'] as String?,
    );
    return user;
  }

  /// POST /auth/login
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await apiClient.dio.post(
      '/auth/login',
      data: {
        'email': email.trim(),
        'password': password,
      },
    );

    final data = Map<String, dynamic>.from(res.data as Map);
    final user = Map<String, dynamic>.from(data['user'] as Map);

    await storage.saveSession(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      email: user['email'] as String?,
      fullName: user['full_name'] as String?,
    );
    return user;
  }

  /// GET /auth/me
  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await apiClient.dio.get('/auth/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// PATCH /auth/account (Soft-Delete / Hesap Dondurma)
  Future<void> freezeAccount({required String password}) async {
    await apiClient.dio.patch(
      '/auth/account',
      data: {'password': password},
    );
    await storage.clearSession();
  }

  /// DELETE /auth/account (Kalıcı Silme)
  Future<void> deleteAccount({required String password}) async {
    await apiClient.dio.delete(
      '/auth/account',
      data: {'password': password},
    );
    await storage.clearSession();
  }

  Future<void> logout() async {
    await storage.clearSession();
  }
}
