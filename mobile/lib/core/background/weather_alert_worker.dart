import 'dart:async';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../notifications/local_notification_service.dart';

class WeatherAlertWorker {
  static Timer? _periodicTimer;

  static Future<void> checkNow({
    required String city,
    String district = '',
  }) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: ApiClient.defaultBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));

      final res = await dio.get(
        '/weather/hourly-alert',
        queryParameters: {'sehir': city, 'ilce': district},
      );

      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['uyari_var_mi'] == true) {
        await LocalNotificationService.instance.showWeatherShiftAlert(
          title: 'OptiWear • Ani Hava Değişimi Uyarısı',
          body: LocalNotificationService.kGeneralWeatherShiftWarning,
        );
      }
    } catch (_) {}
  }

  static Future<void> initializeAndSchedule({
    String city = 'İstanbul',
    String district = '',
  }) async {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(hours: 3),
      (_) => checkNow(city: city, district: district),
    );
  }
}
