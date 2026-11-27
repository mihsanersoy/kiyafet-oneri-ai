import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'optiwear_theme.dart';

/// Büyük yüzeyler için düşük opaklıkta prosedürel mermer damar dokusu.
/// - Yumuşak bezier damar çizgileri ve Linear/RadialGradient katmanlarını
///   `ui.Picture` olarak bellekte cache'ler (her karede yeniden hesaplamaz).
/// - `RepaintBoundary` ile izole edilmiştir; içeriğin önüne geçmez ve APK boyutunu şişirmez.
class MarbleSurfaceBackground extends StatelessWidget {
  final Widget? child;
  final double opacityScale;

  const MarbleSurfaceBackground({
    super.key,
    this.child,
    this.opacityScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final ow = OptiWearTheme.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CachedMarbleVeinPainter(
          isDark: ow.isDark,
          veinLight: ow.veinLight,
          veinMedium: ow.veinMedium,
          veinStrong: ow.veinStrong,
          weatherTint: ow.weatherTint,
          weatherTintOpacity: ow.weatherTintOpacity,
          opacityScale: opacityScale,
        ),
        child: child,
      ),
    );
  }
}

class _CachedMarbleVeinPainter extends CustomPainter {
  final bool isDark;
  final Color veinLight;
  final Color veinMedium;
  final Color veinStrong;
  final Color weatherTint;
  final double weatherTintOpacity;
  final double opacityScale;

  static ui.Picture? _cachedPicture;
  static Size? _cachedSize;
  static int? _cachedSignature;

  const _CachedMarbleVeinPainter({
    required this.isDark,
    required this.veinLight,
    required this.veinMedium,
    required this.veinStrong,
    required this.weatherTint,
    required this.weatherTintOpacity,
    required this.opacityScale,
  });

  int get _signature => Object.hash(
        isDark,
        veinLight.value,
        veinMedium.value,
        veinStrong.value,
        (opacityScale * 100).round(),
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 1. Hava durumu yarı saydam tint katmanı (%8-15 arası)
    final tintPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.65, -0.65),
        radius: 1.35,
        colors: [
          weatherTint.withOpacity((weatherTintOpacity * 0.95).clamp(0.0, 0.18)),
          weatherTint.withOpacity((weatherTintOpacity * 0.35).clamp(0.0, 0.10)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, tintPaint);

    // 2. Prosedürel Mermer Damar Dokusu (Picture Cache ile sıfır CPU maliyeti)
    final sig = _signature;
    if (_cachedPicture == null || _cachedSize != size || _cachedSignature != sig) {
      _cachedPicture = _recordMarbleVeins(size);
      _cachedSize = size;
      _cachedSignature = sig;
    }

    canvas.drawPicture(_cachedPicture!);
  }

  ui.Picture _recordMarbleVeins(Size size) {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Offset.zero & size);
    final w = size.width;
    final h = size.height;

    final baseAlpha = (isDark ? 0.11 : 0.14) * opacityScale;

    // Yumuşak taş gölge bulutları (RadialGradient katmanları)
    final mineralCloud1 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.55, -0.35),
        radius: 0.95,
        colors: [
          veinLight.withOpacity(baseAlpha * 0.75),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    c.drawRect(Offset.zero & size, mineralCloud1);

    final mineralCloud2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.45, 0.55),
        radius: 1.1,
        colors: [
          veinMedium.withOpacity(baseAlpha * 0.55),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    c.drawRect(Offset.zero & size, mineralCloud2);

    // Ana ve kılcal mermer damarları için kalemler
    final glowVeinPaint = Paint()
      ..color = veinLight.withOpacity(baseAlpha * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    final primaryVeinPaint = Paint()
      ..color = veinMedium.withOpacity(baseAlpha * 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    final fineVeinPaint = Paint()
      ..color = veinStrong.withOpacity(baseAlpha * 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;

    // Damar 1: Sol üstten sağ ortaya diyagonal doğal taş çatlağı
    final vein1 = Path()
      ..moveTo(-w * 0.05, h * 0.12)
      ..cubicTo(w * 0.18, h * 0.16, w * 0.26, h * 0.29, w * 0.48, h * 0.31)
      ..cubicTo(w * 0.68, h * 0.33, w * 0.82, h * 0.46, w * 1.05, h * 0.42);

    // Damar 1 Kılcal Dalı
    final vein1Branch = Path()
      ..moveTo(w * 0.36, h * 0.26)
      ..cubicTo(w * 0.44, h * 0.21, w * 0.56, h * 0.23, w * 0.71, h * 0.17);

    // Damar 2: Orta soldan sağ alta uzanan Carrara/Oniks damarı
    final vein2 = Path()
      ..moveTo(-w * 0.04, h * 0.58)
      ..cubicTo(w * 0.22, h * 0.52, w * 0.39, h * 0.68, w * 0.64, h * 0.63)
      ..cubicTo(w * 0.81, h * 0.60, w * 0.91, h * 0.74, w * 1.04, h * 0.79);

    // Damar 2 Kılcal Dalı
    final vein2Branch = Path()
      ..moveTo(w * 0.52, h * 0.64)
      ..cubicTo(w * 0.61, h * 0.72, w * 0.73, h * 0.77, w * 0.88, h * 0.89);

    // Damar 3: Sağ üstten sol alta ince ikincil damar
    final vein3 = Path()
      ..moveTo(w * 0.88, -h * 0.02)
      ..cubicTo(w * 0.72, h * 0.14, w * 0.65, h * 0.34, w * 0.38, h * 0.47)
      ..cubicTo(w * 0.19, h * 0.56, w * 0.12, h * 0.79, -w * 0.02, h * 0.93);

    for (final p in [vein1, vein2, vein3]) {
      c.drawPath(p, glowVeinPaint);
      c.drawPath(p, primaryVeinPaint);
    }
    c.drawPath(vein1Branch, fineVeinPaint);
    c.drawPath(vein2Branch, fineVeinPaint);

    return recorder.endRecording();
  }

  @override
  bool shouldRepaint(covariant _CachedMarbleVeinPainter oldDelegate) {
    return oldDelegate._signature != _signature ||
        oldDelegate.weatherTint != weatherTint ||
        oldDelegate.weatherTintOpacity != weatherTintOpacity;
  }
}
