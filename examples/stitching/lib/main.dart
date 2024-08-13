import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Image stitching demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Uint8List? _stitchedImage;
  final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.PANORAMA);

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            ElevatedButton(
              onPressed: () async {
                final bytes1 =
                    (await DefaultAssetBundle.of(context).load("assets/barcode1.png")).buffer.asUint8List();
                final bytes2 =
                    (await DefaultAssetBundle.of(context).load("assets/barcode2.png")).buffer.asUint8List();
                final images = [
                  cv.imdecode(bytes1, cv.IMREAD_COLOR),
                  cv.imdecode(bytes2, cv.IMREAD_COLOR),
                ].cvd;
                final (status, dst) = await stitcher.stitchAsync(images);
                if (status != cv.StitcherStatus.OK) {
                  throw Exception("Stitcher failed with status $status");
                }
                final (success, bytes) = await cv.imencodeAsync(".png", dst);
                if (!success) {
                  throw Exception("Failed to encode image");
                }
                setState(() {
                  _stitchedImage = bytes;
                });
              },
              child: const Text("run"),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Card(
                  child: Image.asset(
                    "assets/barcode1.png",
                    width: 180,
                  ),
                ),
                Card(
                  child: Image.asset(
                    "assets/barcode2.png",
                    width: 180,
                  ),
                ),
              ],
            ),
            Card(
              child: _stitchedImage == null ? Placeholder() : Image.memory(_stitchedImage!),
            ),
          ],
        ),
      ),
    );
  }
}
