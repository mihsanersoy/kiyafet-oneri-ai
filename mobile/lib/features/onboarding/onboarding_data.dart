import 'package:flutter/material.dart';
import '../../core/theme/optiwear_theme.dart';

/// Her bir eğitim kartının önizleme türü
enum OnboardingPreviewType {
  // Bölüm 1: Kombin & Rutin
  outfitRecommendation,
  dailyRoutinesLeadTime,
  thermalMemoryInput,
  scenarioListManagement,

  // Bölüm 2: Seyahat Valizi
  multiDayTravelMode,
  travelDateRangeForecast,
  personalPackingStrategy,

  // Bölüm 3: Hava Durumu
  quickLocationSearch,
  feelsLikeAndSixCategories,
  liveWeatherBackground,
  abruptWeatherShiftAlert,

  // Bölüm 4: Profil & Hesap
  physicalProfileAndSweating,
  notificationAndRoutineControl,
  accountPrivacyAndControl,
}

/// Tek bir tanıtım kartının veri modeli.
/// İleride `assets/onboarding/` altına WebP görseli eklendiğinde `assetPath` otomatik yüklenir,
/// dosya yoksa mermer temaya uyumlu etkileşimsiz (`IgnorePointer`) mini ekran önizlemesi çizilir.
@immutable
class OnboardingCardData {
  final String title;
  final String description;
  final String semanticsLabel;
  final String assetPath;
  final OnboardingPreviewType previewType;

  const OnboardingCardData({
    required this.title,
    required this.description,
    required this.semanticsLabel,
    required this.assetPath,
    required this.previewType,
  });
}

/// Bir eğitim bölümünün (3-4 kartlık yatay akış) veri modeli.
/// Yeni bir bölüm veya kart eklemek için yalnızca `kOptiWearOnboardingSections` listesine öğe eklemek yeterlidir.
@immutable
class OnboardingSection {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<OnboardingCardData> cards;

  const OnboardingSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.cards,
  });
}

