import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dartcv4/dartcv.dart' as cv;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optical Flow Example',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: const OpticalFlowPage(),
    );
  }
}

class OpticalFlowPage extends StatefulWidget {
  const OpticalFlowPage({super.key});

  @override
  State<OpticalFlowPage> createState() => _OpticalFlowPageState();
}

class _OpticalFlowPageState extends State<OpticalFlowPage> {
  cv.VideoCapture? _cap;
  cv.Mat? _oldGray;
  cv.Mat? _mask;
  cv.VecPoint2f? _p0;
  final List<cv.Scalar> _colors = [];

  Uint8List? _currentFrameBytes;
  bool _isStreaming = false;
  bool _useCamera = false;
  String? _videoFilePath;
  int _rotation = -1;

  final int _maxCorners = 30;
  final double _qualityLevel = 0.3;
  final int _minDistance = 7;
  final int _blockSize = 7;
  final (int, int) _winSize = (15, 15);
  final int _maxLevel = 2;
  // criteria: type, maxCount, epsilon
  final (int, int, double) _criteria = (cv.TERM_EPS + cv.TERM_COUNT, 10, 0.03);

  @override
  void initState() {
    super.initState();
    // Schedule initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initOpenCV();
    });
  }

  Future<String> _copyAssetToLocal(String assetPath) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final fileName = assetPath.split('/').last;
      final file = File('${docDir.path}/$fileName');

      if (await file.exists()) {
        return file.path;
      }

      // Always overwrite to ensure we have the correct file
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes);

      return file.path;
    } catch (e) {
      debugPrint("Error copying asset: $e");
      rethrow;
    }
  }

  void _cleanupResources() {
    _oldGray?.dispose();
    _mask?.dispose();
    _p0?.dispose();
    _cap?.release();
    _cap?.dispose();

    _oldGray = null;
    _mask = null;
    _p0 = null;
    _cap = null;
  }

  Future<void> _initOpenCV() async {
    try {
      cv.VideoCapture cap;
      if (_useCamera) {
        cap = cv.VideoCapture.fromDevice(0);
        cap.set(cv.CAP_PROP_FOURCC, cv.VideoCapture.toCodec("BGR3"));
        cap.set(cv.CAP_PROP_ORIENTATION_AUTO, 1);
        switch (Platform.operatingSystem) {
          case 'android':
            _rotation = cv.ROTATE_90_CLOCKWISE;
            break;
          default:
        }
      } else {
        // 1. Prepare video file
        _videoFilePath ??= await _copyAssetToLocal('assets/box.mp4');
        cap = cv.VideoCapture.fromFile(_videoFilePath!);
      }

      // 2. Initialize VideoCapture
      if (!cap.isOpened) {
        debugPrint("Failed to open source: ${_useCamera ? 'Camera' : _videoFilePath}");
        return;
      }

      // 3. Generate random colors
      final rng = Random();
      _colors.clear();
      for (int i = 0; i < _maxCorners; i++) {
        _colors.add(
          cv.Scalar(
            rng.nextInt(256).toDouble(),
            rng.nextInt(256).toDouble(),
            rng.nextInt(256).toDouble(),
            255,
          ),
        );
      }

      // 4. Take first frame and find corners
      final (ret, firstFrame) = cap.read();
      if (!ret || firstFrame.isEmpty) {
        debugPrint("Failed to read first frame");
        return;
      }

      // Rotate frame if needed
      if (_rotation != -1) {
        cv.rotate(firstFrame, _rotation, dst: firstFrame);
      }

      // Convert to grayscale
      cv.Mat oldGray;

      if (firstFrame.channels == 1) {
        oldGray = firstFrame.clone();
      } else if (firstFrame.channels == 3) {
        oldGray = cv.cvtColor(firstFrame, cv.COLOR_BGR2GRAY);
      } else if (firstFrame.channels == 4) {
        oldGray = cv.cvtColor(firstFrame, cv.COLOR_BGRA2GRAY);
      } else {
        // Fallback
        oldGray = cv.cvtColor(firstFrame, cv.COLOR_BGR2GRAY);
      }

      // Detect corners
      final p0 = cv.goodFeaturesToTrack(
        oldGray,
        _maxCorners,
        _qualityLevel,
        _minDistance.toDouble(),
        blockSize: _blockSize,
      );

      // 5. Create mask for drawing
      // We want mask to be BGR (3 channels) so we can draw colored lines
      final mask = cv.Mat.zeros(firstFrame.rows, firstFrame.cols, cv.MatType.CV_8UC3);

      // Update state
      if (mounted) {
        setState(() {
          _cap = cap;
          _oldGray = oldGray;
          _p0 = p0;
          _mask = mask;
          _isStreaming = true;
        });
      }

      // Dispose temporary firstFrame (we only kept oldGray)
      firstFrame.dispose();

      // Start processing loop
      _processVideo();
    } catch (e) {
      debugPrint("Error initializing OpenCV: $e");
    }
  }

  void _toggleSource(bool value) {
    if (_useCamera == value) return;

    setState(() {
      _isStreaming = false;
      _currentFrameBytes = null; // Clear display while switching
    });

    // Wait for loop to stop
    Future.delayed(const Duration(milliseconds: 200), () {
      _cleanupResources();
      if (mounted) {
        setState(() {
          _useCamera = value;
        });
        _initOpenCV();
      }
    });
  }

  void _processVideo() async {
    if (!mounted || !_isStreaming || _cap == null) return;

    final startTime = DateTime.now();

    try {
      // 1. Read new frame
      var (ret, frame) = _cap!.read();

      // Handle loop: if end of video, rewind (only for video file)
      if (!ret || frame.isEmpty) {
        frame.dispose(); // Dispose empty frame if any

        if (!_useCamera) {
          // Rewind to beginning, not work on Android
          // https://github.com/opencv/opencv/blob/fe38fc608f6acb8b68953438a62305d8318f4fcd/modules/videoio/src/cap_android_mediandk.cpp#L242
          _cap!.set(cv.CAP_PROP_POS_FRAMES, 0);

          // Read again
          final (ret2, frame2) = _cap!.read();
          if (!ret2 || frame2.isEmpty) {
            frame2.dispose();
            return; // Failed to rewind/read
          }
          // Rotate frame if needed
          if (_rotation != -1) {
            cv.rotate(frame, _rotation, dst: frame);
          }

          // Reset Logic for loop
          _mask?.setTo(cv.Scalar.all(0)); // Clear mask

          cv.Mat newGray;
          if (frame2.channels == 1) {
            newGray = frame2.clone();
          } else if (frame2.channels == 3) {
            newGray = cv.cvtColor(frame2, cv.COLOR_BGR2GRAY);
          } else if (frame2.channels == 4) {
            newGray = cv.cvtColor(frame2, cv.COLOR_BGRA2GRAY);
          } else {
            newGray = cv.cvtColor(frame2, cv.COLOR_BGR2GRAY);
          }

          _oldGray?.dispose();
          _oldGray = newGray;

          _p0?.dispose();
          _p0 = cv.goodFeaturesToTrack(
            newGray,
            _maxCorners,
            _qualityLevel,
            _minDistance.toDouble(),
            blockSize: _blockSize,
          );

          // Display this frame and wait for next iteration
          _setCurrentFrame(frame2);
          frame2.dispose();

          // Schedule next
          if (mounted && _isStreaming) {
            Future.delayed(const Duration(milliseconds: 33), _processVideo);
          }
        }
        return;
      }

      // Rotate frame if needed
      if (_rotation != -1) {
        cv.rotate(frame, _rotation, dst: frame);
      }

      // 2. Prepare Gray and Display/Color frames
      cv.Mat frameGray;
      cv.Mat frameDisplay;

      // Determine conversions based on channel count
      if (frame.channels == 1) {
        // Input is Gray
        frameGray = frame.clone();
        frameDisplay = cv.cvtColor(frame, cv.COLOR_GRAY2BGR);
      } else if (frame.channels == 3) {
        // Input is BGR
        frameGray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY);
        frameDisplay = frame.clone();
      } else if (frame.channels == 4) {
        // Input is BGRA
        frameGray = cv.cvtColor(frame, cv.COLOR_BGRA2GRAY);
        frameDisplay = cv.cvtColor(frame, cv.COLOR_BGRA2BGR);
      } else {
        // Fallback
        frameGray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY);
        frameDisplay = frame.clone();
      }

      // 3. Calculate Optical Flow
      if (_p0 != null && _p0!.isNotEmpty && _oldGray != null) {
        // p0: prev points, p1: next points
        final (p1, st, err) = cv.calcOpticalFlowPyrLK(
          _oldGray!,
          frameGray,
          _p0!,
          cv.VecPoint2f(), // Output container
          winSize: _winSize,
          maxLevel: _maxLevel,
          criteria: _criteria,
        );

        final goodNew = <cv.Point2f>[];
        final goodOld = <cv.Point2f>[];

        // 4. Select good points
        for (int i = 0; i < (st?.length ?? 0); i++) {
          // st is status (1 if flow was found)
          if (st?[i] == 1) {
            // p1 contains new positions
            goodNew.add(p1[i]);
            // _p0 contains old positions
            if (i < _p0!.length) {
              goodOld.add(_p0![i]);
            }
          }
        }

        // 5. Draw tracks
        for (int i = 0; i < goodNew.length; i++) {
          // Draw line on persistent mask
          cv.line(
            _mask!,
            cv.Point(goodNew[i].x.toInt(), goodNew[i].y.toInt()),
            cv.Point(goodOld[i].x.toInt(), goodOld[i].y.toInt()),
            _colors[i % _colors.length],
            thickness: 2,
          );
          // Draw circle on current frame
          cv.circle(
            frameDisplay,
            cv.Point(goodNew[i].x.toInt(), goodNew[i].y.toInt()),
            5,
            _colors[i % _colors.length],
            thickness: -1,
          );
        }

        // Combine frame and mask
        cv.add(frameDisplay, _mask!, dst: frameDisplay);

        // 6. Update state for next iteration
        _oldGray?.dispose();
        _oldGray = frameGray; // transfer ownership of frameGray to _oldGray

        _p0?.dispose();
        _p0 = cv.VecPoint2f.fromList(goodNew);

        // Dispose temporary results
        p1.dispose();
        st?.dispose();
        err?.dispose();
      } else {
        // If tracking lost or initialization failed, just use frameGray as new oldGray
        // or re-initialize.
        _oldGray?.dispose();
        _oldGray = frameGray;

        // Re-detect if points are lost
        if (_p0 == null || _p0!.length < 5) {
          _p0 = cv.goodFeaturesToTrack(
            frameGray,
            _maxCorners,
            _qualityLevel,
            _minDistance.toDouble(),
            blockSize: _blockSize,
          );
        }
      }

      // 7. Display
      _setCurrentFrame(frameDisplay);

      // Dispose original frame
      frame.dispose();
      // Dispose frameDisplay if it's different from frame (it usually is a clone or converted)
      if (frameDisplay != frame) {
        frameDisplay.dispose();
      }
      // Note: frameGray was assigned to _oldGray, so we don't dispose it here.
    } catch (e) {
      debugPrint("Error processing video: $e");
    }

    // Schedule next frame
    // Aim for ~30 FPS (33ms)
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final delay = max(0, 33 - elapsed);

    if (mounted && _isStreaming) {
      Future.delayed(Duration(milliseconds: delay), _processVideo);
    }
  }

  void _setCurrentFrame(cv.Mat img) {
    final (success, bytes) = cv.imencode(".png", img);
    if (success) {
      if (mounted) {
        setState(() {
          _currentFrameBytes = bytes;
        });
      }
    }
  }

  @override
  void dispose() {
    _isStreaming = false;
    _cleanupResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optical Flow LK'),
        actions: [
          Row(
            children: [
              const Icon(Icons.videocam),
              Switch(value: _useCamera, onChanged: _toggleSource, activeThumbColor: Colors.deepPurple),
              const Icon(Icons.camera_alt),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      body: Center(
        child: _currentFrameBytes != null
            ? Image.memory(_currentFrameBytes!, gaplessPlayback: true, fit: BoxFit.contain)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text("Initializing ${_useCamera ? 'Camera' : 'Video'}..."),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Re-initialize tracking
          setState(() {
            _isStreaming = false; // Stop loop temporarily
          });
          // Give time for loop to stop
          Future.delayed(const Duration(milliseconds: 100), () {
            _cleanupResources();
            _initOpenCV();
          });
        },
        tooltip: 'Restart Tracking',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
