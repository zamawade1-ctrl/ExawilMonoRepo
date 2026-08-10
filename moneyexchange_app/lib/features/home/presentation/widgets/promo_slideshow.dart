import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One promotional slide: an exchange service and the short number customers
/// dial / send to.
class _PromoSlide {
  const _PromoSlide({
    required this.title,
    required this.service,
    required this.number,
    required this.gradient,
    required this.icon,
  });

  final String title;
  final String service;
  final String number;
  final List<Color> gradient;
  final IconData icon;
}

/// Auto-advancing promo carousel shown at the top of the Home tab. Advertises
/// the exchange short-numbers customers use to top up / send, one slide each,
/// with a page-dot indicator. Tapping a slide copies its number to the
/// clipboard so it's easy to paste into the dialer.
///
/// The numbers are the product's own advertised exchange lines:
///   - Telesom Exchange: 313933
///   - e-Dahab:          654480003
class PromoSlideshow extends StatefulWidget {
  const PromoSlideshow({super.key});

  @override
  State<PromoSlideshow> createState() => _PromoSlideshowState();
}

class _PromoSlideshowState extends State<PromoSlideshow> {
  static const _slides = <_PromoSlide>[
    _PromoSlide(
      title: 'Telesom Exchange',
      service: 'Ka sarifo sariflaha gudaal',
      number: '313933',
      gradient: [Color(0xFF2FA84F), Color(0xFF1B7E39)],
      icon: Icons.currency_exchange,
    ),
    _PromoSlide(
      title: 'e-Dahab',
      service: 'Ka sarifo sariflaha gudaal',
      number: '654480003',
      gradient: [Color(0xFF1E6BB8), Color(0xFF0E4C8A)],
      icon: Icons.account_balance_wallet,
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

  Future<void> _copyNumber(_PromoSlide slide) async {
    await Clipboard.setData(ClipboardData(text: slide.number));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${slide.title} number ${slide.number} copied'),
        duration: const Duration(seconds: 2),
      ),
    );
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
            itemBuilder: (_, i) => _PromoCard(
              slide: _slides[i],
              onTap: () => _copyNumber(_slides[i]),
            ),
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
  const _PromoCard({required this.slide, required this.onTap});

  final _PromoSlide slide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
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
                        Text(
                          slide.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          slide.service,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              slide.number,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ],
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
        ),
      ),
    );
  }
}
