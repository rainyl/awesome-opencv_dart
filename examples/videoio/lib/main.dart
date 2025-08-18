import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:extended_text/extended_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dartcv4/dartcv.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';

void main() {
  // cv.setLogLevel(cv.LOG_LEVEL_DEBUG);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Video IO demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int width = -1;
  int height = -1;
  double fps = -1;
  String backend = "unknown";
  String? src;
  String? dst;
  final vc = cv.VideoCapture.empty();
  final vw = cv.VideoWriter.empty();

  ui.Image? _currentFrame;
  bool _isPlaying = false;
  Timer? _frameTimer;

  @override
  void dispose() {
    _frameTimer?.cancel();
    vc.release();
    vw.release();
    super.dispose();
  }

  Future<void> _playVideo() async {
    if (src == null || !vc.isOpened) {
      debugPrint('No video selected or video not opened');
      return;
    }

    setState(() {
      _isPlaying = true;
    });

    // Reset to beginning
    vc.set(cv.CAP_PROP_POS_FRAMES, 0);

    // 使用Timer进行精确的帧率控制
    final frameDuration = Duration(milliseconds: (1000 / fps).round());

    _frameTimer = Timer.periodic(frameDuration, (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      final (success, frame) = await vc.readAsync();

      if (!success || frame.width == 0 || frame.height == 0) {
        debugPrint('End of video reached');
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
        timer.cancel();
        return;
      }

      final image = await _cvMatToImage(frame, dstSize: (1920, 1080));

      if (mounted && _isPlaying) {
        setState(() {
          _currentFrame = image;
        });
      } else {
        debugPrint('Failed to encode frame');
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);

                    if (result != null) {
                      final file = result.files.single;
                      final path = file.path;
                      if (path != null) {
                        debugPrint("selected file: $path");
                        final ret = await vc.openAsync(path);
                        setState(() {
                          src = path;
                          if (ret) {
                            width = vc.get(cv.CAP_PROP_FRAME_WIDTH).toInt();
                            height = vc.get(cv.CAP_PROP_FRAME_HEIGHT).toInt();
                            fps = vc.get(cv.CAP_PROP_FPS);
                            backend = vc.getBackendName();
                          }
                        });
                      }

                      final dstDir = await getApplicationCacheDirectory();
                      debugPrint("dstDir: $dstDir");
                      setState(() {
                        dst = p.join(dstDir.path, "output.mp4");
                      });
                    }
                  },
                  child: const Text("Select a video"),
                )
              ],
            ),
            Text(
              "width: $width, height: $height, fps: $fps, backend: $backend",
            ),
            ExtendedText(
              "src: $src",
              maxLines: 1,
              overflowWidget: const TextOverflowWidget(
                position: TextOverflowPosition.middle,
                child: Text("..."),
              ),
            ),
            ExtendedText(
              "dst: $dst",
              maxLines: 1,
              overflowWidget: const TextOverflowWidget(
                position: TextOverflowPosition.middle,
                child: Text("..."),
              ),
            ),
            ElevatedButton(
              child: const Text("Save & Read Back"),
              onPressed: () async {
                debugPrint("dst: $dst");
                // we will write the first frame to the `dst` file and read it back
                vw.open(dst!, "MJPG", fps, (width, height));
                assert(vw.isOpened);
                final (success, frame) = await vc.readAsync();
                if (success) {
                  await vw.writeAsync(frame);
                } else {
                  debugPrint("failed to read frame");
                }
                vw.release();

                // read it back
                final vc1 = cv.VideoCapture.fromFile(dst!);
                final (s, f) = await vc1.readAsync();
                vc1.dispose();

                if (s) {
                  final image = await _cvMatToImage(f, dstSize: (1920, 1080));

                  setState(() {
                    _currentFrame = image;
                  });
                } else {
                  debugPrint("failed to read frame from $dst");
                }
              },
            ),
            _previewContainer(
                child: _currentFrame == null
                    ? Text("Waiting...")
                    : RawImage(
                        image: _currentFrame,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                      )),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isPlaying ? null : _playVideo,
                  child: Text(_isPlaying ? 'Playing...' : 'Play'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isPlaying
                      ? () {
                          setState(() {
                            _isPlaying = false;
                          });
                          _frameTimer?.cancel();
                        }
                      : null,
                  child: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewContainer({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(5),
      margin: EdgeInsets.all(5),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(color: Colors.black, child: child),
        ),
      ),
    );
  }

  Future<ui.Image> _rgbaBytesToImage(
    Uint8List data,
    int w,
    int h,
  ) async {
    // Always feed RGBA to avoid bgra8888 issues on Chrome.
    final immutable = await ui.ImmutableBuffer.fromUint8List(data);
    ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
      immutable,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<ui.Image> _cvMatToImage(cv.Mat mat, {(int, int)? dstSize}) async {
    final resized = dstSize == null ? mat : await cv.resizeAsync(mat, dstSize);
    final rgba = await cv.cvtColorAsync(resized, cv.COLOR_BGR2RGBA);
    resized.dispose();
    final image = await _rgbaBytesToImage(rgba.data, rgba.width, rgba.height);
    rgba.dispose();
    return image;
  }
}
