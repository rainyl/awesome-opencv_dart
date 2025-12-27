import 'package:flutter/material.dart';

import '../models/face_detection_result.dart';

class FaceDetectionPainter extends CustomPainter {
  final List<FaceDetectionResult> faces;
  final Size imageSize;
  final Size screenSize;
  final bool isInverted;

  FaceDetectionPainter({
    required this.faces,
    required this.imageSize,
    required this.screenSize,
    this.isInverted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Cyan stroke for the box
    final boxPaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Compute scale ratio
    final scaleX = screenSize.width / imageSize.width;
    final scaleY = screenSize.height / imageSize.height;

    for (final face in faces) {
      final scaledBox = Rect.fromLTWH(
        // When the camera is inverted
        isInverted
            ? screenSize.width -
                  (face.boundingBox.left + face.boundingBox.width) * scaleX
            : face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        face.boundingBox.width * scaleX,
        face.boundingBox.height * scaleY,
      );

      // Draw the main rectangle
      canvas.drawRect(scaledBox, boxPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
