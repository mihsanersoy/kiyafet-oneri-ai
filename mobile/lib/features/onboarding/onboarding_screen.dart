import 'package:flutter/material.dart';
import '../../core/theme/marble_background_painter.dart';
import '../../core/theme/optiwear_theme.dart';
import 'onboarding_data.dart';

enum _OnboardingStage {
  welcome,
  sections,
  completed,
}

/// OptiWear Uygulama Tanıtım Eğitimi (Onboarding) Ekranı
/// - Oyun tarzı ekran karartma veya konfeti/puan/rozet içermez; sakin mermer kart akışıyla çalışır.
/// - 1. Aşama (Karşılama): Tek cümlelik tanıtım, "Başla" ve "Eğitimi Atla" butonları.
/// - 2. Aşama (Bölümler): 4 ana bölüm sırayla gelir. Her bölüm 3-4 kartlık yatay `PageView` akışıdır.
///   Nokta göstergesi, "Geri", "İleri", "Bu bölümü atla" ve "Eğitimi bitir" seçenekleri net ayrılmıştır.
/// - 3. Aşama (Bitiş): "Hazırsın" kartı ve "Uygulamaya Geç" butonu.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  final List<OnboardingSection> sections;

  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.sections = kOptiWearOnboardingSections,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _OnboardingStage _stage = _OnboardingStage.welcome;
  int _sectionIndex = 0;
  int _cardIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  OnboardingSection get _currentSection => widget.sections[_sectionIndex];

  void _startOnboarding() {
    setState(() {
      _stage = _OnboardingStage.sections;
      _sectionIndex = 0;
      _cardIndex = 0;
    });
  }

  void _finishEntireOnboarding() {
    widget.onFinished();
  }

  void _skipCurrentSection() {
    if (_sectionIndex < widget.sections.length - 1) {
      setState(() {
        _sectionIndex++;
        _cardIndex = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } else {
      setState(() => _stage = _OnboardingStage.completed);
    }
  }

  void _goNextCardOrSection() {
    final cardsCount = _currentSection.cards.length;
    if (_cardIndex < cardsCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else {
      _skipCurrentSection();
    }
  }

  void _goPreviousCardOrSection() {
    if (_cardIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else if (_sectionIndex > 0) {
      final prevSectionIdx = _sectionIndex - 1;
      final lastCardIdx = widget.sections[prevSectionIdx].cards.length - 1;
      setState(() {
        _sectionIndex = prevSectionIdx;
        _cardIndex = lastCardIdx;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(lastCardIdx);
        }
      });
    } else {
      setState(() => _stage = _OnboardingStage.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ow = OptiWearTheme.of(context);

    return Scaffold(
      backgroundColor: ow.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: MarbleSurfaceBackground(),
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _buildActiveStage(context, ow),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStage(BuildContext context, OptiWearTheme ow) {
    switch (_stage) {
      case _OnboardingStage.welcome:
        return _buildWelcomeStage(context, ow);
      case _OnboardingStage.sections:
        return _buildSectionFlowStage(context, ow);
      case _OnboardingStage.completed:
        return _buildCompletionStage(context, ow);
    }
  }

  /// 1. AŞAMA: KARŞILAMA EKRANI
  Widget _buildWelcomeStage(BuildContext context, OptiWearTheme ow) {
    return Center(
      key: const ValueKey('onboarding_welcome'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Semantics(
            container: true,
            label: 'OptiWear karşılama ekranı',
            child: MarbleCard(
              padding: const EdgeInsets.all(26),
              borderRadius: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: ow.elevatedSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ow.cardBorder),
                        ),
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 32,
                          width: 32,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'OptiWear’a Hoş Geldin',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: ow.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'OptiWear, bulunduğun yerin hava durumunu, fiziksel yapını ve geçmiş deneyimlerini birleştirerek her gün ne giymen gerektiğini sade bir dille önerir.',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.48,
                      color: ow.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.sections
                        .map(
                          (sec) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: ow.elevatedSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: ow.cardBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  sec.icon,
                                  size: 15,
                                  color: ow.effectiveAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  sec.title,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ow.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    button: true,
                    label: 'Tanıtım eğitimine başla',
                    child: FilledButton(
                      onPressed: _startOnboarding,
                      child: const Text('Başla'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    button: true,
                    label: 'Eğitimi atla ve doğrudan uygulamaya geç',
                    child: OutlinedButton(
                      onPressed: _finishEntireOnboarding,
                      child: const Text('Eğitimi Atla'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 2. AŞAMA: BÖLÜM VE YATAY KART AKIŞI (PageView)
  Widget _buildSectionFlowStage(BuildContext context, OptiWearTheme ow) {
    final section = _currentSection;
    final totalSections = widget.sections.length;
    final cards = section.cards;

    return Center(
      key: ValueKey('onboarding_section_${section.id}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üst Bar: Bölüm bilgisi + Her zaman görünen "Eğitimi bitir" (Atla) butonu
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ow.elevatedSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ow.cardBorder),
                    ),
                    child: Text(
                      'Bölüm ${_sectionIndex + 1} / $totalSections',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ow.effectiveAccent,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Tüm eğitimi bitir ve uygulamaya geç',
                    child: TextButton.icon(
                      onPressed: _finishEntireOnboarding,
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Eğitimi bitir'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Bölüm Başlığı ve Sekme Seçici
              Row(
                children: [
                  Icon(section.icon, color: ow.effectiveAccent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: ow.textPrimary,
                      ),
                    ),
                  ),
                  if (_sectionIndex < totalSections - 1)
                    Semantics(
                      button: true,
                      label: 'Bu bölümü atla ve sonraki bölüme geç',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _skipCurrentSection,
                        child: const Text(
                          'Bu bölümü atla →',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                section.subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: ow.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Yatay Kaydırmalı Kartlar (PageView) - Küçük ekranlarda ve büyük fontlarda kaydırılabilir
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: cards.length,
                  onPageChanged: (idx) {
                    setState(() => _cardIndex = idx);
                  },
                  itemBuilder: (context, idx) {
                    final card = cards[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: Semantics(
                        container: true,
                        label:
                            '${section.title}, Kart ${idx + 1} / ${cards.length}: ${card.title}. ${card.description}',
                        child: MarbleCard(
                          padding: const EdgeInsets.all(20),
                          borderRadius: 20,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OnboardingCardPreviewWidget(card: card),
                                const SizedBox(height: 18),
                                Text(
                                  card.title,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: ow.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  card.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.48,
                                    color: ow.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Nokta Göstergesi (Page Indicator)
              Semantics(
                label:
                    'Kart ${_cardIndex + 1} / ${cards.length}',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(cards.length, (idx) {
                    final isSelected = idx == _cardIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: isSelected ? 22 : 8,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? ow.effectiveAccent
                            : ow.veinMedium.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),

              // Alt Gezinme Butonları: Geri ve İleri / Sonraki Bölüm
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Önceki karta dön',
                      child: OutlinedButton.icon(
                        onPressed: _goPreviousCardOrSection,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Geri'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Semantics(
                      button: true,
                      label: _cardIndex < cards.length - 1
                          ? 'Sonraki karta ilerle'
                          : (_sectionIndex < totalSections - 1
                              ? 'Sonraki bölüme geç'
                              : 'Eğitimi tamamla'),
                      child: FilledButton.icon(
                        onPressed: _goNextCardOrSection,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          _cardIndex < cards.length - 1
                              ? 'İleri'
                              : (_sectionIndex < totalSections - 1
                                  ? 'Sonraki Bölüm'
                                  : 'Tamamla'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3. AŞAMA: BİTİŞ KARTI ("Hazırsın" -> "Uygulamaya Geç")
  Widget _buildCompletionStage(BuildContext context, OptiWearTheme ow) {
    return Center(
      key: const ValueKey('onboarding_completed'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Semantics(
            container: true,
            label: 'Tanıtım tamamlandı, hazırsın ekranı',
            child: MarbleCard(
              padding: const EdgeInsets.all(26),
              borderRadius: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ow.effectiveAccent.withOpacity(0.16),
                        border: Border.all(color: ow.effectiveAccent),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 30,
                        color: ow.effectiveAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hazırsın',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: ow.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Artık bulunduğun konuma göre kombin önerisi alabilir, günlük rutin bildirimlerini kurabilir ve seyahat valizini planlayabilirsin. Bu tanıtımı dilediğin zaman Profilim ekranından tekrar açabilirsin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.48,
                      color: ow.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    button: true,
                    label: 'Uygulamaya geç',
                    child: FilledButton(
                      onPressed: _finishEntireOnboarding,
                      child: const Text('Uygulamaya Geç'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
