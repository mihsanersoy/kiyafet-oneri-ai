import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 6 Hava Durumu Kategorisi
enum WeatherCategory {
  sunny('Güneşli'),
  coldFrost('Soğuk/Ayaz'),
  rainy('Yağmurlu'),
  snowy('Karlı'),
  windy('Rüzgarlı'),
  hail('Dolu');

  final String label;
  const WeatherCategory(this.label);

  static WeatherCategory fromStatus(String? rawStatus) {
    final s = (rawStatus ?? '').trim();
    switch (s) {
      case 'Güneşli':
        return WeatherCategory.sunny;
      case 'Soğuk/Ayaz':
        return WeatherCategory.coldFrost;
      case 'Yağmurlu':
        return WeatherCategory.rainy;
      case 'Karlı':
        return WeatherCategory.snowy;
      case 'Rüzgarlı':
        return WeatherCategory.windy;
      case 'Dolu':
        return WeatherCategory.hail;
      default:
        return WeatherCategory.sunny;
    }
  }
}

/// Hava Durumu Vurgu ve Tint Çifti
class WeatherAccentSpec {
  final Color accent;
  final Color secondaryAccent;
  final Color dayTint;
  final Color nightTint;

  const WeatherAccentSpec({
    required this.accent,
    required this.secondaryAccent,
    required this.dayTint,
    required this.nightTint,
  });

  Color tintFor({required bool isNight}) => isNight ? nightTint : dayTint;

  static WeatherAccentSpec forCategory(WeatherCategory category) {
    switch (category) {
      case WeatherCategory.sunny:
        return const WeatherAccentSpec(
          accent: Color(0xFFE8B86D),
          secondaryAccent: Color(0xFFD9A05B),
          dayTint: Color(0xFFFFD166),
          nightTint: Color(0xFF282A52),
        );
      case WeatherCategory.coldFrost:
        return const WeatherAccentSpec(
          accent: Color(0xFFA8DADC),
          secondaryAccent: Color(0xFF7FB8C2),
          dayTint: Color(0xFF5C7C99),
          nightTint: Color(0xFF1E293B),
        );
      case WeatherCategory.rainy:
        return const WeatherAccentSpec(
          accent: Color(0xFF5B7B9A),
          secondaryAccent: Color(0xFF7B9AB8),
          dayTint: Color(0xFF3D5A80),
          nightTint: Color(0xFF1F2A44),
        );
      case WeatherCategory.snowy:
        return const WeatherAccentSpec(
          accent: Color(0xFFCBD5E1),
          secondaryAccent: Color(0xFF94A3B8),
          dayTint: Color(0xFF94A3B8),
          nightTint: Color(0xFF253147),
        );
      case WeatherCategory.windy:
        return const WeatherAccentSpec(
          accent: Color(0xFF6BB5A6),
          secondaryAccent: Color(0xFF8FA6B8),
          dayTint: Color(0xFF8FA6B8),
          nightTint: Color(0xFF213142),
        );
      case WeatherCategory.hail:
        return const WeatherAccentSpec(
          accent: Color(0xFF718096),
          secondaryAccent: Color(0xFF7DD3FC),
          dayTint: Color(0xFF4A5568),
          nightTint: Color(0xFF312E81),
        );
    }
  }
}

/// Mermer Estetiği (Carrara Açık & Oniks Koyu) + Hava Vurguları ThemeExtension
@immutable
class OptiWearTheme extends ThemeExtension<OptiWearTheme> {
  final Brightness brightness;
  final Color background;
  final Color elevatedSurface;
  final Color cardSurface;
  final Color cardSurfaceBottom;
  final Color veinLight;
  final Color veinMedium;
  final Color veinStrong;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color weatherAccent;
  final Color weatherSecondaryAccent;
  final Color weatherTint;
  final double weatherTintOpacity;
  final Color danger;
  final Color warning;
  final Color success;
  final bool isNight;

  const OptiWearTheme({
    required this.brightness,
    required this.background,
    required this.elevatedSurface,
    required this.cardSurface,
    required this.cardSurfaceBottom,
    required this.veinLight,
    required this.veinMedium,
    required this.veinStrong,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.weatherAccent,
    required this.weatherSecondaryAccent,
    required this.weatherTint,
    required this.weatherTintOpacity,
    required this.danger,
    required this.warning,
    required this.success,
    required this.isNight,
  });

  bool get isDark => brightness == Brightness.dark;

  /// Sıcaklık Skalası: #38BDF8 -> #A3E635 -> #FBBF24 -> #F97316
  static const List<Color> temperatureScaleColors = [
    Color(0xFF38BDF8), // <= 5°C soğuk
    Color(0xFFA3E635), // ~15°C ılıman
    Color(0xFFFBBF24), // ~24°C sıcak
    Color(0xFFF97316), // >= 32°C yüksek sıcak
  ];

