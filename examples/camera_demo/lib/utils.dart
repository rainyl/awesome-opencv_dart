import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:opencv_core/opencv.dart' as cv;

extension CvMatUiImageExtension on cv.Mat {
  Future<ui.Image> toUiImage({ui.PixelFormat format = ui.PixelFormat.bgra8888}) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(data, width, height, format, completer.complete);
    return completer.future;
  }
}

Uint8List convertYUV420ToNV21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  // Planes from CameraImage
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  // Buffers from Y, U, and V planes
  final yBuffer = yPlane.bytes;
  final uBuffer = uPlane.bytes;
  final vBuffer = vPlane.bytes;
  // Total number of pixels in NV21 format
  final numPixels = width * height + (width * height ~/ 2);
  final nv21 = Uint8List(numPixels);
  // Y (Luma) plane metadata
  int idY = 0;
  int idUV = width * height; // Start UV after Y plane
  final uvWidth = width ~/ 2;
  final uvHeight = height ~/ 2;
  // Strides and pixel strides for Y and UV planes
  final yRowStride = yPlane.bytesPerRow;
  final yPixelStride = yPlane.bytesPerPixel ?? 1;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 2;
  // Copy Y (Luma) channel
  for (int y = 0; y < height; ++y) {
    final yOffset = y * yRowStride;
    for (int x = 0; x < width; ++x) {
      nv21[idY++] = yBuffer[yOffset + x * yPixelStride];
    }
  }
  // Copy UV (Chroma) channels in NV21 format (YYYYVU interleaved)
  for (int y = 0; y < uvHeight; ++y) {
    final uvOffset = y * uvRowStride;
    for (int x = 0; x < uvWidth; ++x) {
      final bufferIndex = uvOffset + (x * uvPixelStride);
      nv21[idUV++] = vBuffer[bufferIndex]; // V channel
      nv21[idUV++] = uBuffer[bufferIndex]; // U channel
    }
  }
  return nv21;
}
