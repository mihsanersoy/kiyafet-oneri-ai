import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

/// OptiWear Güvenli HTTP İstemcisi (Dio + JWT Auto-Refresh Interceptor)
class ApiClient {
  final SecureStorageService storage;
  late final Dio dio;

  /// Canlı Kurumsal Bulut Sunucusu (Render HTTPS):
  /// APK'yı indiren tüm cihazlar ve emülatörler doğrudan 7/24 çalışan canlı sunucuya bağlanır.
  static const String kProductionBaseUrl = 'https://kiyafet-oneri-ai.onrender.com';

  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('OPTIWEAR_API_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    return kProductionBaseUrl;
  }

  /// Render Free Tier uykudan uyanma (cold start ~25-40 sn) durumuna karşı
  /// connectTimeout ve receiveTimeout süreleri kurumsal toleransla ayarlandı.
  ApiClient({required this.storage, String? baseUrl}) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? defaultBaseUrl,
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
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
