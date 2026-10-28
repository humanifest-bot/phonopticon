import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/simulated_backend.dart';
import 'package:phonopticon/main.dart';
import 'package:phonopticon/domain/experiment.dart';

void main() {
  testWidgets('idle, explicit start, results, mode change and stop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PhonopticonApp(backend: SimulatedBackend(realtime: false)),
    );
    expect(find.text('SIMULATED · feasibility runner'), findsOneWidget);
    expect(find.textContaining('IDLE'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('COMPLETE'), findsOneWidget);
    expect(find.text('Movement above fixture threshold'), findsOneWidget);
    expect(
      find.textContaining('single tone provides no absolute range'),
      findsOneWidget,
    );
    await tester.tap(find.text('Chirp ranging'));
    await tester.pumpAndSettle();
    expect(find.textContaining('IDLE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(find.text('Equivalent range over time'), findsOneWidget);
    expect(find.textContaining('equivalent range'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground stop produces cancellation without a result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PhonopticonApp());
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('stop')));
    await tester.pumpAndSettle();
    expect(find.textContaining('CANCELLED'), findsOneWidget);
    expect(find.text('Movement above fixture threshold'), findsNothing);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.textContaining('CANCELLED'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('CANCELLED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width remains usable without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PhonopticonApp());
    expect(tester.takeException(), isNull);
    expect(find.text('Configure a trial'), findsOneWidget);
  });
  testWidgets('native unavailable and invalid input are explicit UI states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PhonopticonApp(backend: SimulatedBackend(realtime: false)),
    );
    await tester.tap(find.byType(DropdownButtonFormField<Scenario>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invalid PCM · failure check').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('FAILED'), findsOneWidget);
    expect(find.text('Unknown · analysis unavailable'), findsOneWidget);
    expect(find.text('Nonfinite PCM'), findsWidgets);
    await tester.pumpWidget(const PhonopticonApp(key: ValueKey('native-test')));
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Native audio · unavailable').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNull,
    );
    expect(find.textContaining('No silent fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
