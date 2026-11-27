import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/marble_background_painter.dart';
import '../theme/optiwear_theme.dart';

/// Web'deki (components/UserPreferenceForm.tsx) deterministik parçacık modelleri
class _RainParticle {
  final double leftFraction;
  final double delaySeconds;
  final double durationSeconds;
  final double opacity;

  const _RainParticle({
    required this.leftFraction,
    required this.delaySeconds,
    required this.durationSeconds,
    required this.opacity,
  });
}

class _SnowParticle {
  final double leftFraction;
  final double delaySeconds;
  final double durationSeconds;
  final double size;

  const _SnowParticle({
    required this.leftFraction,
    required this.delaySeconds,
    required this.durationSeconds,
    required this.size,
  });
}

class _HailParticle {
  final double leftFraction;
  final double delaySeconds;
  final double durationSeconds;
  final double size;

  const _HailParticle({
    required this.leftFraction,
    required this.delaySeconds,
    required this.durationSeconds,
    required this.size,
  });
}

class _WindStreak {
  final double topFraction;
  final double delaySeconds;
  final double durationSeconds;
  final double width;

  const _WindStreak({
    required this.topFraction,
    required this.delaySeconds,
    required this.durationSeconds,
    required this.width,
  });
}

/// Web'deki sabit deterministik parçacık dizileriyle birebir uyumlu listeler
final List<_RainParticle> _kRainParticles = List.generate(42, (i) {
  return _RainParticle(
    leftFraction: ((i * 2.4) % 100) / 100.0,
    delaySeconds: (i * 0.17) % 2.0,
    durationSeconds: 0.65 + ((i * 0.11) % 0.45),
    opacity: 0.35 + ((i * 0.07) % 0.50),
  );
});

final List<_SnowParticle> _kSnowParticles = List.generate(36, (i) {
  return _SnowParticle(
    leftFraction: ((i * 2.8) % 100) / 100.0,
    delaySeconds: (i * 0.25) % 4.0,
    durationSeconds: 3.5 + ((i * 0.30) % 3.0),
    size: 4.0 + (i % 6),
  );
});

final List<_HailParticle> _kHailParticles = List.generate(32, (i) {
  return _HailParticle(
    leftFraction: ((i * 3.1) % 100) / 100.0,
    delaySeconds: (i * 0.12) % 1.2,
    durationSeconds: 0.40 + ((i * 0.05) % 0.25),
    size: 5.0 + (i % 5),
  );
});

final List<_WindStreak> _kWindStreaks = List.generate(14, (i) {
  return _WindStreak(
    topFraction: (8.0 + ((i * 6.5) % 85.0)) / 100.0,
    delaySeconds: (i * 0.35) % 3.0,
    durationSeconds: 1.8 + ((i * 0.20) % 1.5),
    width: 120.0 + ((i * 25) % 180),
  );
});

/// Hava Durumuna Duyarlı Arka Plan Animasyonu
/// - Web'deki `WeatherAnimatedBackground`'un 6 temasını (Güneşli, Soğuk/Ayaz,
///   Yağmurlu, Karlı, Rüzgarlı, Dolu) tek bir `AnimationController` ve `CustomPainter` ile çizer.
/// - Veri gelmeden önce (`lockedWeatherStatus == null`) 5.5 saniyede bir 6 tema arasında döngü yapar.
/// - `hava_durumu_durumu` verisi geldiğinde o temaya kilitlenir ve cross-fade ile yumuşak geçiş yapar.
/// - `WidgetsBindingObserver` ile uygulama arka plana geçtiğinde animasyonu durdurur.
/// - `lowPerformanceMode` etkinleştirildiğinde parçacık sayısını yarıya indirir veya statik mermer zemine düşer.
class WeatherAnimatedBackground extends StatefulWidget {
  final String? lockedWeatherStatus;
  final bool isNight;
  final bool lowPerformanceMode;
  final ValueChanged<WeatherCategory>? onActiveCategoryChanged;
  final Widget child;

  const WeatherAnimatedBackground({
    super.key,
    required this.child,
    this.lockedWeatherStatus,
    this.isNight = false,
    this.lowPerformanceMode = false,
    this.onActiveCategoryChanged,
  });

