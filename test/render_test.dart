import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/simulated_backend.dart';
import 'package:phonopticon/main.dart';

void main() {
  for (final width in [1400.0, 390.0]) {
    testWidgets('render completed chirp at width $width', (tester) async {
      tester.view.physicalSize = Size(width, width > 1000 ? 1100 : 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final sdk = Platform.environment['FLUTTER_ROOT'];
        if (sdk == null)
          throw StateError(
            'FLUTTER_ROOT required for cached-font render verification.',
          );
        final fonts = '$sdk/bin/cache/artifacts/material_fonts';
        final regular = FontLoader('Roboto')
          ..addFont(
            File(
              '$fonts/Roboto-Regular.ttf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          )
          ..addFont(
            File(
              '$fonts/Roboto-Bold.ttf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              '$fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await regular.load();
        await icons.load();
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PhonopticonApp(backend: SimulatedBackend(realtime: false)),
        ),
      );
      await tester.tap(find.text('Chirp ranging'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      expect(find.text('Equivalent range over time'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Phonopticon'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory.systemTemp.createTempSync('phonopticon-render-');
        final path = '${dir.path}/chirp-${width.round()}.png';
        File(path).writeAsBytesSync(png!.buffer.asUint8List());
        stdout.writeln('WIDGET_RENDER=$path');
        image.dispose();
      });
    });
  }
}
