import 'dart:io';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:flutter/services.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _textureRgbaRendererPlugin = TextureRgbaRenderer();
  int textureId = -1;
  int height = 768;
  int width = 1377;
  int cnt = 0;
  var key = 0;
  int texturePtr = 0;
  final random = Random();
  Uint8List? data;
  Timer? _timer;
  int time = 0;
  int method = 0;
  final strideAlign = Platform.isMacOS ? 64 : 1;

  String? videoPath;
  cv.VideoCapture? cap;
  int currentFrame = 0;
  int frameCount = 0;

  @override
  void initState() {
    super.initState();
    // if (videoPath != null)
    // initCapture();
    _textureRgbaRendererPlugin.createTexture(key).then((textureId) {
      if (textureId != -1) {
        debugPrint("Texture register success, textureId=$textureId");
        _textureRgbaRendererPlugin.getTexturePtr(key).then((value) {
          debugPrint("texture ptr: ${value.toRadixString(16)}");
          setState(() {
            texturePtr = value;
          });
        });
        setState(() {
          this.textureId = textureId;
        });
      } else {
        return;
      }
    });
  }

  void initCapture() {
    if (videoPath == null) {
      debugPrint("videoPath is null");
      return;
    }
    if (!File(videoPath!).existsSync()) {
      debugPrint("video not exists: $videoPath");
      return;
    }
    cap?.release();
    cap = cv.VideoCapture.fromFile(videoPath!);
    if (cap?.isOpened ?? false) {
      frameCount = cap!.get(cv.CAP_PROP_FRAME_COUNT).toInt();
      currentFrame = 0;
      debugPrint("Frame count: $frameCount");
    } else {
      debugPrint("Failed to open video file: $videoPath");
    }
  }

  void start(int methodId) {
    debugPrint("start mockPic");
    method = methodId;
    final rowBytes = (width * 4 + strideAlign - 1) & (~(strideAlign - 1));
    final picDataLength = rowBytes * height;
    debugPrint('REMOVE ME =============================== rowBytes $rowBytes');
    _timer?.cancel();
    // 60 fps
    _timer =
        Timer.periodic(const Duration(milliseconds: 1000 ~/ 60), (timer) async {
      if (methodId == 0) {
        // Method.1: with MethodChannel
        data = mockPicture(width, height, rowBytes, picDataLength);
        final t1 = DateTime.now().microsecondsSinceEpoch;
        final res = await _textureRgbaRendererPlugin.onRgba(
            key, data!, height, width, strideAlign);
        final t2 = DateTime.now().microsecondsSinceEpoch;
        setState(() {
          time = t2 - t1;
        });
        if (!res) {
          debugPrint("WARN: render failed");
        }
      } else if (methodId == 1) {
        final dataPtr = mockPicturePtr(width, height, rowBytes, picDataLength);
        // Method.2: with native ffi
        final t1 = DateTime.now().microsecondsSinceEpoch;
        Native.instance.onRgba(Pointer.fromAddress(texturePtr).cast<Void>(),
            dataPtr, picDataLength, width, height, strideAlign);
        final t2 = DateTime.now().microsecondsSinceEpoch;
        setState(() {
          time = t2 - t1;
        });
        malloc.free(dataPtr);
      } else if (methodId == 2) {
        if (cap?.isOpened ?? false) {
          if (currentFrame >= frameCount) {
            cap!.set(cv.CAP_PROP_POS_FRAMES, 0);
            currentFrame = 0;
          }
          final (success, mat) = cap!.read();
          if (success) {
            final pic = cv.cvtColor(mat, cv.COLOR_RGB2RGBA);

            final sourceRowBytes = mat.width * 4;
            final destRowBytes =
                (sourceRowBytes + strideAlign - 1) & (~(strideAlign - 1));

            Pointer<Uint8> dataPtr;
            int dataLength;

            if (sourceRowBytes == destRowBytes) {
              dataPtr = pic.dataPtr;
              dataLength = pic.total * pic.elemSize;
            } else {
              dataLength = destRowBytes * mat.height;
              dataPtr = malloc.allocate<Uint8>(dataLength);

              final srcPtr = pic.dataPtr;
              final destList = dataPtr.asTypedList(dataLength);
              final srcList = srcPtr.asTypedList(sourceRowBytes * mat.height);

              for (int i = 0; i < mat.height; i++) {
                final srcOffset = i * sourceRowBytes;
                final destOffset = i * destRowBytes;
                final srcRowView = Uint8List.sublistView(
                    srcList, srcOffset, srcOffset + sourceRowBytes);
                destList.setRange(
                    destOffset, destOffset + sourceRowBytes, srcRowView);
              }
            }

            final t1 = DateTime.now().microsecondsSinceEpoch;
            final texture = Pointer.fromAddress(texturePtr).cast<Void>();
            Native.instance.onRgba(texture, dataPtr, dataLength, mat.width,
                mat.height, strideAlign);
            final t2 = DateTime.now().microsecondsSinceEpoch;

            if (sourceRowBytes != destRowBytes) {
              malloc.free(dataPtr);
            }

            setState(() {
              time = t2 - t1;
            });
            pic.dispose();
            mat.dispose();
            currentFrame += 1;
          } else {
            debugPrint("Read failed");
          }
        } else {
          debugPrint("Video not loaded. Please pick a video file first.");
        }
      } else {
        throw UnimplementedError("");
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (key != -1) {
      _textureRgbaRendererPlugin.closeTexture(key);
    }
    if (cap?.isOpened ?? false) {
      cap!.release();
    }
    super.dispose();
  }

  Uint8List mockPicture(int width, int height, int rowBytes, int length) {
    final pic = List.generate(length, (index) {
      final r = index / rowBytes;
      final c = (index % rowBytes) / 4;
      final p = index & 0x03;
      if (c > 20 && c < 30) {
        if (r > 20 && r < 25) {
          if (p == 0 || p == 3) {
            return 255;
          } else {
            return 0;
          }
        }
        if (r > 40 && r < 45) {
          if (p == 1 || p == 3) {
            return 255;
          } else {
            return 0;
          }
        }
        if (r > 60 && r < 65) {
          if (p == 2 || p == 3) {
            return 255;
          } else {
            return 0;
          }
        }
      }
      return 255;
    });
    return Uint8List.fromList(pic);
  }

  Pointer<Uint8> mockPicturePtr(
      int width, int height, int rowBytes, int length) {
    final pic = List.generate(length, (index) {
      final r = index / rowBytes;
      final c = (index % rowBytes) / 4;
      final p = index & 0x03;
      final edgeH = (c >= 0 && c < 10) || ((c >= width - 10) && c < width);
      final edgeW = (r >= 0 && r < 10) || ((r >= height - 10) && r < height);
      if (edgeH || edgeW) {
        if (p == 0 || p == 3) {
          return 255;
        } else {
          return 0;
        }
      }
      return 255;
    });
    final picAddr = malloc.allocate(pic.length).cast<Uint8>();
    final list = picAddr.asTypedList(pic.length);
    list.setRange(0, pic.length, pic);
    return picAddr;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: textureId == -1
                  ? const Offstage()
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: Colors.blue),
                          // decoration: const BoxDecoration(color: Colors.black),
                          // width: width.toDouble(),
                          // height: height.toDouble(),
                          child: Texture(textureId: textureId)),
                    ),
            ),
            Text(
                "texture id: $textureId, texture memory address: ${texturePtr.toRadixString(16)}"),
            TextButton.icon(
              label: const Text("play with texture (method channel API)"),
              icon: const Icon(Icons.play_arrow),
              onPressed: () => start(0),
            ),
            TextButton.icon(
              label: const Text("play with texture (native API, faster)"),
              icon: const Icon(Icons.play_arrow),
              onPressed: () => start(1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform
                        .pickFiles(type: FileType.video);
                    if (result != null) {
                      final file = result.files.single;
                      final path = file.path;
                      if (path != null) {
                        setState(() {
                          videoPath = path;
                        });
                        initCapture();
                      }
                    }
                  },
                  label: const Text("Pick a video file"),
                  icon: const Icon(Icons.video_file),
                ),
                videoPath != null
                    ? Expanded(
                        child: Text(
                        "File: $videoPath",
                        softWrap: true,
                      ))
                    : const Offstage(),
              ],
            ),
            TextButton.icon(
              label: const Text("play with texture (native API, opencv_dart)"),
              icon: const Icon(Icons.play_arrow),
              onPressed: () => start(2),
            ),
            Text(
                "Current mode: ${method == 0 ? 'Method Channel API' : 'Native API'}"),
            time != 0 ? Text("FPS: ${1000000 ~/ time} fps") : const Offstage()
          ],
        ),
      ),
    );
  }
}