  @override
  State<WeatherAnimatedBackground> createState() =>
      _WeatherAnimatedBackgroundState();
}

class _WeatherAnimatedBackgroundState extends State<WeatherAnimatedBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const List<WeatherCategory> _allCategories = WeatherCategory.values;

  late final AnimationController _controller;
  Timer? _cycleTimer;
  int _cycleIndex = 0;

  WeatherCategory _previousCategory = WeatherCategory.sunny;
  WeatherCategory _currentCategory = WeatherCategory.sunny;
  double _transitionStartSec = 0.0;
  static const double _crossFadeDurationSec = 1.1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.lockedWeatherStatus != null &&
        widget.lockedWeatherStatus!.trim().isNotEmpty) {
      _currentCategory =
          WeatherCategory.fromStatus(widget.lockedWeatherStatus);
      _previousCategory = _currentCategory;
    }

    // 60 saniyelik kesintisiz zaman tabanı
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    _syncCycleTimer();
  }

  double get _elapsedSeconds => _controller.value * 60.0;

  void _syncCycleTimer() {
    _cycleTimer?.cancel();
    final hasLocked = widget.lockedWeatherStatus != null &&
        widget.lockedWeatherStatus!.trim().isNotEmpty;
    if (hasLocked) {
      final target = WeatherCategory.fromStatus(widget.lockedWeatherStatus);
      _switchToCategory(target);
      return;
    }

    _cycleTimer = Timer.periodic(const Duration(milliseconds: 5500), (_) {
      if (!mounted) return;
      _cycleIndex = (_cycleIndex + 1) % _allCategories.length;
      _switchToCategory(_allCategories[_cycleIndex]);
    });
  }

  void _switchToCategory(WeatherCategory next) {
    if (next == _currentCategory) return;
    setState(() {
      _previousCategory = _currentCategory;
      _currentCategory = next;
      _transitionStartSec = _elapsedSeconds;
    });
    widget.onActiveCategoryChanged?.call(next);
  }

  @override
  void didUpdateWidget(covariant WeatherAnimatedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockedWeatherStatus != widget.lockedWeatherStatus) {
      _syncCycleTimer();
    }
    if (oldWidget.lowPerformanceMode != widget.lowPerformanceMode) {
      if (widget.lowPerformanceMode) {
        // Düşük performans modunda da akıcı ama hafif çalışır
        if (!_controller.isAnimating) _controller.repeat();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller.stop();
      _cycleTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      _syncCycleTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cycleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = OptiWearTheme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. En Alt Katman: Mermer zemin + Prosedürel mermer damar dokusu
        Positioned.fill(
          child: ColoredBox(
            color: ow.background,
            child: const MarbleSurfaceBackground(),
          ),
        ),

        // 2. Hava Durumu Parçacık ve Atmosfer Katmanı (RepaintBoundary ile izole)
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final nowSec = _elapsedSeconds;
                  double delta = nowSec - _transitionStartSec;
                  if (delta < 0) delta += 60.0;
                  final crossFade =
                      (delta / _crossFadeDurationSec).clamp(0.0, 1.0);

                  return CustomPaint(
                    painter: _WeatherAtmospherePainter(
                      previousCategory: _previousCategory,
                      currentCategory: _currentCategory,
                      crossFadeProgress: Curves.easeInOut.transform(crossFade),
                      elapsedSeconds: nowSec,
                      isDark: ow.isDark,
                      isNight: widget.isNight,
                      lowPerformance: widget.lowPerformanceMode,
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // 3. Ön Plan İçeriği (Yarı saydam mermer kartlar ve yüzeyler)
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _WeatherAtmospherePainter extends CustomPainter {
  final WeatherCategory previousCategory;
  final WeatherCategory currentCategory;
  final double crossFadeProgress;
  final double elapsedSeconds;
  final bool isDark;
  final bool isNight;
  final bool lowPerformance;

  const _WeatherAtmospherePainter({
    required this.previousCategory,
    required this.currentCategory,
    required this.crossFadeProgress,
    required this.elapsedSeconds,
    required this.isDark,
    required this.isNight,
    required this.lowPerformance,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (previousCategory != currentCategory && crossFadeProgress < 1.0) {
      _paintCategoryScene(
        canvas,
        size,
        previousCategory,
        (1.0 - crossFadeProgress).clamp(0.0, 1.0),
      );
    }

    _paintCategoryScene(
      canvas,
      size,
      currentCategory,
      crossFadeProgress.clamp(0.0, 1.0),
    );
  }

  void _paintCategoryScene(
    Canvas canvas,
    Size size,
    WeatherCategory category,
    double masterAlpha,
  ) {
    if (masterAlpha <= 0.01) return;

    // Mermer estetiğini bozmamak için atmosfer tinti %8-15 aralığında tutulur
    final spec = WeatherAccentSpec.forCategory(category);
    final tintColor = spec.tintFor(isNight: isNight);
    final tintOpacity = (isDark ? (isNight ? 0.15 : 0.13) : 0.10) * masterAlpha;

    final washPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          tintColor.withOpacity(tintOpacity),
          spec.accent.withOpacity(tintOpacity * 0.55),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, washPaint);

    // Parçacık adım katsayısı (düşük performansta parçacık sayısını yarıya indirir)
    final step = lowPerformance ? 2 : 1;

    switch (category) {
      case WeatherCategory.sunny:
        _paintSunny(canvas, size, masterAlpha, spec);
        break;
      case WeatherCategory.coldFrost:
        _paintColdFrost(canvas, size, masterAlpha, spec);
        break;
      case WeatherCategory.rainy:
        _paintRain(canvas, size, masterAlpha, spec, step);
        break;
      case WeatherCategory.snowy:
        _paintSnow(canvas, size, masterAlpha, spec, step);
        break;
      case WeatherCategory.windy:
        _paintWindy(canvas, size, masterAlpha, spec, step);
        break;
      case WeatherCategory.hail:
        _paintHailAndStorm(canvas, size, masterAlpha, spec, step);
        break;
    }
  }

  /// 1. GÜNEŞLİ: Sağ üstte nefes alan (sunPulse 5s & 7s) sıcak amber/altın hale
  void _paintSunny(
    Canvas canvas,
    Size size,
    double masterAlpha,
    WeatherAccentSpec spec,
  ) {
    final pulse5 = 1.0 + 0.10 * math.sin((elapsedSeconds / 5.0) * 2 * math.pi);
    final pulse7 = 1.0 + 0.08 * math.cos((elapsedSeconds / 7.0) * 2 * math.pi);

    final center = Offset(size.width * 0.88, size.height * 0.08);
    final outerRadius = size.shortestSide * 0.52 * pulse5;
    final innerRadius = size.shortestSide * 0.24 * pulse7;

    final coreColor = isNight
        ? const Color(0xFF818CF8)
        : (isDark ? const Color(0xFFE8B86D) : const Color(0xFFD99B42));

    final outerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          coreColor.withOpacity((isDark ? 0.22 : 0.18) * masterAlpha),
          spec.dayTint.withOpacity((isDark ? 0.09 : 0.08) * masterAlpha),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));

    final innerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          coreColor.withOpacity((isDark ? 0.28 : 0.22) * masterAlpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));

    canvas.drawCircle(center, outerRadius, outerGlow);
    canvas.drawCircle(center, innerRadius, innerGlow);
  }

  /// 2. SOĞUK / AYAZ: Kenar kırağı/buz çerçevesi (frostShimmer 4s) ve buzlu pus küreleri
  void _paintColdFrost(
    Canvas canvas,
    Size size,
    double masterAlpha,
    WeatherAccentSpec spec,
  ) {
    final shimmer =
        0.35 + 0.30 * (0.5 + 0.5 * math.sin((elapsedSeconds / 4.0) * 2 * math.pi));
    final frostColor = isDark
        ? const Color(0xFFA8DADC)
        : const Color(0xFF4A788E);

    // Sol üst ve sağ alt buzlu pus küreleri
    final orb1Center = Offset(size.width * 0.25, size.height * 0.26);
    final orb2Center = Offset(size.width * 0.76, size.height * 0.74);
    final orbRadius = size.shortestSide * 0.42;

    final orb1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          frostColor.withOpacity(0.15 * shimmer * masterAlpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: orb1Center, radius: orbRadius));

    final orb2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          spec.dayTint.withOpacity(0.16 * shimmer * masterAlpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: orb2Center, radius: orbRadius));

    canvas.drawCircle(orb1Center, orbRadius, orb1Paint);
    canvas.drawCircle(orb2Center, orbRadius, orb2Paint);

    // Ekran kenarlarında ince kırağı vinyeti
    final borderPaint = Paint()
      ..color = frostColor.withOpacity((isDark ? 0.14 : 0.16) * shimmer * masterAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(18),
      ),
      borderPaint,
    );
  }

  /// 3. YAĞMURLU: 42 deterministik yağmur damlası (12 derece eğimli)
  void _paintRain(
    Canvas canvas,
    Size size,
    double masterAlpha,
    WeatherAccentSpec spec,
    int step,
  ) {
    final dropBaseColor = isDark
        ? const Color(0xFF8AB4D8)
        : const Color(0xFF3E6182);

    for (int i = 0; i < _kRainParticles.length; i += step) {
      final drop = _kRainParticles[i];
      final progress =
          ((elapsedSeconds + drop.delaySeconds) / drop.durationSeconds) % 1.0;

      final startX = drop.leftFraction * size.width;
      final y = -size.height * 0.10 + progress * (size.height * 1.22);
      final x = startX - progress * (size.height * 0.16);

      final alpha = (drop.opacity * (isDark ? 0.55 : 0.48) * masterAlpha)
          .clamp(0.0, 1.0);
      final p1 = Offset(x, y);
      final p2 = Offset(x - 5.5, y + 26.0);

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dropBaseColor.withOpacity(0.0),
            dropBaseColor.withOpacity(alpha),
          ],
        ).createShader(Rect.fromPoints(p1, p2))
        ..strokeWidth = 1.45
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, paint);
    }
  }

  /// 4. KARLI: 36 deterministik kar tanesi (yatay salınımlı)
  void _paintSnow(
    Canvas canvas,
    Size size,
    double masterAlpha,
    WeatherAccentSpec spec,
    int step,
  ) {
    final flakeColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF64748B);

    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final corePaint = Paint();

    for (int i = 0; i < _kSnowParticles.length; i += step) {
      final flake = _kSnowParticles[i];
      final progress =
          ((elapsedSeconds + flake.delaySeconds) / flake.durationSeconds) % 1.0;

      final sway = math.sin(progress * 2 * math.pi + i) * 20.0;
      final x = (flake.leftFraction * size.width + sway) % size.width;
      final y = -size.height * 0.06 + progress * (size.height * 1.12);
      final radius = flake.size * 0.46;

      final alpha = ((isDark ? 0.52 : 0.42) * masterAlpha).clamp(0.0, 1.0);
      glowPaint.color = flakeColor.withOpacity(alpha * 0.45);
      corePaint.color = flakeColor.withOpacity(alpha);

      final c = Offset(x, y);
      canvas.drawCircle(c, radius * 1.5, glowPaint);
      canvas.drawCircle(c, radius, corePaint);
    }
  }

  /// 5. RÜZGARLI: Hareketli bulut katmanları (cloudDrift 14s/18s) ve 14 rüzgar çizgisi
  void _paintWindy(
    Canvas canvas,
    Size size,
    double masterAlpha,
    WeatherAccentSpec spec,
    int step,
  ) {
    final drift1 = math.sin((elapsedSeconds / 14.0) * 2 * math.pi) * size.width * 0.16;
    final drift2 = -math.sin((elapsedSeconds / 18.0) * 2 * math.pi) * size.width * 0.18;

    final cloudColor = isDark
        ? const Color(0xFF6BB5A6)
        : const Color(0xFF4A7C72);

    final cloud1Center = Offset(size.width * 0.30 + drift1, size.height * 0.16);
    final cloud2Center = Offset(size.width * 0.72 + drift2, size.height * 0.44);

    final cloud1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          cloudColor.withOpacity((isDark ? 0.13 : 0.11) * masterAlpha),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: cloud1Center, radius: size.shortestSide * 0.45),
      );
    canvas.drawCircle(cloud1Center, size.shortestSide * 0.45, cloud1Paint);

    final cloud2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          spec.dayTint.withOpacity((isDark ? 0.14 : 0.12) * masterAlpha),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: cloud2Center, radius: size.shortestSide * 0.50),
      );
    canvas.drawCircle(cloud2Center, size.shortestSide * 0.50, cloud2Paint);

    for (int i = 0; i < _kWindStreaks.length; i += step) {
      final streak = _kWindStreaks[i];
      final progress =
          ((elapsedSeconds + streak.delaySeconds) / streak.durationSeconds) % 1.0;

      // Web windSweep: 0->30% fade in, 70->100% fade out
      double streakEnvelope;
      if (progress < 0.3) {
        streakEnvelope = progress / 0.3;
      } else if (progress > 0.7) {
        streakEnvelope = (1.0 - progress) / 0.3;
      } else {
        streakEnvelope = 1.0;
      }

      final x = -streak.width + progress * (size.width + streak.width * 1.4);
      final y = streak.topFraction * size.height;
      final alpha =
          (0.42 * streakEnvelope * masterAlpha).clamp(0.0, 1.0);

      final rect = Rect.fromLTWH(x, y, streak.width, 2.0);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            cloudColor.withOpacity(0.0),
            cloudColor.withOpacity(alpha),
            cloudColor.withOpacity(0.0),
          ],
        ).createShader(rect)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, y),
        Offset(x + streak.width, y),
        paint,
      );
    }
  }

  /// 6. DOLU & FIRTINA: 32 hızlı dolu tanesi (zıplama efektli) ve 6 saniyelik yumuşak şimşek çakması
  void _paintHailAndStorm(
    Canvas canvas,
    Size size,
    double masterAlpha,
    WeatherAccentSpec spec,
    int step,
  ) {
    // Web lightningFlash: 6 saniyelik döngünün %93-%98 aralığında hafif çakma
    final cycle6 = (elapsedSeconds % 6.0) / 6.0;
    if (!lowPerformance &&
        ((cycle6 > 0.93 && cycle6 < 0.95) || (cycle6 > 0.965 && cycle6 < 0.985))) {
      final flashPaint = Paint()
        ..color = const Color(0xFF7DD3FC)
            .withOpacity((isDark ? 0.12 : 0.09) * masterAlpha);
      canvas.drawRect(Offset.zero & size, flashPaint);
    }

    final hailPrimary = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final hailSecondary = const Color(0xFF7DD3FC);

    for (int i = 0; i < _kHailParticles.length; i += step) {
      final stone = _kHailParticles[i];
      final progress =
          ((elapsedSeconds + stone.delaySeconds) / stone.durationSeconds) % 1.0;

      // Web hailFall: %85-92 arasında zeminden hafif sekme (bounce)
      double yFactor;
      if (progress < 0.85) {
        yFactor = (progress / 0.85) * 0.96;
      } else if (progress < 0.92) {
        final b = (progress - 0.85) / 0.07;
        yFactor = 0.96 - b * 0.06;
      } else {
        final b = (progress - 0.92) / 0.08;
        yFactor = 0.90 + b * 0.14;
      }

      final startX = stone.leftFraction * size.width;
      final x = startX - progress * (size.width * 0.11);
      final y = -size.height * 0.08 + yFactor * (size.height * 1.04);
      final r = stone.size * 0.45;

      final alpha = ((isDark ? 0.62 : 0.50) * masterAlpha).clamp(0.0, 1.0);
      final trailPaint = Paint()
        ..color = hailSecondary.withOpacity(alpha * 0.35)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x + 3.0, y - 10.0), Offset(x, y), trailPaint);

      final stonePaint = Paint()
        ..color = Color.lerp(hailPrimary, hailSecondary, 0.35)!
            .withOpacity(alpha);
      canvas.drawCircle(Offset(x, y), r, stonePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherAtmospherePainter oldDelegate) {
    return oldDelegate.elapsedSeconds != elapsedSeconds ||
        oldDelegate.currentCategory != currentCategory ||
        oldDelegate.previousCategory != previousCategory ||
        oldDelegate.crossFadeProgress != crossFadeProgress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isNight != isNight ||
        oldDelegate.lowPerformance != lowPerformance;
  }
}
