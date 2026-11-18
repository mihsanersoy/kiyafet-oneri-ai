import '../../core/network/api_client.dart';

class RoutineService {
  final ApiClient apiClient;

  RoutineService({required this.apiClient});

  /// GET /routines/me
  Future<Map<String, dynamic>> getMyRoutine() async {
    final res = await apiClient.dio.get('/routines/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// PUT /routines/me
  Future<Map<String, dynamic>> updateRoutine({
    required String wakeUpTime,
    required String sehir,
    String? ilce,
    required double boy,
    required double kilo,
    required String terlemeEgilimi,
    required bool notificationEnabled,
    String? fcmToken,
  }) async {
    final res = await apiClient.dio.put(
      '/routines/me',
      data: {
        'wake_up_time': wakeUpTime,
        'sehir': sehir,
        'ilce': ilce ?? '',
        'boy': boy,
        'kilo': kilo,
        'terleme_egilimi': terlemeEgilimi,
        'notification_enabled': notificationEnabled,
        if (fcmToken != null) 'fcm_token': fcmToken,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// POST /routines/me/morning-brief
  Future<Map<String, dynamic>> triggerMorningBrief() async {
    final res = await apiClient.dio.post('/routines/me/morning-brief');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// GET /routines/custom
  Future<List<Map<String, dynamic>>> getCustomRoutines() async {
    final res = await apiClient.dio.get('/routines/custom');
    final list = res.data as List;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// POST /routines/custom
  Future<Map<String, dynamic>> createCustomRoutine({
    required String routineTitle,
    required String routineTime,
    required String daysOfWeek,
  }) async {
    final res = await apiClient.dio.post(
      '/routines/custom',
      data: {
        'routine_title': routineTitle,
        'routine_time': routineTime,
        'days_of_week': daysOfWeek,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// DELETE /routines/custom/{id}
  Future<void> deleteCustomRoutine(int routineId) async {
    await apiClient.dio.delete('/routines/custom/$routineId');
  }

  /// PATCH /routines/custom/{id}/toggle
  Future<Map<String, dynamic>> toggleCustomRoutine({
    required int routineId,
    required bool isEnabled,
  }) async {
    final res = await apiClient.dio.patch(
      '/routines/custom/$routineId/toggle',
      queryParameters: {'is_enabled': isEnabled},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// GET /weather/current (Yapay Zekasız - Hızlı Hava Durumu Arama)
  Future<Map<String, dynamic>> fetchQuickWeather({
    required String sehir,
    String? ilce,
  }) async {
    final res = await apiClient.dio.get(
      '/weather/current',
      queryParameters: {
        'sehir': sehir.trim(),
        if (ilce != null && ilce.trim().isNotEmpty) 'ilce': ilce.trim(),
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// GET /weather/hourly-alert (Saatlik 8°C Fark ve Ani Hava Olayı Kontrolü)
  Future<Map<String, dynamic>> checkHourlyWeatherShift({
    required String sehir,
    String? ilce,
  }) async {
    final res = await apiClient.dio.get(
      '/weather/hourly-alert',
      queryParameters: {
        'sehir': sehir.trim(),
        if (ilce != null && ilce.trim().isNotEmpty) 'ilce': ilce.trim(),
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// POST /recommendation/travel (Seyahat / Bavul Hazırlama Modu)
  Future<Map<String, dynamic>> getTravelPackingRecommendation({
    required String hedefSehir,
    String? hedefIlce,
    required String baslangicTarihi,
    required String bitisTarihi,
    required double boy,
    required double kilo,
    required String terlemeEgilimi,
  }) async {
    final res = await apiClient.dio.post(
      '/recommendation/travel',
      data: {
        'hedef_sehir': hedefSehir.trim(),
        'hedef_ilce': (hedefIlce ?? '').trim(),
        'baslangic_tarihi': baslangicTarihi.trim(),
        'bitis_tarihi': bitisTarihi.trim(),
        'boy': boy,
        'kilo': kilo,
        'terleme_egilimi': terlemeEgilimi,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}