/// Uygulamadaki gerçek özelliklerle doğrulanmış 4 ana bölüm ve 14 bilgi kartı
const List<OnboardingSection> kOptiWearOnboardingSections = [
  // 1. BÖLÜM: KOMBİN & RUTİN
  OnboardingSection(
    id: 'outfit_and_routine',
    title: 'Kombin & Rutin',
    subtitle: 'Bedeninize ve günlük programınıza uyum sağlayan giyim rehberi',
    icon: Icons.checkroom_rounded,
    cards: [
      OnboardingCardData(
        title: 'Kişiselleştirilmiş Kombin Önerisi',
        description:
            'Boy, kilo, hareket halindeyken terleme eğiliminiz ve bulunduğunuz yerin hissedilen sıcaklığı birlikte değerlendirilir. Hava durumuna göre katmanlı giyim, şemsiye veya su geçirmez bot gibi ekipmanlar önerilir.',
        semanticsLabel:
            'Kombin önerisi önizlemesi: Konum, boy, kilo ve hissedilen sıcaklığa göre katmanlı giyim ve ekipman önerisi kartı.',
        assetPath: 'assets/onboarding/outfit_recommendation.webp',
        previewType: OnboardingPreviewType.outfitRecommendation,
      ),
      OnboardingCardData(
        title: 'Günlük Rutinler ve Zamanlı Bildirim',
        description:
            'Sabah uyanma veya işe gidiş gibi rutinlerinizi haftanın istediğiniz günleri için kurabilirsiniz. Seçtiğiniz dakika kadar önce (örneğin 10 veya 15 dakika önce) o günün kombin özeti bildirim olarak gelir.',
        semanticsLabel:
            'Rutinlerim önizlemesi: Sabah uyanma ve işe gidiş saatleri, gün seçimi ve bildirim süresi ayarları.',
        assetPath: 'assets/onboarding/daily_routines.webp',
        previewType: OnboardingPreviewType.dailyRoutinesLeadTime,
      ),
      OnboardingCardData(
        title: 'Termal Hafıza ile Kişisel Öğrenme',
        description:
            'Geçmişte hangi havada ne giyip üşüdüğünüzü veya terlediğinizi kısa bir cümleyle ekleyebilirsiniz. Sistem yeni öneriler hazırlarken bu deneyimlerinizi dikkate alarak aynı rahatsızlığı yaşamanızı önler.',
        semanticsLabel:
            'Termal Hafıza önizlemesi: Geçmiş giyim deneyimlerini ekleme kutusu ve hızlı örnek butonları.',
        assetPath: 'assets/onboarding/thermal_memory.webp',
        previewType: OnboardingPreviewType.thermalMemoryInput,
      ),
      OnboardingCardData(
        title: 'Senaryo Listesi ve Kolay Yönetim',
        description:
            'Kaydettiğiniz tüm geçmiş deneyimlerinizi tek listede görebilir, sola kaydırarak silebilir veya 5 saniye içinde geri alabilirsiniz. Kayıtlara uzun basarak birden fazla deneyimi tek seferde topluca silebilirsiniz.',
        semanticsLabel:
            'Senaryo Listesi önizlemesi: Kayıtlı deneyimler, göreli tarihler, geri al düğmesi ve toplu seçim görünümü.',
        assetPath: 'assets/onboarding/scenario_list.webp',
        previewType: OnboardingPreviewType.scenarioListManagement,
      ),
    ],
  ),

  // 2. BÖLÜM: SEYAHAT VALİZİ
  OnboardingSection(
    id: 'travel_packing',
    title: 'Seyahat Valizi',
    subtitle: 'Gideceğiniz şehrin çok günlük havasına göre bavul planlama',
    icon: Icons.luggage_rounded,
    cards: [
      OnboardingCardData(
        title: 'Çok Günlük Seyahat Modu',
        description:
            'Yurt içi veya yurt dışında gideceğiniz şehri ya da ilçeyi aratarak seyahat planınızı başlatabilirsiniz. Varsayılan konumunuzu değiştirmeden farklı rotalar için hazırlık yapabilirsiniz.',
        semanticsLabel:
            'Seyahat modu önizlemesi: Hedef şehir arama kutusu ve rota seçimi.',
        assetPath: 'assets/onboarding/travel_mode.webp',
        previewType: OnboardingPreviewType.multiDayTravelMode,
      ),
      OnboardingCardData(
        title: 'Tarih Aralığı Hava Tahmini',
        description:
            'Başlangıç ve bitiş tarihlerinizi seçtiğinizde seyahat günlerinizin en düşük, en yüksek sıcaklık ve rüzgar tahminleri listelenir. Hangi gün yağış veya rüzgar beklendiğini tek bakışta görebilirsiniz.',
        semanticsLabel:
            'Seyahat tarih aralığı önizlemesi: Günlük en düşük ve en yüksek sıcaklıklar ile hava durumu listesi.',
        assetPath: 'assets/onboarding/travel_forecast.webp',
        previewType: OnboardingPreviewType.travelDateRangeForecast,
      ),
      OnboardingCardData(
        title: 'Kişiye Özel Bavul ve Ekipman Listesi',
        description:
            'Fiziksel yapınıza ve gideceğiniz yerin günlük hava olaylarına uygun kıyafet ile ekipman listesi otomatik hazırlanır. Yanınıza almanız gereken yedek katmanları, ayakkabıyı ve aksesuarları eksiksiz planlarsınız.',
        semanticsLabel:
            'Valiz önerisi önizlemesi: Çok günlük katmanlı giyim ve ekipman tavsiyesi özeti.',
        assetPath: 'assets/onboarding/travel_packing_list.webp',
        previewType: OnboardingPreviewType.personalPackingStrategy,
      ),
    ],
  ),

  // 3. BÖLÜM: HAVA DURUMU
  OnboardingSection(
    id: 'weather_insights',
    title: 'Hava Durumu',
    subtitle: 'Anlık atmosfer verileri, canlı arka plan ve ani değişim uyarıları',
    icon: Icons.cloud_outlined,
    cards: [
      OnboardingCardData(
        title: 'Hızlı Şehir ve İlçe Sorgusu',
        description:
            'Dünyadaki herhangi bir şehir veya ilçeyi yazarak kombin önerisi beklemeden anlık hava durumunu hemen öğrenebilirsiniz. İl ve ilçe adını birlikte yazarak nokta atışı konum seçebilirsiniz.',
        semanticsLabel:
            'Hızlı hava durumu arama önizlemesi: İlçe veya şehir arama alanı ve anlık sorgu butonu.',
        assetPath: 'assets/onboarding/weather_search.webp',
        previewType: OnboardingPreviewType.quickLocationSearch,
      ),
      OnboardingCardData(
        title: 'Hissedilen Sıcaklık ve 6 Hava Kategorisi',
        description:
            'Gerçek sıcaklığın yanında rüzgar ve nemle değişen hissedilen sıcaklığı ve rüzgar hızını net olarak görürsünüz. Hava durumu Güneşli, Soğuk/Ayaz, Yağmurlu, Karlı, Rüzgarlı ve Dolu olarak 6 net kategoride sunulur.',
        semanticsLabel:
            'Hava durumu detay önizlemesi: Derece, hissedilen sıcaklık, rüzgar hızı ve 6 hava kategorisi etiketi.',
        assetPath: 'assets/onboarding/weather_categories.webp',
        previewType: OnboardingPreviewType.feelsLikeAndSixCategories,
      ),
      OnboardingCardData(
        title: 'Hava Durumuna Duyarlı Canlı Arka Plan',
        description:
            'Uygulamanın arka planı ve kart vurguları sorguladığınız konumun hava olayına göre yumuşak bir geçişle değişir. Dilerseniz yan menüden açık/koyu mermer temasını veya düşük performans modunu seçebilirsiniz.',
        semanticsLabel:
            'Canlı arka plan önizlemesi: Yağmur, kar ve güneş efektleriyle mermer kart görünümü.',
        assetPath: 'assets/onboarding/weather_background.webp',
        previewType: OnboardingPreviewType.liveWeatherBackground,
      ),
      OnboardingCardData(
        title: 'Ani Hava Değişimi Uyarıları',
        description:
            'Gün içinde sıcaklıkta sert bir dalgalanma veya ani yağış/fırtına beklendiğinde uygulama sizi önceden uyarır. Böylece dışarı çıkmadan önce yanınıza koruyucu bir dış katman veya şemsiye alabilirsiniz.',
        semanticsLabel:
            'Ani hava değişimi uyarısı önizlemesi: Sıcaklık farkı ve yağış uyarısı bildirim kartı.',
        assetPath: 'assets/onboarding/weather_shift_alert.webp',
        previewType: OnboardingPreviewType.abruptWeatherShiftAlert,
      ),
    ],
  ),

  // 4. BÖLÜM: PROFİL & HESAP
  OnboardingSection(
    id: 'profile_and_account',
    title: 'Profil & Hesap',
    subtitle: 'Fiziksel tercihleriniz, bildirim kontrolü ve veri gizliliğiniz',
    icon: Icons.verified_user_outlined,
    cards: [
      OnboardingCardData(
        title: 'Fiziksel Profil ve Varsayılan Konum',
        description:
            'Profilim ekranından varsayılan konumunuzu ve profil fotoğrafınızı kaydedebilir, ana ekrandan boy, kilo ve terleme tercihinizi güncelleyebilirsiniz. Kaydettiğiniz varsayılan konum her açılışta kombin ekranınıza otomatik gelir.',
        semanticsLabel:
            'Profil ve fiziksel tercihler önizlemesi: Varsayılan konum, boy, kilo ve terleme eğilimi alanları.',
        assetPath: 'assets/onboarding/profile_preferences.webp',
        previewType: OnboardingPreviewType.physicalProfileAndSweating,
      ),
      OnboardingCardData(
        title: 'Bildirim ve Rutin Kontrolü',
        description:
            'Eklediğiniz her rutinin yanındaki anahtarla bildirimleri tek dokunuşla açıp kapatabilir veya sesli bildirim testini anında deneyebilirsiniz. Hangi gün ve saatte bildirim alacağınız tamamen sizin tercihinize bağlıdır.',
        semanticsLabel:
            'Bildirim kontrolü önizlemesi: Rutin bildirim anahtarları ve anında ses testi butonu.',
        assetPath: 'assets/onboarding/notification_controls.webp',
        previewType: OnboardingPreviewType.notificationAndRoutineControl,
      ),
      OnboardingCardData(
        title: 'Veri Kontrolü, Hesap Dondurma ve Silme',
        description:
            'Verilerinizin kontrolü her zaman sizdedir; Hesap Ayarları ekranından hesabınızı istediğiniz an geçici olarak dondurabilirsiniz. Dilerseniz KVKK kapsamında hesabınızı ve tüm kayıtlı verilerinizi kalıcı olarak silebilirsiniz.',
        semanticsLabel:
            'Hesap ayarları önizlemesi: Hesabı geçici dondurma ve tüm verilerle kalıcı silme seçenekleri.',
        assetPath: 'assets/onboarding/account_privacy.webp',
        previewType: OnboardingPreviewType.accountPrivacyAndControl,
      ),
    ],
  ),
];

