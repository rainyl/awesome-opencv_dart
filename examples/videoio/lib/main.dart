import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';

void main() {
  // cv.setLogLevel(cv.LOG_LEVEL_DEBUG);
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
      home: const MyHomePage(title: 'Video IO demo'),
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
  int width = -1;
  int height = -1;
  double fps = -1;
  String backend = "unknown";
  String? src;
  String? dst;
  final vc = cv.VideoCapture.empty();
  final vw = cv.VideoWriter.empty();

  Uint8List? _wroteFrame;

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            ElevatedButton(
                onPressed: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
                  if (result != null) {
                    final file = result.files.single;
                    final path = file.path;
                    if (path != null) {
                      await vc.openAsync(path);
                      setState(() {
                        src = path;
                        dst = p.join(p.dirname(path), "output.avi");
                        width = vc.get(cv.CAP_PROP_FRAME_WIDTH).toInt();
                        height = vc.get(cv.CAP_PROP_FRAME_HEIGHT).toInt();
                        fps = vc.get(cv.CAP_PROP_FPS);
                        backend = vc.getBackendName();
                      });
                    }
                  }
                },
                child: const Text("Select a video")),
            Text("width: $width, height: $height, fps: $fps, backend: $backend"),
            Text("src: $src"),
            Text("dst: $dst"),
            ElevatedButton(
                onPressed: () async {
                  final result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    setState(() {
                      dst = p.join(result, "output.avi");
                    });
                  }
                },
                child: const Text("Save to")),
            ElevatedButton(
                onPressed: () async {
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
                    final rgb = cv.cvtColor(f, cv.COLOR_BGR2RGB);
                    final (s1, bytes) = await cv.imencodeAsync(".png", rgb);

                    f.dispose();
                    rgb.dispose();

                    if (s1) {
                      setState(() {
                        _wroteFrame = bytes;
                      });
                    } else {
                      debugPrint("encode failed");
                    }
                  } else {
                    debugPrint("failed to read frame from $dst");
                  }
                },
                child: const Text("Start")),
            _wroteFrame == null ? Placeholder() : Image.memory(_wroteFrame!),
          ],
        ),
      ),
    );
  }
}