  /// Verilen dereceye (°C) göre sıcaklık skalasından enterpolasyonlu renk döner.
  /// Açık mermer zemin üzerinde WCAG AA okunabilirliği için gerektiğinde koyulaştırır.
  Color temperatureColor(double tempCelsius) {
    final t = ((tempCelsius + 2.0) / 36.0).clamp(0.0, 1.0);
    Color raw;
    if (t < 0.33) {
      raw = Color.lerp(
        temperatureScaleColors[0],
        temperatureScaleColors[1],
        t / 0.33,
      )!;
    } else if (t < 0.66) {
      raw = Color.lerp(
        temperatureScaleColors[1],
        temperatureScaleColors[2],
        (t - 0.33) / 0.33,
      )!;
    } else {
      raw = Color.lerp(
        temperatureScaleColors[2],
        temperatureScaleColors[3],
        (t - 0.66) / 0.34,
      )!;
    }
    if (!isDark) {
      // Carrara açık mermer üzerinde yüksek kontrast için hafif koyu tonlama
      return Color.lerp(raw, const Color(0xFF1A1A1C), 0.24)!;
    }
    return raw;
  }

  /// Buton ve seçili durumlar için açık/koyu zeminde WCAG AA uyumlu vurgu rengi
  Color get effectiveAccent {
    if (!isDark) {
      final hsl = HSLColor.fromColor(weatherAccent);
      if (hsl.lightness > 0.44) {
        return hsl.withLightness(0.36).withSaturation((hsl.saturation * 0.85).clamp(0.15, 0.75)).toColor();
      }
    }
    return weatherAccent;
  }

  /// Vurgu rengi üzerindeki metin/ikon rengi (WCAG AA >= 4.5:1)
  Color get onEffectiveAccent {
    final lum = effectiveAccent.computeLuminance();
    return lum > 0.38 ? const Color(0xFF17171A) : const Color(0xFFFAFAF8);
  }

