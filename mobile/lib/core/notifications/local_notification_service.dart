import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  static final LocalNotificationService instance = LocalNotificationService._();
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String kGeneralWeatherShiftWarning =
      'Dikkat! Gün içinde ani hava ve sıcaklık değişimi bekleniyor. '
      'Dışarı çıkarken tedbirli ve katmanlı giyindiğinden emin ol.';

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

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Kullanıcının seçtiği dakika kadar önce (leadMinutes) gerçek sistem kombin
  /// yorumunun 3-4 cümlelik kısaltılmış haliyle ve özel sesle (routine_alert) bildirim kurar.
  Future<void> scheduleRoutineNotification({
    required int routineId,
    required String routineTitle,
    required String routineTimeHhMm,
    required int leadMinutes,
    required String systemCommentSummary,
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
    ).subtract(Duration(minutes: leadMinutes));

    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 1));
    }

    final androidDetails = AndroidNotificationDetails(
      'optiwear_routine_sound_v3',
      'OptiWear Rutin Bildirimleri',
      channelDescription: 'Rutin saatinden seçilen süre önce kişiselleştirilmiş kombin özetini bildirir',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('routine_alert'),
      styleInformation: BigTextStyleInformation(
        systemCommentSummary,
        contentTitle: 'OptiWear • $routineTitle ($routineTimeHhMm)',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'routine_alert.mp3',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      routineId,
      'OptiWear • $routineTitle ($routineTimeHhMm)',
      systemCommentSummary,
      targetTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// 0 Saniye Gecikmeyle Anında Gerçek Sistem Kombin Yorumunun 3-4 Cümlelik Özetiyle Bildirim Testi
  Future<void> triggerInstantRoutineTestNotification({
    required String systemCommentSummary,
  }) async {
    await init();

    final androidDetails = AndroidNotificationDetails(
      'optiwear_routine_sound_v3',
      'OptiWear Rutin Bildirimleri',
      channelDescription: 'Rutin saatinden seçilen süre önce kişiselleştirilmiş kombin özetini bildirir',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('routine_alert'),
      styleInformation: BigTextStyleInformation(
        systemCommentSummary,
        contentTitle: 'OptiWear • Kişisel Kombin Özeti',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'routine_alert.mp3',
    );

    await _plugin.show(
      99000,
      'OptiWear • Kişisel Kombin Özeti',
      systemCommentSummary,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Ani Hava Değişimi Uyarısı (Genel Geçer Uyarı Metni + weather_shift_alert Sesi)
  Future<void> showWeatherShiftAlert({
    String? title,
    String? body,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'optiwear_weather_shift_sound_v3',
      'OptiWear Ani Hava Değişimi Uyarıları',
      channelDescription: 'Gün içinde ani hava ve sıcaklık değişimi uyarıları',
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
      title ?? 'OptiWear • Ani Hava Değişimi Uyarısı',
      body ?? kGeneralWeatherShiftWarning,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> cancelRoutineNotification(int routineId) async {
    await init();
    await _plugin.cancel(routineId);
  }
}
