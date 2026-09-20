import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _CaveBackdrop()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [skyBlue, caveBlue, caveNavy],
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x330F4C81),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    size: 55,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const BrandMark(),
                const SizedBox(height: 8),
                const Text(
                  'S C A N  •  S T O R E  •  R E L A X',
                  style: TextStyle(
                    color: caveBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  context.l10n.text('welcomeCopy'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF526E84),
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
                const Spacer(flex: 3),
                PrimaryButton(
                  label: context.l10n.text('getStarted'),
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () =>
                      context.read<AppController>().completeOnboarding(),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.text('peaceStarts'),
                  style: AppTypography.muted,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
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