/// İlgili `assetPath` altında WebP görseli varsa onu gösterir;
/// henüz yüklenmemişse mermer temasına (`OptiWearTheme`) tam uyumlu,
/// etkileşimsiz (`IgnorePointer`) mini ekran önizlemesini üretir.
class OnboardingCardPreviewWidget extends StatelessWidget {
  final OnboardingCardData card;

  const OnboardingCardPreviewWidget({
    super.key,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    final ow = OptiWearTheme.of(context);

    return Semantics(
      label: card.semanticsLabel,
      image: true,
      child: IgnorePointer(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 165, maxHeight: 205),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ow.cardBorder, width: 1.0),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ow.elevatedSurface.withOpacity(ow.isDark ? 0.92 : 0.96),
                Color.lerp(
                  ow.cardSurface,
                  ow.weatherTint,
                  ow.weatherTintOpacity * 1.1,
                )!
                    .withOpacity(ow.isDark ? 0.95 : 0.98),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.asset(
              card.assetPath,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, _, __) {
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: _buildMockPreview(context, ow, card.previewType),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockPreview(
    BuildContext context,
    OptiWearTheme ow,
    OnboardingPreviewType type,
  ) {
    switch (type) {
      case OnboardingPreviewType.outfitRecommendation:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.checkroom_rounded,
              title: 'Samsun, Tekkeköy • Yağmurlu',
              badgeText: '11°C',
              badgeColor: ow.temperatureColor(11),
            ),
            const SizedBox(height: 10),
            _mockPillRow(ow, ['Boy: 178 cm', 'Kilo: 76 kg', 'Terleme: Evet']),
            const SizedBox(height: 10),
            _mockInfoBox(
              ow,
              text:
                  'Nefes alan iç katman üzerine fermuarlı polar giy; dışarı çıkarken su geçirmez bot ve şemsiyeni yanına al.',
            ),
          ],
        );

      case OnboardingPreviewType.dailyRoutinesLeadTime:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.alarm_rounded,
              title: 'İşe Gidiş • 08:00',
              badgeText: '10 dk önce',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['P', 'S', 'Ç', 'P', 'C', 'C', 'P']
                  .asMap()
                  .entries
                  .map((e) {
                final active = e.key < 5;
                return Container(
                  width: 28,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? ow.effectiveAccent : ow.cardSurface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: active ? ow.effectiveAccent : ow.cardBorder,
                    ),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? ow.onEffectiveAccent : ow.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            _mockInfoBox(
              ow,
              text: 'Bildirim: 07:50 • Kişisel kombin özeti sesli gönderilir.',
            ),
          ],
        );

      case OnboardingPreviewType.thermalMemoryInput:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.psychology_outlined,
              title: 'Termal Hafıza',
              badgeText: '3 kayıt',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: ow.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ow.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded,
                      size: 16, color: ow.effectiveAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '12°C yürüyüşte kalın montla terledim',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: ow.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _mockPillRow(
                ow, ['+ Rüzgarda ince ceketle üşüdüm', '+ 15°C polar idealdi']),
          ],
        );

