import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ProcessedCameraViewPainter extends CustomPainter {
  ui.Image? image;

  ProcessedCameraViewPainter({required this.image});
  @override
  void paint(Canvas canvas, Size size) {
    if (image != null) {
      paintImage(canvas: canvas, rect: ui.Rect.fromLTWH(0, 0, size.width, size.height), image: image!);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return image == (oldDelegate as ProcessedCameraViewPainter).image;
    // return true;
  }
}