  /// Kartlar için üstten alta çok yumuşak mermer gradyanı + %8-12 hava tint karışımı
  LinearGradient get cardGradient {
    final topColor = Color.lerp(
      cardSurface,
      weatherTint,
      weatherTintOpacity * 0.65,
    )!;
    final bottomColor = Color.lerp(
      cardSurfaceBottom,
      weatherTint,
      weatherTintOpacity,
    )!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [topColor, bottomColor],
    );
  }

  /// Açık Tema (Carrara Mermeri)
  factory OptiWearTheme.carrara({
    WeatherCategory category = WeatherCategory.sunny,
    bool isNight = false,
  }) {
    final spec = WeatherAccentSpec.forCategory(category);
    return OptiWearTheme(
      brightness: Brightness.light,
      background: const Color(0xFFF5F5F2),
      elevatedSurface: const Color(0xFFECEBE7),
      cardSurface: const Color(0xFFFAFAF8),
      cardSurfaceBottom: const Color(0xFFF1F0EC),
      veinLight: const Color(0xFFDAD8D2),
      veinMedium: const Color(0xFFB8B5AD),
      veinStrong: const Color(0xFF8E8B84),
      cardBorder: const Color(0xFFD5D3CC),
      textPrimary: const Color(0xFF1A1A1C),
      textSecondary: const Color(0xFF55555B),
      weatherAccent: spec.accent,
      weatherSecondaryAccent: spec.secondaryAccent,
      weatherTint: spec.tintFor(isNight: isNight),
      weatherTintOpacity: isNight ? 0.10 : 0.09,
      danger: const Color(0xFFB93838),
      warning: const Color(0xFFB4691E),
      success: const Color(0xFF2B7A5B),
      isNight: isNight,
    );
  }

  /// Koyu Tema (Oniks Mermeri)
  factory OptiWearTheme.onyx({
    WeatherCategory category = WeatherCategory.sunny,
    bool isNight = false,
  }) {
    final spec = WeatherAccentSpec.forCategory(category);
    return OptiWearTheme(
      brightness: Brightness.dark,
      background: const Color(0xFF0E0E10),
      elevatedSurface: const Color(0xFF17171A),
      cardSurface: const Color(0xFF1E1E22),
      cardSurfaceBottom: const Color(0xFF18181C),
      veinLight: const Color(0xFF2E2E33),
      veinMedium: const Color(0xFF4A4A50),
      veinStrong: const Color(0xFF6B6B72),
      cardBorder: const Color(0xFF333339),
      textPrimary: const Color(0xFFF0EFEA),
      textSecondary: const Color(0xFFA5A5AB),
      weatherAccent: spec.accent,
      weatherSecondaryAccent: spec.secondaryAccent,
      weatherTint: spec.tintFor(isNight: isNight),
      weatherTintOpacity: isNight ? 0.14 : 0.11,
      danger: const Color(0xFFE57373),
      warning: const Color(0xFFE6A24C),
      success: const Color(0xFF5CB894),
      isNight: isNight,
    );
  }

  static OptiWearTheme of(BuildContext context) {
    final ext = Theme.of(context).extension<OptiWearTheme>();
    if (ext != null) return ext;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? OptiWearTheme.onyx() : OptiWearTheme.carrara();
  }

  /// Bu mermer paletinden Material 3 ThemeData ve ColorScheme üretir
  ThemeData toThemeData() {
    final accent = effectiveAccent;
    final onAccent = onEffectiveAccent;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: Color.lerp(elevatedSurface, weatherTint, 0.22)!,
      onPrimaryContainer: textPrimary,
      secondary: weatherSecondaryAccent,
      onSecondary: isDark ? const Color(0xFF17171A) : const Color(0xFFFAFAF8),
      secondaryContainer: Color.lerp(cardSurface, weatherTint, 0.16)!,
      onSecondaryContainer: textPrimary,
      tertiary: veinStrong,
      onTertiary: isDark ? const Color(0xFF17171A) : const Color(0xFFFAFAF8),
      error: danger,
      onError: const Color(0xFFFAFAF8),
      surface: cardSurface,
      onSurface: textPrimary,
      surfaceContainerHighest: elevatedSurface,
      onSurfaceVariant: textSecondary,
      outline: veinMedium,
      outlineVariant: veinLight,
      shadow: const Color(0xFF0E0E10),
      scrim: const Color(0xFF0E0E10),
      inverseSurface: isDark ? const Color(0xFFF5F5F2) : const Color(0xFF17171A),
      onInverseSurface: isDark ? const Color(0xFF1A1A1C) : const Color(0xFFF0EFEA),
      inversePrimary: weatherAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: elevatedSurface,
      dividerColor: veinLight,
      extensions: <ThemeExtension<dynamic>>[this],
      appBarTheme: AppBarTheme(
        backgroundColor: elevatedSurface.withOpacity(isDark ? 0.88 : 0.92),
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardTheme(
        color: cardSurface.withOpacity(isDark ? 0.90 : 0.92),
        surfaceTintColor: weatherTint.withOpacity(weatherTintOpacity),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cardBorder, width: 1.0),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: veinLight,
        thickness: 1,
        space: 20,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: elevatedSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: elevatedSurface.withOpacity(isDark ? 0.92 : 0.94),
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withOpacity(isDark ? 0.24 : 0.20),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return IconThemeData(color: accent, size: 23);
          }
          return IconThemeData(color: textSecondary, size: 22);
        }),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return TextStyle(
              color: textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurface.withOpacity(isDark ? 0.72 : 0.76),
        labelStyle: TextStyle(color: textSecondary, fontSize: 13.5),
        hintStyle: TextStyle(color: textSecondary.withOpacity(0.75), fontSize: 13),
        prefixIconColor: accent,
        suffixIconColor: textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: veinLight, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: veinLight,
          disabledForegroundColor: textSecondary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: veinMedium, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevatedSurface,
        selectedColor: accent.withOpacity(0.22),
        side: BorderSide(color: veinLight, width: 1.0),
        labelStyle: TextStyle(color: textPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return onAccent;
          return textSecondary;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return accent;
          return elevatedSurface;
        }),
        trackOutlineColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return Colors.transparent;
          return veinMedium;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF232329) : const Color(0xFF232326),
        contentTextStyle: const TextStyle(color: Color(0xFFF0EFEA), fontSize: 13.5),
        actionTextColor: weatherAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: veinMedium.withOpacity(0.45)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cardBorder),
        ),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
        headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary, height: 1.45),
        bodyMedium: TextStyle(color: textPrimary, height: 1.42),
        bodySmall: TextStyle(color: textSecondary, height: 1.38),
        labelLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: textSecondary),
      ),
    );
  }

  @override
  OptiWearTheme copyWith({
    Brightness? brightness,
    Color? background,
    Color? elevatedSurface,
    Color? cardSurface,
    Color? cardSurfaceBottom,
    Color? veinLight,
    Color? veinMedium,
    Color? veinStrong,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? weatherAccent,
    Color? weatherSecondaryAccent,
    Color? weatherTint,
    double? weatherTintOpacity,
    Color? danger,
    Color? warning,
    Color? success,
    bool? isNight,
  }) {
    return OptiWearTheme(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      cardSurface: cardSurface ?? this.cardSurface,
      cardSurfaceBottom: cardSurfaceBottom ?? this.cardSurfaceBottom,
      veinLight: veinLight ?? this.veinLight,
      veinMedium: veinMedium ?? this.veinMedium,
      veinStrong: veinStrong ?? this.veinStrong,
      cardBorder: cardBorder ?? this.cardBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      weatherAccent: weatherAccent ?? this.weatherAccent,
      weatherSecondaryAccent: weatherSecondaryAccent ?? this.weatherSecondaryAccent,
      weatherTint: weatherTint ?? this.weatherTint,
      weatherTintOpacity: weatherTintOpacity ?? this.weatherTintOpacity,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      isNight: isNight ?? this.isNight,
    );
  }

  @override
  OptiWearTheme lerp(ThemeExtension<OptiWearTheme>? other, double t) {
    if (other is! OptiWearTheme) return this;
    return OptiWearTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardSurfaceBottom: Color.lerp(cardSurfaceBottom, other.cardSurfaceBottom, t)!,
      veinLight: Color.lerp(veinLight, other.veinLight, t)!,
      veinMedium: Color.lerp(veinMedium, other.veinMedium, t)!,
      veinStrong: Color.lerp(veinStrong, other.veinStrong, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      weatherAccent: Color.lerp(weatherAccent, other.weatherAccent, t)!,
      weatherSecondaryAccent:
          Color.lerp(weatherSecondaryAccent, other.weatherSecondaryAccent, t)!,
      weatherTint: Color.lerp(weatherTint, other.weatherTint, t)!,
      weatherTintOpacity:
          ui.lerpDouble(weatherTintOpacity, other.weatherTintOpacity, t) ??
              weatherTintOpacity,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      isNight: t < 0.5 ? isNight : other.isNight,
    );
  }
}

