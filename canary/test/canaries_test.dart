@Tags(['golden'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _canary = GlobalKey();

Widget frame(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(key: _canary, child: SizedBox(width: 300, height: 200, child: child)),
        ),
      ),
    );

Future<void> expectGolden(WidgetTester tester, Widget child, String name) async {
  await tester.pumpWidget(frame(child));
  await expectLater(find.byKey(_canary), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  testWidgets('text in Inter and in FlutterTest', (tester) async {
    await expectGolden(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Quick fox 123', style: TextStyle(fontFamily: 'Inter', fontSize: 20)),
          Text('Quick fox 123', style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600)),
          // FlutterTest draws every glyph as a 1em square, so keep it short.
          Text('Fox 123', style: TextStyle(fontSize: 20)),
          Text('Glyphs', style: TextStyle(fontFamily: 'Inter', fontSize: 56)),
        ],
      ),
      'text',
    );
  });

  testWidgets('gradients', (tester) async {
    await expectGolden(
      tester,
      const Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: SweepGradient(colors: [Colors.red, Colors.green, Colors.blue, Colors.red]),
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [Colors.yellow, Colors.purple]),
              ),
            ),
          ),
        ],
      ),
      'gradients',
    );
  });

  testWidgets('blur and rounded clip', (tester) async {
    await expectGolden(
      tester,
      ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const ColoredBox(color: Colors.orange, child: Center(child: FlutterLogo(size: 120))),
        ),
      ),
      'blur',
    );
  });

  testWidgets('strokes and blend', (tester) async {
    await expectGolden(tester, CustomPaint(painter: _StrokePainter()), 'strokes');
  });

  testWidgets('scaled image', (tester) async {
    final image = await tester.runAsync(_checkerboard);
    await expectGolden(
      tester,
      RawImage(image: image, width: 300, height: 200, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
      'image',
    );
  });
}

/// A 7x5 checkerboard, so scaling to 300x200 is non-integral on both axes.
Future<ui.Image> _checkerboard() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var x = 0; x < 7; x++) {
    for (var y = 0; y < 5; y++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        Paint()..color = (x + y).isEven ? Colors.teal : Colors.amber,
      );
    }
  }
  return recorder.endRecording().toImage(7, 5);
}

class _StrokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.indigo;
    for (var i = 0; i < 8; i++) {
      canvas.drawLine(Offset(10, 10 + i * 24.0), Offset(size.width - 10, 30 + i * 21.7), stroke);
    }
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.multiply);
    canvas.drawCircle(const Offset(150, 100), 70, Paint()..color = Colors.pink.withValues(alpha: 0.7));
    canvas.drawCircle(const Offset(190, 100), 70, Paint()..color = Colors.cyan.withValues(alpha: 0.7));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
