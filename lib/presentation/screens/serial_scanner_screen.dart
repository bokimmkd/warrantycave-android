import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';

class SerialScannerScreen extends StatefulWidget {
  const SerialScannerScreen({super.key});

  @override
  State<SerialScannerScreen> createState() => _SerialScannerScreenState();
}

class _SerialScannerScreenState extends State<SerialScannerScreen> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool completed = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void onDetect(BarcodeCapture capture) {
    if (completed) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        completed = true;
        controller.stop();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(context.l10n.text('scanTitle')),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: context.l10n.text('toggleFlashlight'),
          onPressed: controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final scanWindow = scannerWindowFor(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              scanWindow: scanWindow,
              onDetect: onDetect,
            ),
            _ScannerOverlay(scanWindow: scanWindow),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: caveNavy.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    context.l10n.text('scanHint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

@visibleForTesting
Rect scannerWindowFor(Size size) => Rect.fromCenter(
  center: Offset(size.width / 2, size.height * .42),
  width: size.width * .82,
  height: size.width * .48,
);

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _ScannerOverlayPainter(scanWindow)),
  );
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: .46);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, shade);
    final border = Paint()
      ..color = caveTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(24)),
      border,
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(frame.left + 22, frame.center.dy),
      Offset(frame.right - 22, frame.center.dy),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
