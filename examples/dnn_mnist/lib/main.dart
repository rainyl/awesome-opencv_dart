// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int? predictedNumber;
  cv.Net? _model;
  Uint8List? currentImage;
  String currentImagePath = "";
  final assetImgs = [
    "assets/mnist_0.png",
    "assets/mnist_1.png",
    "assets/mnist_2.png",
    "assets/mnist_4.png",
    "assets/mnist_5.png",
    "assets/mnist_8.png",
    "assets/mnist_9.png",
    "assets/mnist_9_1.png",
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> loadModel() async {
    if (_model == null) {
      final data = await DefaultAssetBundle.of(context).load("assets/mnist-8.onnx");
      final bytes = data.buffer.asUint8List();
      _model = await cv.NetAsync.fromOnnxBytesAsync(bytes);
    }
  }

  Future<int> predict(cv.Mat img) async {
    await loadModel();
    assert(!img.isEmpty);
    final blob = await cv.blobFromImageAsync(
      img,
      scalefactor: 1.0,
      size: (28, 28),
      mean: cv.Scalar.all(0),
      crop: false,
    );
    assert(!blob.isEmpty);
    await _model!.setInputAsync(blob);
    final logits = await _model!.forwardAsync();
    debugPrint("logits: ${logits.toFmtString()}");
    final (_, maxVal, _, maxLoc) = await cv.minMaxLocAsync(logits);
    debugPrint("maxVal: $maxVal, maxLoc: $maxLoc");
    return maxLoc.x;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('DNN MNIST Demo'),
        ),
        body: Container(
          alignment: Alignment.center,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final img = await picker.pickImage(source: ImageSource.gallery);
                      if (img != null) {
                        final bytes = await img.readAsBytes();
                        setState(() {
                          currentImagePath = img.path;
                          currentImage = bytes;
                        });
                      }
                    },
                    child: const Text("Pick Image"),
                  ),
                  ElevatedButton(
                      onPressed: () async {
                        final idx = Random().nextInt(assetImgs.length);
                        final data = await DefaultAssetBundle.of(context).load(assetImgs[idx]);
                        setState(() {
                          currentImagePath = assetImgs[idx];
                          currentImage = data.buffer.asUint8List();
                        });
                      },
                      child: const Text("Random")),
                ],
              ),
              ElevatedButton(
                onPressed: () async {
                  if (currentImage != null) {
                    final mat = await cv.imdecodeAsync(currentImage!, cv.IMREAD_GRAYSCALE);
                    final result = await predict(mat);
                    setState(() {
                      predictedNumber = result;
                    });
                  }
                },
                child: const Text("Predict"),
              ),
              Text(
                "Image: $currentImagePath",
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox.fromSize(
                size: const Size(200, 200),
                child: currentImage == null
                    ? const Placeholder()
                    : Image.memory(
                        currentImage!,
                        fit: BoxFit.fill,
                      ),
              ),
              Text(
                "Predicted:",
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                "$predictedNumber",
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
