import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

/// OptiWear Güvenli HTTP İstemcisi (Dio + JWT Auto-Refresh Interceptor)
class ApiClient {
  final SecureStorageService storage;
  late final Dio dio;

  /// Android Emülatör için 10.0.2.2:8001 (ana bilgisayarın localhost'u),
  /// diğer platformlar için 127.0.0.1:8001
  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('OPTIWEAR_API_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8001';
      }
    } catch (_) {}
    return 'http://127.0.0.1:8001';
  }

  void updateBaseUrl(String newUrl) {
    final cleaned = newUrl.trim();
    if (cleaned.isNotEmpty) {
      dio.options.baseUrl = cleaned;
    }
  }

  ApiClient({required this.storage, String? baseUrl}) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? defaultBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final isAuthEndpoint = error.requestOptions.path.startsWith('/auth/login') ||
              error.requestOptions.path.startsWith('/auth/register') ||
              error.requestOptions.path.startsWith('/auth/refresh');

          if (error.response?.statusCode == 401 && !isAuthEndpoint) {
            final refreshToken = await storage.getRefreshToken();
            if (refreshToken != null && refreshToken.isNotEmpty) {
              try {
                final refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
                final res = await refreshDio.post(
                  '/auth/refresh',
                  data: {'refresh_token': refreshToken},
                );

                final newAccess = res.data['access_token'] as String;
                final newRefresh = res.data['refresh_token'] as String;
                await storage.saveSession(
                  accessToken: newAccess,
                  refreshToken: newRefresh,
                );

                error.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
                final clonedResponse = await dio.fetch(error.requestOptions);
                return handler.resolve(clonedResponse);
              } catch (_) {
                await storage.clearSession();
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }
}
