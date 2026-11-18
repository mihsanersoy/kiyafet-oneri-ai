import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  static final LocalNotificationService instance = LocalNotificationService._();
  LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Random _random = Random();
  bool _initialized = false;

  /// Kamusal / Kurumsal Uygulama Standartlarında (08:00 - 22:00) Zengin Mesaj Havuzu
  static const List<Map<String, String>> _smartEngagementPool = [
    {
      'title': '🌤️ Öğle Saatleri Yaklaşıyor!',
      'body': 'Sıcaklık gün içi zirvesine doğru çıkıyor. Kalın giyindiysen terlememek için dış katmanını hafifletmeyi unutma!',
    },
    {
      'title': '🧥 Akşamüstü Serinliği Başlıyor',
      'body': 'Güneş etkisini kaybederken hissedilen sıcaklık düşüyor. Dışarıdaysan rüzgarlığını veya üst katmanını hazır tut.',
    },
    {
      'title': '🧠 Bugün Termal Konforun Nasıldı?',
      'body': 'Bugünkü kıyafetlerinle terledin mi yoksa üşüdün mü? OptiWear hafızana 1 cümle ekle, yarın çok daha nokta atışı önerelim!',
    },
    {
      'title': '✨ Yarının Kombinini Şimdiden Planla',
      'body': 'Sabah dolap karşısında vakit kaybetme! Yarının hava olayına ve VKE profiline uygun kombinin OptiWear\'da hazır.',
    },
    {
      'title': '🌬️ Rüzgar ve Hissedilen Sıcaklık Kontrolü',
      'body': 'Termometreye aldanma! Rüzgar hızı hissedilen sıcaklığı değiştirebilir, dışarı çıkmadan önce OptiWear\'a göz at.',
    },
    {
      'title': '🧳 Hafta Sonu veya Seyahat Planın Var mı?',
      'body': 'Gideceğin şehrin çok günlük hava tahminine göre yapay zeka destekli bavul listeni saniyeler içinde oluşturabilirsin.',
    },
  ];

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
    _initialized = true;
  }

  /// 1. Kullanıcının Rutin Saatinden Tam 10 Dakika Önce (Örn: 08:00 -> 07:50)
  /// Özel Ses Efektiyle (routine_alert) Tetiklenen Bildirim
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
      'optiwear_routine_channel',
      'OptiWear Günlük Rutin Bildirimleri',
      channelDescription: 'Rutin saatinden 10 dakika önce sesli giyim uyarısı verir',
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

  /// 2. Workmanager Ani Hava Değişimi Uyarısı (8°C fark veya ani yağış)
  /// Özel Ses Efektiyle (weather_shift_alert) Tetiklenen Bildirim
  Future<void> showWeatherShiftAlert({
    required String title,
    required String body,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'optiwear_weather_alert_channel',
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

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      99001,
      title,
      body,
      details,
    );
  }

  /// 3. Kamusal / Kurumsal Uygulama Standardında (08:00 - 22:00 Aralığında)
  /// Bildirim Körlüğünü Önleyen Rastgele (Jittered) Akıllı Hatırlatıcılar
  /// Gece 22:00 - Sabah 08:00 (Sessiz Saatler) arasında ASLA bildirim kurmaz.
  Future<List<String>> scheduleSmartDaytimeReminders({bool enabled = true}) async {
    await init();

    // Önceki rastgele hatırlatıcı ID'lerini (88001, 88002, 88003) temizle
    await _plugin.cancel(88001);
    await _plugin.cancel(88002);
    await _plugin.cancel(88003);

    if (!enabled) return [];

    // 08:00 - 22:00 arasını 3 doğal yaşam dilimine bölüp her dilimde rastgele saat:dakika seç:
    // 1. Kuşluk / Öğle Öncesi Dilimi: 09:00 - 12:59 arası
    // 2. Öğleden Sonra / Akşamüstü Çıkış Dilimi: 14:00 - 17:59 arası
    // 3. Akşam / Yarın Hazırlık Dilimi: 19:00 - 21:45 arası (22:00'ı asla geçmez)
    final slots = [
      {'id': 88001, 'minHour': 9, 'maxHour': 12},
      {'id': 88002, 'minHour': 14, 'maxHour': 17},
      {'id': 88003, 'minHour': 19, 'maxHour': 21},
    ];

    const androidDetails = AndroidNotificationDetails(
      'optiwear_smart_engagement_channel',
      'OptiWear Gün İçi Akıllı Hatırlatmalar (08:00-22:00)',
      channelDescription: '08:00 - 22:00 saatleri arasında rastgele zamanlarda giyim ve konfor ipuçları verir',
      importance: Importance.high,
      priority: Priority.defaultPriority,
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

    final now = tz.TZDateTime.now(tz.local);
    final shuffledMessages = List<Map<String, String>>.from(_smartEngagementPool)..shuffle(_random);
    final scheduledTimes = <String>[];

    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final id = slot['id']!;
      final minH = slot['minHour']!;
      final maxH = slot['maxHour']!;

      final randomHour = minH + _random.nextInt((maxH - minH) + 1);
      final maxMinute = (randomHour == 21) ? 45 : 59;
      final randomMinute = _random.nextInt(maxMinute + 1);

      var target = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        randomHour,
        randomMinute,
      );
      if (target.isBefore(now)) {
        target = target.add(const Duration(days: 1));
      }

      final msg = shuffledMessages[i % shuffledMessages.length];
      await _plugin.zonedSchedule(
        id,
        msg['title']!,
        msg['body']!,
        target,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      final hh = randomHour.toString().padLeft(2, '0');
      final mm = randomMinute.toString().padLeft(2, '0');
      scheduledTimes.add('$hh:$mm');
    }

    return scheduledTimes;
  }

  /// Kullanıcının rastgele hatırlatma bildirimini anında test edebilmesi için örnek tetikleyici
  Future<void> triggerRandomEngagementSampleNow() async {
    await init();
    final msg = _smartEngagementPool[_random.nextInt(_smartEngagementPool.length)];

    const androidDetails = AndroidNotificationDetails(
      'optiwear_smart_engagement_channel',
      'OptiWear Gün İçi Akıllı Hatırlatmalar (08:00-22:00)',
      channelDescription: '08:00 - 22:00 saatleri arasında rastgele zamanlarda giyim ve konfor ipuçları verir',
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
      88099,
      msg['title']!,
      msg['body']!,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> cancelRoutineNotification(int routineId) async {
    await init();
    await _plugin.cancel(routineId);
  }
}
