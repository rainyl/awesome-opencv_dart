import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv.dart' as cv;

import '../components/extracted_faces_dialog.dart';
import '../models/face_detection_result.dart';
import '../painter/face_detection_painter.dart';
import '../services/face_detector_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  bool _isFlashOn = false;
  final _faceDetectorService = FaceDetectorService();
  List<FaceDetectionResult> _detectedFaces = [];
  XFile? _picture;
  Timer? _timer;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    _controller = CameraController(
      _cameras[_currentCameraIndex],
      ResolutionPreset.high,
    );

    _controller!.initialize().then((_) async {
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });

      await _faceDetectorService.initialize();

      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _processFrame();
      });
    });
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;

    // Stop processing frames
    _timer?.cancel();
    _isProcessing = false;

    setState(() {
      _isCameraInitialized = false;
      _detectedFaces = [];
    });

    // Dispose old controller
    await _controller?.dispose();

    // Switch camera index
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

    // Initialize new camera
    _controller = CameraController(
      _cameras[_currentCameraIndex],
      ResolutionPreset.high,
    );

    await _controller!.initialize();

    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
      _isFlashOn = false; // Reset flash when switching cameras
    });

    // Restart frame processing
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _processFrame();
    });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    setState(() {
      _isFlashOn = !_isFlashOn;
    });

    await _controller!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceDetectorService.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraInitialized
          ? Stack(
              fit: StackFit.expand,
              children: [
                // Camera Preview
                CameraPreview(_controller!),

                // Face Detection Overlay
                CustomPaint(
                  painter: FaceDetectionPainter(
                    faces: _detectedFaces,
                    isInverted: _currentCameraIndex != 0,
                    imageSize: Size(
                      _controller!.value.previewSize!.height,
                      _controller!.value.previewSize!.width,
                    ),
                    screenSize: MediaQuery.sizeOf(context),
                  ),
                ),

                // Top Bar
                _buildTopBar(),

                // Status Indicator
                if (_detectedFaces.isNotEmpty) _buildStatusIndicator(),

                // Bottom Controls
                _buildBottomControls(),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Settings Button
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                onPressed: () {
                  // Settings action
                },
              ),
            ),

            // Title
            const Text(
              'Face Detector',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),

            // Flash Button
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: _toggleFlash,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 80),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.cyan,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_detectedFaces.length} FACE${_detectedFaces.length > 1 ? 'S' : ''} DETECTED',
                style: const TextStyle(
                  color: Colors.cyan,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Camera Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Gallery Button
                  GestureDetector(
                    onTap: _pickImageFromGallery,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                      child: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),

                  // Capture Button
                  GestureDetector(
                    onTap: extract,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),

                  // Flip Camera Button
                  GestureDetector(
                    onTap: _toggleCamera,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Version Info
            const Text(
              'V1.2.0 • AI ACTIVE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Extract detected faces from the last captured picture
  Future<void> extract() async {
    if (_detectedFaces.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucun visage détecté')));
      return;
    }

    if (_picture == null) return;

    final bytes = await _picture?.readAsBytes();

    final cv.Mat image = cv.imdecode(bytes!, cv.IMREAD_COLOR);

    List<Uint8List> extractedFaces = [];
    for (final face in _detectedFaces) {
      final rect = cv.Rect(
        face.boundingBox.left.toInt(),
        face.boundingBox.top.toInt(),
        face.boundingBox.width.toInt(),
        face.boundingBox.height.toInt(),
      );

      final cv.Mat faceMat = image.region(rect);
      final (_, faceBytes) = cv.imencode('.jpg', faceMat);
      extractedFaces.add(faceBytes);
      faceMat.dispose();
    }

    image.dispose();

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => ExtractedFacesDialog(faces: extractedFaces),
      );
    }
  }

  /// Process a single frame from the camera
  Future<void> _processFrame() async {
    if (!_isCameraInitialized || _isProcessing) return;

    // Check if controller is still valid
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isProcessing = true;

    try {
      _picture = await _controller!.takePicture();
      final bytes = await _picture?.readAsBytes();

      if (bytes != null) {
        final faces = await _faceDetectorService.detectFromBytes(bytes);

        if (mounted) {
          setState(() => _detectedFaces = faces);
        }
      }
    } catch (e) {
      // Ignore errors during camera switching
      debugPrint('Error processing frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Pick image from gallery and process it
  Future<void> _pickImageFromGallery() async {
    // Implement image picking from gallery
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final faces = await _faceDetectorService.detectFromBytes(bytes);

      if (mounted) {
        setState(() {
          _detectedFaces = faces;
          _picture = image;
        });
      }

      // Show dialog with extracted faces
      if (faces.isNotEmpty && mounted) {
        List<Uint8List> extractedFaces = [];
        final cv.Mat imgMat = cv.imdecode(bytes, cv.IMREAD_COLOR);

        for (final face in faces) {
          final rect = cv.Rect(
            face.boundingBox.left.toInt(),
            face.boundingBox.top.toInt(),
            face.boundingBox.width.toInt(),
            face.boundingBox.height.toInt(),
          );

          final cv.Mat faceMat = imgMat.region(rect);
          final (_, faceBytes) = cv.imencode('.jpg', faceMat);
          extractedFaces.add(faceBytes);
          faceMat.dispose();
        }

        imgMat.dispose();

        showDialog(
          context: context,
          builder: (context) => ExtractedFacesDialog(faces: extractedFaces),
        );
      }
    }
  }
}