      case OnboardingPreviewType.scenarioListManagement:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.checklist_rounded,
              title: 'Senaryo Listesi • 2 seçili',
              badgeText: 'Toplu Sil',
              badgeColor: ow.danger,
            ),
            const SizedBox(height: 8),
            _mockScenarioRow(
              ow,
              text: '12°C yürüyüşte kalın montla terledim',
              time: '2 gün önce',
              selected: true,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ow.cardSurface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: ow.veinMedium),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Senaryo silindi (5 sn)',
                    style: TextStyle(fontSize: 11, color: ow.textSecondary),
                  ),
                  Text(
                    'GERİ AL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ow.effectiveAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case OnboardingPreviewType.multiDayTravelMode:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.public_rounded,
              title: 'Hedef Rota Seçimi',
              badgeText: 'Seyahat',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            _mockInfoBox(
              ow,
              icon: Icons.place_outlined,
              text: 'Kaş, Antalya, Türkiye',
            ),
            const SizedBox(height: 8),
            _mockPillRow(ow, ['Başlangıç: 12 Mayıs', 'Bitiş: 16 Mayıs']),
          ],
        );

      case OnboardingPreviewType.travelDateRangeForecast:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.calendar_month_rounded,
              title: 'Günlük Seyahat Tahmini',
              badgeText: '4 Gün',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 8),
            _mockForecastLine(ow, '1. Gün • Güneşli', '14°C / 24°C', 24),
            const SizedBox(height: 5),
            _mockForecastLine(ow, '2. Gün • Rüzgarlı', '12°C / 19°C', 19),
            const SizedBox(height: 5),
            _mockForecastLine(ow, '3. Gün • Yağmurlu', '10°C / 15°C', 15),
          ],
        );

      case OnboardingPreviewType.personalPackingStrategy:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.luggage_rounded,
              title: 'Kişisel Valiz Özeti',
              badgeText: 'Hazır',
              badgeColor: ow.success,
            ),
            const SizedBox(height: 10),
            _mockPillRow(ow, [
              'Nefes Alan Tişört',
              'Rüzgarlık',
              'Şemsiye',
              'Su İtici Sneaker',
            ]),
            const SizedBox(height: 8),
            _mockInfoBox(
              ow,
              text:
                  'Gündüzleri güneş gözlüğü, 3. gündeki yağış için katlanabilir şemsiye ve su itici dış katman ekleyin.',
            ),
          ],
        );

      case OnboardingPreviewType.quickLocationSearch:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.search_rounded,
              title: 'Hızlı Hava Durumu Arama',
              badgeText: 'Anlık',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            _mockInfoBox(
              ow,
              icon: Icons.location_searching_rounded,
              text: 'Tekkeköy, Samsun, Türkiye',
            ),
            const SizedBox(height: 8),
            _mockPillRow(
                ow, ['İlçe: Tekkeköy', 'İl: Samsun', 'Anlık Sorgula']),
          ],
        );

      case OnboardingPreviewType.feelsLikeAndSixCategories:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '14.5°C',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: ow.temperatureColor(14.5),
                  ),
                ),
                Text(
                  'Hissedilen: 12.0°C • 22 km/s',
                  style: TextStyle(fontSize: 11.5, color: ow.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _mockPillRow(ow, [
              'Güneşli',
              'Soğuk/Ayaz',
              'Yağmurlu',
              'Karlı',
              'Rüzgarlı',
              'Dolu',
            ]),
          ],
        );

      case OnboardingPreviewType.liveWeatherBackground:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.auto_awesome_rounded,
              title: 'Canlı Atmosfer & Mermer Tema',
              badgeText: ow.isDark ? 'Oniks' : 'Carrara',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            _mockPillRow(
                ow, ['Sistem Teması', 'Carrara (Açık)', 'Oniks (Koyu)']),
            const SizedBox(height: 8),
            _mockInfoBox(
              ow,
              text:
                  'Arka plan yağmur, kar, rüzgar ve güneş durumuna göre yumuşak geçişle kilitlenir.',
            ),
          ],
        );

      case OnboardingPreviewType.abruptWeatherShiftAlert:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.thunderstorm_outlined,
              title: 'Ani Hava Değişimi Uyarısı',
              badgeText: 'Δ 9°C Fark',
              badgeColor: ow.warning,
            ),
            const SizedBox(height: 10),
            _mockInfoBox(
              ow,
              text:
                  'Dikkat! Gün içinde ani hava ve sıcaklık değişimi bekleniyor. Dışarı çıkarken tedbirli ve katmanlı giyinin.',
            ),
          ],
        );

      case OnboardingPreviewType.physicalProfileAndSweating:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.person_outline_rounded,
              title: 'Profil & Fiziksel Tercihler',
              badgeText: 'Senkron',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            _mockPillRow(ow, [
              'Konum: İstanbul',
              'Boy: 175 cm',
              'Kilo: 75 kg',
            ]),
            const SizedBox(height: 8),
            _mockInfoBox(
              ow,
              text:
                  'Varsayılan konumunuz ana ekrana otomatik yansır; terleme tercihiniz katman sayısını dengeler.',
            ),
          ],
        );

      case OnboardingPreviewType.notificationAndRoutineControl:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.notifications_active_outlined,
              title: 'Bildirim ve Ses Kontrolü',
              badgeText: 'Aktif',
              badgeColor: ow.success,
            ),
            const SizedBox(height: 8),
            _mockInfoBox(
              ow,
              icon: Icons.volume_up_rounded,
              text: 'Sabah Uyanma (07:30) • Bildirim Açık',
            ),
            const SizedBox(height: 8),
            _mockPillRow(
                ow, ['Bildirimi Şimdi Test Et', 'Rutini Aç / Kapat']),
          ],
        );

      case OnboardingPreviewType.accountPrivacyAndControl:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _mockHeaderRow(
              ow,
              icon: Icons.shield_outlined,
              title: 'Hesap Ayarları ve KVKK Kontrolü',
              badgeText: 'Güvenli',
              badgeColor: ow.effectiveAccent,
            ),
            const SizedBox(height: 10),
            _mockPillRow(ow, [
              'Hesabı Geçici Dondur',
              'Hesabı Kalıcı Sil (KVKK)',
            ]),
            const SizedBox(height: 8),
            _mockInfoBox(
              ow,
              text:
                  'Kişisel verileriniz şifreli saklanır; dilediğiniz an hesabınızı pasife alabilir veya tamamen silebilirsiniz.',
            ),
          ],
        );
    }
  }

  Widget _mockHeaderRow(
    OptiWearTheme ow, {
    required IconData icon,
    required String title,
    required String badgeText,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ow.effectiveAccent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: ow.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: badgeColor.withOpacity(0.5)),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: badgeColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mockPillRow(OptiWearTheme ow, List<String> labels) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: labels
          .map(
            (l) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ow.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ow.cardBorder),
              ),
              child: Text(
                l,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: ow.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _mockInfoBox(
    OptiWearTheme ow, {
    IconData? icon,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ow.cardSurface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ow.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: ow.effectiveAccent),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.2,
                height: 1.35,
                color: ow.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mockScenarioRow(
    OptiWearTheme ow, {
    required String text,
    required String time,
    required bool selected,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: ow.cardSurface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? ow.effectiveAccent : ow.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: selected ? ow.effectiveAccent : ow.textSecondary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.2, color: ow.textPrimary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            time,
            style: TextStyle(fontSize: 10, color: ow.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _mockForecastLine(
    OptiWearTheme ow,
    String dayLabel,
    String tempRange,
    double maxTemp,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ow.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ow.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            dayLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ow.textPrimary,
            ),
          ),
          Text(
            tempRange,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ow.temperatureColor(maxTemp),
            ),
          ),
        ],
      ),
    );
  }
}
