import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv.dart' as cv;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IO',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'IO'),
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
  List<String> assetImageNames = ["assets/lenna.png", "assets/sample.webp"];
  List<Uint8List?> assetImages = [];
  List<Uint8List?> fileImages = [];
  cv.Net? model;
  List<String> layerNames = [];
  int drawerIndex = 0;
  final imageCount = 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text('Image/Model Reading Example'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_special_outlined),
              title: const Text('Assets'),
              selected: drawerIndex == 0,
              onTap: () {
                // Update the state of the app
                setState(() {
                  drawerIndex = 0;
                });
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Files'),
              selected: drawerIndex == 1,
              onTap: () {
                // Update the state of the app
                setState(() {
                  drawerIndex = 1;
                });
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_applications_outlined),
              title: const Text('Models'),
              selected: drawerIndex == 2,
              onTap: () {
                // Update the state of the app
                setState(() {
                  drawerIndex = 2;
                });
                // Then close the drawer
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: switch (drawerIndex) {
        0 => _buildAssetPage(),
        1 => _buildFilePage(),
        2 => _buildModelPage(),
        _ => const Placeholder(),
      },
    );
  }

  Future<Uint8List> applyRandomProcess(Uint8List bytes) async {
    final img = await cv.imdecodeAsync(bytes, cv.IMREAD_COLOR);
    final cv.Mat dst = await img.cloneAsync();
    final rand = Random().nextInt(5);
    switch (rand) {
      case 0:
        await cv.cvtColorAsync(img, cv.COLOR_BGR2GRAY, dst: dst);
        break;
      case 1:
        await cv.thresholdAsync(img, 128, 255.0, cv.THRESH_BINARY, dst: dst);
        break;
      case 2:
        await cv.circleAsync(dst, cv.Point(1, 1), img.rows ~/ 2, cv.Scalar.red, thickness: 3);
        break;
      case 3:
        await cv.putTextAsync(dst, "Hello", cv.Point(1, 1), cv.FONT_HERSHEY_SIMPLEX, 1, cv.Scalar.red);
        break;
      case 4:
        await cv.blurAsync(img, (15, 15), dst: dst);
        break;
      default:
    }
    final res = await cv.imencodeAsync(".png", dst);
    img.dispose();
    return res.$2;
  }

  Widget _buildAssetPage() {
    return Column(
      children: [
        ElevatedButton(
          child: const Text('Load Image from Assets'),
          onPressed: () async {
            final imgs = <Uint8List>[];
            for (var i = 0; i < imageCount; i++) {
              final data = await rootBundle.load(assetImageNames[i % assetImageNames.length]);
              final bytes = data.buffer.asUint8List();
              final res = await applyRandomProcess(bytes);
              imgs.add(res);
            }
            setState(() {
              assetImages = imgs;
            });
          },
        ),
        Expanded(
          child: assetImages.isEmpty
              ? const Placeholder()
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: imageCount,
                  itemBuilder: (ctx, idx) {
                    final i = Random().nextInt(assetImages.length);
                    return assetImages[i] == null
                        ? const Placeholder()
                        : Card(
                            child: Image.memory(
                              assetImages[i]!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                            ),
                          );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilePage() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            final files = await ImagePicker().pickMultiImage();
            final imgs = <Uint8List>[];
            for (var i = 0; i < imageCount; i++) {
              final idx = Random().nextInt(files.length);
              final bytes = await files[idx].readAsBytes();
              final res = await applyRandomProcess(bytes);
              imgs.add(res);
            }
            setState(() {
              fileImages = imgs;
            });
          },
          child: const Text('Pick Image from File'),
        ),
        Expanded(
          child: fileImages.isEmpty
              ? const Placeholder()
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: imageCount,
                  itemBuilder: (ctx, idx) {
                    final i = idx % fileImages.length;
                    return fileImages[i] == null
                        ? const Placeholder()
                        : Image.memory(
                            fileImages[i]!,
                            width: 200,
                            height: 200,
                            fit: BoxFit.contain,
                          );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildModelPage() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            if (model != null) model!.dispose();
            final data = await DefaultAssetBundle.of(context).load("assets/mnist-8.onnx");
            final bytes = data.buffer.asUint8List();
            model = cv.Net.fromOnnxBytes(bytes);
            final names = await model!.getLayerNamesAsync();
            setState(() {
              layerNames = names;
            });
          },
          child: const Text("Load onnx model"),
        ),
        Expanded(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: layerNames.length,
            itemBuilder: (ctx, i) => ListTile(
              leading: const Icon(Icons.model_training),
              title: Text(layerNames[i]),
              onTap: () {},
            ),
          ),
        ),
      ],
    );
  }
}