/// Mermer Estetikli Kart Bileşeni:
/// - Üstten alta yumuşak mermer gradyanı + hava tint katmanı
/// - 1px ince mermer kenarlık (açıkta daha koyu, koyuda daha açık ton)
/// - Çok hafif gömülü prosedürel damar izi
class MarbleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool showSubtleVeins;

  const MarbleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.borderRadius = 18,
    this.showSubtleVeins = true,
  });

  @override
  Widget build(BuildContext context) {
    final ow = OptiWearTheme.of(context);
    final topColor = Color.lerp(
      ow.cardSurface,
      ow.weatherTint,
      ow.weatherTintOpacity * 0.55,
    )!
        .withOpacity(ow.isDark ? 0.88 : 0.91);
    final bottomColor = Color.lerp(
      ow.cardSurfaceBottom,
      ow.weatherTint,
      ow.weatherTintOpacity * 0.90,
    )!
        .withOpacity(ow.isDark ? 0.92 : 0.94);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: ow.cardBorder, width: 1.0),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E0E10).withOpacity(ow.isDark ? 0.28 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            if (showSubtleVeins)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _CardMarbleVeinPainter(
                        veinColor: ow.veinMedium.withOpacity(
                          ow.isDark ? 0.08 : 0.11,
                        ),
                        secondaryVeinColor: ow.veinLight.withOpacity(
                          ow.isDark ? 0.06 : 0.09,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardMarbleVeinPainter extends CustomPainter {
  final Color veinColor;
  final Color secondaryVeinColor;

  const _CardMarbleVeinPainter({
    required this.veinColor,
    required this.secondaryVeinColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final mainPaint = Paint()
      ..color = veinColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    final softPaint = Paint()
      ..color = secondaryVeinColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    final path1 = Path()
      ..moveTo(size.width * 0.05, size.height * 0.18)
      ..cubicTo(
        size.width * 0.32,
        size.height * 0.08,
        size.width * 0.58,
        size.height * 0.42,
        size.width * 0.96,
        size.height * 0.26,
      );

    final path2 = Path()
      ..moveTo(size.width * 0.18, size.height * 0.88)
      ..cubicTo(
        size.width * 0.45,
        size.height * 0.65,
        size.width * 0.72,
        size.height * 0.78,
        size.width * 0.94,
        size.height * 0.54,
      );

    canvas.drawPath(path1, softPaint);
    canvas.drawPath(path1, mainPaint);
    canvas.drawPath(path2, softPaint);
  }

  @override
  bool shouldRepaint(covariant _CardMarbleVeinPainter oldDelegate) {
    return oldDelegate.veinColor != veinColor ||
        oldDelegate.secondaryVeinColor != secondaryVeinColor;
  }
}
