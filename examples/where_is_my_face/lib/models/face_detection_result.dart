import 'dart:math' as math;
import 'dart:ui';

class FaceDetectionResult {
  final Rect boundingBox;
  final double score;
  final List<math.Point<double>> landmarks;

  FaceDetectionResult(this.boundingBox, this.score, this.landmarks);
}