import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class CropImageScreen extends StatefulWidget {
  const CropImageScreen({super.key, required this.bytes});

  final Uint8List bytes;

  static const Color bg = Color(0xFF1B1E23);
  static const Color gold = Color(0xFFE2C078);

  @override
  State<CropImageScreen> createState() => _CropImageScreenState();
}

class _CropImageScreenState extends State<CropImageScreen> {
  final CropController _controller = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CropImageScreen.bg,
      appBar: AppBar(
        backgroundColor: CropImageScreen.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Crop',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _isCropping
                ? null
                : () {
                    setState(() => _isCropping = true);
                    _controller.crop();
                  },
            child: Text(
              _isCropping ? '...' : 'Done',
              style: const TextStyle(
                color: CropImageScreen.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const sidePadding = 20.0;
            const verticalPadding = 0.0;

            final maxW = (constraints.maxWidth - sidePadding * 2).clamp(
              0.0,
              constraints.maxWidth,
            );
            final maxH = (constraints.maxHeight - verticalPadding * 2).clamp(
              0.0,
              constraints.maxHeight,
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Image.memory(
                    widget.bytes,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(color: Colors.black.withOpacity(0.35)),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: sidePadding,
                      vertical: verticalPadding,
                    ),
                    child: SizedBox(
                      width: maxW,
                      height: maxH,
                      child: Crop(
                        controller: _controller,
                        image: widget.bytes,
                        initialRectBuilder: InitialRectBuilder.withBuilder(
                          (viewportRect, imageRect) => imageRect,
                        ),
                        overlayBuilder: (context, rect) {
                          return const SizedBox.expand(
                            child: CustomPaint(painter: _CropOverlayPainter()),
                          );
                        },
                        cornerDotBuilder: (size, edgeAlignment) {
                          return _CropCornerHandle(
                            size: size,
                            alignment: edgeAlignment,
                          );
                        },
                        onCropped: (result) {
                          if (result is CropSuccess) {
                            Navigator.of(
                              context,
                            ).pop<Uint8List>(result.croppedImage);
                            return;
                          }

                          if (result is CropFailure) {
                            if (!mounted) return;
                            setState(() => _isCropping = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(result.cause.toString())),
                            );
                          }
                        },
                        baseColor: CropImageScreen.bg,
                        maskColor: Colors.black.withOpacity(0.6),
                        radius: 0,
                        withCircleUi: false,
                        interactive: true,
                        filterQuality: FilterQuality.high,
                        progressIndicator: const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            CropImageScreen.gold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final inset = borderPaint.strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      (size.width - inset * 2).clamp(0.0, size.width),
      (size.height - inset * 2).clamp(0.0, size.height),
    );

    canvas.drawRect(rect, borderPaint);

    final thirdW = rect.width / 3;
    final thirdH = rect.height / 3;

    canvas.drawLine(
      Offset(rect.left + thirdW, rect.top),
      Offset(rect.left + thirdW, rect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(rect.left + thirdW * 2, rect.top),
      Offset(rect.left + thirdW * 2, rect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + thirdH),
      Offset(rect.right, rect.top + thirdH),
      gridPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + thirdH * 2),
      Offset(rect.right, rect.top + thirdH * 2),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => false;
}

class _CropCornerHandle extends StatelessWidget {
  const _CropCornerHandle({required this.size, required this.alignment});

  final double size;
  final EdgeAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final handleThickness = 3.0;
    final handleLength = (size * 0.85).clamp(12.0, 22.0);

    final shift = size / 2;
    Offset translate;
    switch (alignment) {
      case EdgeAlignment.topLeft:
        translate = Offset(shift, shift);
        break;
      case EdgeAlignment.topRight:
        translate = Offset(-shift, shift);
        break;
      case EdgeAlignment.bottomLeft:
        translate = Offset(shift, -shift);
        break;
      case EdgeAlignment.bottomRight:
        translate = Offset(-shift, -shift);
        break;
    }

    return Transform.translate(
      offset: translate,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CornerHandlePainter(
            alignment: alignment,
            thickness: handleThickness,
            length: handleLength,
          ),
        ),
      ),
    );
  }
}

class _CornerHandlePainter extends CustomPainter {
  const _CornerHandlePainter({
    required this.alignment,
    required this.thickness,
    required this.length,
  });

  final EdgeAlignment alignment;
  final double thickness;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.square;

    final inset = thickness / 2;
    final maxL = (size.shortestSide - inset).clamp(0.0, size.shortestSide);
    final l = length.clamp(0.0, maxL);

    switch (alignment) {
      case EdgeAlignment.topLeft:
        canvas.drawLine(Offset(inset, inset), Offset(inset + l, inset), paint);
        canvas.drawLine(Offset(inset, inset), Offset(inset, inset + l), paint);
        return;
      case EdgeAlignment.topRight:
        canvas.drawLine(
          Offset(size.width - inset, inset),
          Offset(size.width - inset - l, inset),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - inset, inset),
          Offset(size.width - inset, inset + l),
          paint,
        );
        return;
      case EdgeAlignment.bottomLeft:
        canvas.drawLine(
          Offset(inset, size.height - inset),
          Offset(inset + l, size.height - inset),
          paint,
        );
        canvas.drawLine(
          Offset(inset, size.height - inset),
          Offset(inset, size.height - inset - l),
          paint,
        );
        return;
      case EdgeAlignment.bottomRight:
        canvas.drawLine(
          Offset(size.width - inset, size.height - inset),
          Offset(size.width - inset - l, size.height - inset),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - inset, size.height - inset),
          Offset(size.width - inset, size.height - inset - l),
          paint,
        );
        return;
    }
  }

  @override
  bool shouldRepaint(covariant _CornerHandlePainter oldDelegate) {
    return oldDelegate.alignment != alignment ||
        oldDelegate.thickness != thickness ||
        oldDelegate.length != length;
  }
}
