import 'package:flutter/material.dart';

class ClinicalOnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const ClinicalOnboardingScreen({super.key, required this.onComplete});

  @override
  State<ClinicalOnboardingScreen> createState() => _ClinicalOnboardingScreenState();
}

class _ClinicalOnboardingScreenState extends State<ClinicalOnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _slides = [
    _OnboardSlide(
      icon: Icons.monitor_heart_outlined,
      title: 'Rapid Clinical Triage',
      body: 'Submit your medical emergency in seconds. The system grades severity using the Emergency Severity Index (ESI) and routes your claim instantly.',
      color: Color(0xFF0D9488),
    ),
    _OnboardSlide(
      icon: Icons.receipt_long_outlined,
      title: 'Digital Invoice Scanner',
      body: 'Attach any hospital bill, pharmacy receipt, or lab invoice. The app scans and verifies it automatically — no manual data entry needed.',
      color: Color(0xFF0284C7),
    ),
    _OnboardSlide(
      icon: Icons.payments_outlined,
      title: 'Instant Copay Relief',
      body: 'Approved copay grants are disbursed in under 60 seconds. Track every dollar from claim to payment in real time.',
      color: Color(0xFF0F766E),
    ),
    _OnboardSlide(
      icon: Icons.psychology_outlined,
      title: '24/7 First Aid & Support',
      body: 'Feeling overwhelmed? Our confidential health assistant provides guidance around the clock — completely private, no cloud required.',
      color: Color(0xFF0D9488),
    ),
  ];

  void _next() {
    if (_page < _slides.length - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: s.color.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, size: 48, color: s.color),
                        ),
                        const SizedBox(height: 32),
                        Text(s.title,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: s.color),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(s.body,
                            style: const TextStyle(
                                fontSize: 15,
                                color: Colors.grey,
                                height: 1.6),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? const Color(0xFF0D9488)
                        : const Color(0xFF0D9488).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _page < _slides.length - 1 ? 'Next' : 'Get Started',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OnboardSlide {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  const _OnboardSlide(
      {required this.icon,
      required this.title,
      required this.body,
      required this.color});
}
