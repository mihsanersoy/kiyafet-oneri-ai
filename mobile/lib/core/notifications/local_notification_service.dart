import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  static final LocalNotificationService instance = LocalNotificationService._();
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    // Android 13+ (API 33+) için bildirim ve tam zamanlı alarm izinlerini otomatik iste
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Rutin saatinden tam 10 dakika önce (Örn: 08:00 -> 07:50) özel ses efektiyle
  /// (routine_alert) zonedSchedule bildirimi kurar.
  Future<void> scheduleRoutineBefore10Min({
    required int routineId,
    required String routineTitle,
    required String routineTimeHhMm,
  }) async {
    await init();

    final parts = routineTimeHhMm.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final now = tz.TZDateTime.now(tz.local);
    var targetTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(const Duration(minutes: 10));

    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'optiwear_routine_sound_v2',
      'OptiWear Rutin Bildirimleri',
      channelDescription: 'Rutin saatinden 10 dakika önce özel sesli giyim uyarısı verir',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('routine_alert'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'routine_alert.mp3',
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      routineId,
      'OptiWear • $routineTitle ($routineTimeHhMm)',
      'Rutinin yaklaşıyor, dışarısı serin iyi giyindiğinden emin ol.',
      targetTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// 0 Saniye Gecikmeyle Anında Rutin Bildirim ve Ses Testi
  Future<void> triggerInstantRoutineTestNotification() async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'optiwear_routine_sound_v2',
      'OptiWear Rutin Bildirimleri',
      channelDescription: 'Rutin saatinden 10 dakika önce özel sesli giyim uyarısı verir',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('routine_alert'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'routine_alert.mp3',
    );

    await _plugin.show(
      99000,
      'OptiWear • Rutin Bildirim Testi',
      'Rutinin yaklaşıyor, dışarısı serin iyi giyindiğinden emin ol.',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// 0 Saniye Gecikmeyle Anında Ani Hava Değişimi Bildirim ve Ses Testi (weather_shift_alert)
  Future<void> showWeatherShiftAlert({
    required String title,
    required String body,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'optiwear_weather_shift_sound_v2',
      'OptiWear Ani Hava Değişimi Uyarıları',
      channelDescription: 'Gün içinde 8°C üstü sıcaklık farkı ve ani yağış uyarıları',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('weather_shift_alert'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'weather_shift_alert.mp3',
    );

    await _plugin.show(
      99001,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> cancelRoutineNotification(int routineId) async {
    await init();
    await _plugin.cancel(routineId);
  }
}
