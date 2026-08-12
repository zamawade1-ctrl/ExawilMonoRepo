import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/config/app_info.dart';

/// One promotional slide advertising an app feature/benefit — no third-party
/// exchange numbers, just what e-Xawil does for the user.
class _PromoSlide {
  const _PromoSlide({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
}

/// Auto-advancing promo carousel shown at the top of the Home tab. It advertises
/// **the app itself** — its automatic-forwarding value props — one slide each,
/// with a page-dot indicator. It deliberately shows NO exchange short-numbers or
/// third-party services; it's pure app promotion.
class PromoSlideshow extends StatefulWidget {
  const PromoSlideshow({super.key});

  @override
  State<PromoSlideshow> createState() => _PromoSlideshowState();
}

class _PromoSlideshowState extends State<PromoSlideshow> {
  static const _slides = <_PromoSlide>[
    _PromoSlide(
      title: 'e-Xawil auto-forwarding',
      subtitle: 'Your Zaad money is forwarded to your destination automatically.',
      gradient: [Color(0xFF26A65B), Color(0xFF1B7E39)],
      icon: Icons.autorenew,
    ),
    _PromoSlide(
      title: 'Set it and forget it',
      subtitle: 'We watch for incoming money and send it on for you — hands-free.',
      gradient: [Color(0xFF2E8B57), Color(0xFF176B44)],
      icon: Icons.bolt,
    ),
    _PromoSlide(
      title: 'Private by design',
      subtitle: 'Your PINs stay encrypted on your phone — never on a server.',
      gradient: [Color(0xFF2FA84F), Color(0xFF1E7E3C)],
      icon: Icons.lock_outline,
    ),
  ];

  static const _autoAdvance = Duration(seconds: 5);
  static const _slideHeight = 150.0;

  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoAdvance() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoAdvance, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % _slides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: _slideHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _PromoCard(slide: _slides[i]),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.slide});

  final _PromoSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: slide.gradient,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand header: the app icon + name, so every banner carries
                    // the e-Xawil identity.
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/branding/app_icon.png',
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.bolt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppInfo.appName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      slide.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slide.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(slide.icon, color: Colors.white, size: 30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
