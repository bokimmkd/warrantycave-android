import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() => context.read<AppController>().completeOnboarding();

  @override
  Widget build(BuildContext context) {
    final slides = <({String title, String copy, IconData icon})>[
      (title: context.l10n.text('introTitle1'), copy: context.l10n.text('introCopy1'), icon: Icons.inventory_2_outlined),
      (title: context.l10n.text('introTitle2'), copy: context.l10n.text('introCopy2'), icon: Icons.receipt_long_outlined),
      (title: context.l10n.text('introTitle3'), copy: context.l10n.text('introCopy3'), icon: Icons.notifications_active_outlined),
      (title: context.l10n.text('introTitle4'), copy: context.l10n.text('introCopy4'), icon: Icons.picture_as_pdf_outlined),
    ];
    return Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _CaveBackdrop()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(context.l10n.text('introSkip')),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: slides.length,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemBuilder: (context, index) {
                      final slide = slides[index];
                      return SingleChildScrollView(
                        child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [skyBlue, caveBlue, caveNavy]),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Icon(slide.icon, size: 55, color: Colors.white),
                          ),
                          const SizedBox(height: 24),
                          const BrandMark(),
                          const SizedBox(height: 30),
                          Text(slide.title, textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: caveNavy)),
                          const SizedBox(height: 14),
                          Text(slide.copy, textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF526E84), height: 1.45, fontSize: 15)),
                        ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(slides.length, (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == index ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == index ? caveBlue : const Color(0xFFB9D2E5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: context.l10n.text(_page == slides.length - 1 ? 'getStarted' : 'introNext'),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _page == slides.length - 1
                    ? _finish()
                    : _pages.nextPage(duration: const Duration(milliseconds: 240), curve: Curves.easeOut),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  }
}

class _CaveBackdrop extends StatelessWidget {
  const _CaveBackdrop();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BackdropPainter(), child: const SizedBox.expand());
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wash = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xFFF4FAFE), Color(0xFFE5F3FB)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, wash);

    final mountain = Path()
      ..moveTo(0, size.height * .63)
      ..lineTo(size.width * .18, size.height * .49)
      ..lineTo(size.width * .34, size.height * .61)
      ..lineTo(size.width * .57, size.height * .42)
      ..lineTo(size.width * .78, size.height * .58)
      ..lineTo(size.width, size.height * .46)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(mountain, Paint()..color = const Color(0x1F60A5FA));

    final cave = Path()
      ..moveTo(size.width * .61, size.height)
      ..quadraticBezierTo(
        size.width * .72,
        size.height * .67,
        size.width,
        size.height * .61,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(cave, Paint()..color = const Color(0x2414B8A6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
