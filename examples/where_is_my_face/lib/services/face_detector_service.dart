import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv.dart' as cv;

import '../models/face_detection_result.dart';

class FaceDetectorService {
  cv.FaceDetectorYN? _detector;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load Yunet model from assets
      final modelData = await rootBundle.load("assets/yunet.onnx");
      final modelBytes = modelData.buffer.asUint8List();

      // Save it inside the temporary directory
      final tempPath = '${Directory.systemTemp.path}/yunet.onnx';
      await File(tempPath).writeAsBytes(modelBytes);

      // Initialize the detector
      _detector = cv.FaceDetectorYN.fromFile(
        tempPath,
        '',
        (320, 320),
        scoreThreshold: 0.6,
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing face detector: $e');
    }
  }

  Future<List<FaceDetectionResult>> detectFromBytes(Uint8List imageBytes) async {
    if (!_isInitialized || _detector == null) return [];

    final cv.Mat inputMat = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
    if (inputMat.isEmpty) {
      debugPrint('Error decoding image');
      return [];
    }

    // Detect faces
    final results = await detectFace(inputMat);

    inputMat.dispose();

    return results;
  }

  Future<List<FaceDetectionResult>> detectFace(cv.Mat inputMat) async {
    if (!_isInitialized || _detector == null) {
      throw StateError('Error while loading image or yunet model');
    }

    // Update input size
    _detector!.setInputSize((inputMat.cols, inputMat.rows));

    // Detect faces
    final cv.Mat facesMat = _detector!.detect(inputMat);

    final List<FaceDetectionResult> results = [];

    // Process detections
    for (int i = 0; i < facesMat.rows; i++) {
      // YuNet output format: [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rcm, y_rcm, x_lcm, y_lcm, score]
      final double x = facesMat.at<double>(i, 0);
      final double y = facesMat.at<double>(i, 1);
      final double w = facesMat.at<double>(i, 2);
      final double h = facesMat.at<double>(i, 3);
      final double score = facesMat.at<double>(i, 14);

      final Rect bbox = Rect.fromLTWH(x, y, w, h);

      // Extract 5 facial landmarks (right eye, left eye, nose tip, right mouth corner, left mouth corner)
      final List<math.Point<double>> landmarks = [];
      for (int j = 0; j < 5; j++) {
        final double lx = facesMat.at<double>(i, 4 + j * 2);
        final double ly = facesMat.at<double>(i, 5 + j * 2);
        landmarks.add(math.Point<double>(lx, ly));
      }

      results.add(FaceDetectionResult(bbox, score, landmarks));
    }

    facesMat.dispose();

    return results;
  }

  void dispose() {
    _detector?.dispose();
    _isInitialized = false;
  }
}
