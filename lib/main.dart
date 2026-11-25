import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'audio/audio_backend.dart';
import 'audio/computer_backend.dart';
import 'audio/simulated_backend.dart';
import 'calibration/tone_calibration.dart';
import 'calibration/import_profile.dart';
import 'calibration/read_bundle.dart';
import 'calibration/breathing_comparison.dart';
import 'domain/experiment.dart';
import 'export/artifacts.dart';
import 'export/export_bundle.dart';
import 'runner/trial_runner.dart';
import 'session/session_store.dart';
import 'signal/analysis.dart' show analyze, silentMicrophoneInput;
import 'ui/plots.dart';
import 'ui/trial_guide.dart';

// Keep controls inspectable by assistive tools without an invisible opt-in.
// The handle intentionally lives for the lifetime of the application.
SemanticsHandle? _applicationSemantics;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _applicationSemantics ??= SemanticsBinding.instance.ensureSemantics();
  runApp(const PhonopticonApp());
}

class PhonopticonApp extends StatelessWidget {
  const PhonopticonApp({
    super.key,
    this.backend,
    this.initialCalibration,
    this.sessionStore,
  });
  final AudioBackend? backend;
  final ToneCalibration? initialCalibration;
  final SessionStore? sessionStore;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Phonopticon',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff006d77)),
      scaffoldBackgroundColor: const Color(0xfff3f5f8),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    ),
    home: ExperimentScreen(
      backend: backend,
      initialCalibration: initialCalibration,
      sessionStore: sessionStore,
    ),
  );
}

class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({
    super.key,
    this.backend,
    this.initialCalibration,
    this.sessionStore,
  });
  final AudioBackend? backend;
  final ToneCalibration? initialCalibration;
  final SessionStore? sessionStore;
  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen>
    with WidgetsBindingObserver {
  static const _guidedTrialsJson = '''
  [
    {"id":"mic-check","mode":"tone","scenario":"transmitterOff","durationSeconds":4,"amplitude":0.02,"nearUltrasonic":false,"instruction":"Speak during the recording, then export it."},
    {"id":"stationary","mode":"breathing","scenario":"stationary","durationSeconds":30,"amplitude":0.02,"breathingGateMeters":0.6,"nearUltrasonic":false,"instruction":"Keep the Mac and reflector still."},
    {"id":"motion","mode":"breathing","scenario":"moving","durationSeconds":30,"amplitude":0.02,"breathingGateMeters":0.6,"nearUltrasonic":false,"instruction":"Move the reflector 5–10 mm, two seconds each way."},
    {"id":"transmitter-off","mode":"breathing","scenario":"transmitterOff","durationSeconds":30,"amplitude":0.02,"breathingGateMeters":0.6,"nearUltrasonic":false,"instruction":"Repeat the small motion with the chirp off."}
  ]
  ''';
  late final List<Map<String, dynamic>> guidedTrials =
      (jsonDecode(_guidedTrialsJson) as List)
          .map((step) => Map<String, dynamic>.from(step as Map))
          .toList();
  int? guidedIndex;
  bool guidedExportRequested = false;
  late final SessionStore sessionStore;
  Map<String, dynamic>? guidedSession;
  Map<String, dynamic>? resumableSession;
  bool sessionSaving = false;
  bool sessionLoaded = false, sessionSaveFailed = false, notesDirty = false;
  String? sessionStatus;
  final notesControllers = <String, TextEditingController>{
    'systemVolume': TextEditingController(),
    'distance': TextEditingController(),
    'reflector': TextEditingController(),
    'deviceStability': TextEditingController(),
    'unexpectedSounds': TextEditingController(),
  };
  Map<String, Object?>? comparison;
  String? comparisonStatus;
  bool meterActive = false;
  double meterLevel = 0;
  String? meterStatus;
  late TrialRunner runner;
  ProbeMode mode = ProbeMode.tone;
  Scenario scenario = Scenario.moving;
  bool native = false, nearUltrasonic = false, exporting = false;
  double duration = 4, amplitude = 0.02, range = 0.6;
  int selectedFrame = 0;
  String? exportStatus;
  ToneCalibration? calibration;
  String? calibrationStatus;
  List<Scenario>? validationPlan;
  final validationTrials = <Map<String, Object?>>[];
  bool slotRecorded = false;
  bool get breathing => mode == ProbeMode.breathing;
  double get runDuration =>
      breathing ? ExperimentConfig.breathingSeconds : duration;
  bool get settingsLocked =>
      runner.busy ||
      validationPlan != null ||
      guidedIndex != null ||
      sessionSaving ||
      meterActive;

  Future<void> loadSavedSession() async {
    try {
      final value = await sessionStore.loadLatest();
      if (!mounted || value == null) return;
      final decoded = jsonDecode(value);
      if (decoded is! Map ||
          decoded['schemaVersion'] != 1 ||
          decoded['id'] is! String ||
          decoded['attempts'] is! List ||
          decoded['index'] is! int ||
          (decoded['index'] as int) < 0 ||
          (decoded['index'] as int) >= guidedTrials.length) {
        throw const FormatException('Unsupported or invalid saved session');
      }
      setState(() {
        resumableSession = Map<String, dynamic>.from(decoded);
        sessionStatus = 'A local session is available to resume.';
      });
    } catch (error) {
      if (mounted)
        setState(() => sessionStatus = 'Session restore unavailable: $error');
    } finally {
      if (mounted) setState(() => sessionLoaded = true);
    }
  }

  Future<bool> saveGuidedSession() async {
    final session = guidedSession;
    if (session == null || sessionSaving) return false;
    setState(() {
      sessionSaving = true;
      sessionStatus = 'Saving session locally…';
      session['notes'] = {
        for (final entry in notesControllers.entries)
          entry.key: entry.value.text,
      };
    });
    try {
      await sessionStore.save(session['id'] as String, jsonEncode(session));
      if (mounted)
        setState(() {
          sessionStatus = 'Session saved locally.';
          resumableSession = session;
          sessionSaveFailed = false;
          notesDirty = false;
        });
      return true;
    } catch (error) {
      if (mounted)
        setState(() {
          sessionSaveFailed = true;
          sessionStatus =
              'Session save failed: $error. Retry saving before continuing.';
        });
      return false;
    } finally {
      if (mounted) setState(() => sessionSaving = false);
    }
  }

  Future<void> beginGuidedSession() async {
    for (final controller in notesControllers.values) {
      controller.clear();
    }
    guidedSession = {
      'schemaVersion': 1,
      'id': 'session-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      'createdUtc': DateTime.now().toUtc().toIso8601String(),
      'index': 0,
      'complete': false,
      'attempts': <Map<String, dynamic>>[],
    };
    setState(() {
      comparison = null;
      comparisonStatus = null;
      notesDirty = false;
      sessionSaveFailed = false;
    });
    applyGuidedStep(0);
    await saveGuidedSession();
  }

  void resumeGuidedSession() {
    final saved = resumableSession;
    if (saved == null) return;
    guidedSession = saved;
    final notes = saved['notes'];
    for (final entry in notesControllers.entries) {
      entry.value.text = notes is Map
          ? (notes[entry.key] as String? ?? '')
          : '';
    }
    comparison = null;
    comparisonStatus = null;
    applyGuidedStep(saved['index'] as int);
    final attempts = (saved['attempts'] as List)
        .whereType<Map>()
        .where((a) => a['step'] == guidedIndex)
        .toList();
    if (attempts.isNotEmpty) {
      final last = attempts.last;
      try {
        final bundle = last['bundle'];
        if (bundle is Map) {
          runner.capture = readPhysicalBundle(
            Map<String, dynamic>.from(bundle),
            mode: mode,
          );
          if (!runner.capture!.cancelled)
            runner.result = analyze(runner.capture!);
        }
        runner.state = TrialState.values.byName(last['state'] as String);
        runner.error = last['error'] as String?;
        guidedExportRequested = last['exported'] == true;
      } catch (error) {
        sessionStatus = 'Saved attempt could not be restored: $error';
      }
    }
    setState(() {
      resumableSession = null;
      notesDirty = false;
    });
    if (saved['complete'] == true) compareGuided();
  }

  void compareGuided() {
    final session = guidedSession;
    if (session == null) return;
    try {
      final attempts = (session['attempts'] as List).whereType<Map>().toList();
      final captures = <AudioCapture>[];
      final ids = <String?>[];
      final revisions = <String?>[];
      for (var step = 1; step <= 3; step++) {
        final matched = attempts
            .where(
              (a) =>
                  a['step'] == step &&
                  a['bundle'] is Map &&
                  a['state'] != 'cancelled',
            )
            .toList();
        if (matched.isEmpty)
          throw StateError(
            'Complete a stationary, motion and transmitter-off trial first.',
          );
        final bundle = Map<String, dynamic>.from(matched.last['bundle'] as Map);
        captures.add(readPhysicalBundle(bundle, mode: ProbeMode.breathing));
        ids.add((bundle['manifest'] as Map)['trialId'] as String?);
        revisions.add((bundle['manifest'] as Map)['sourceRevision'] as String?);
      }
      final result = compareBreathingCaptures(
        captures,
        trialIds: ids,
        sourceRevisions: revisions,
      );
      setState(() {
        comparison = result;
        comparisonStatus = null;
        session['comparison'] = result;
      });
    } catch (error) {
      setState(() {
        comparison = null;
        comparisonStatus = 'Comparison unavailable: $error';
        session.remove('comparison');
      });
    }
  }

  Future<void> exportGuidedSession() async {
    if (guidedSession == null) return;
    if (notesDirty && !await saveGuidedSession()) return;
    if (!mounted) return;
    setState(() {
      exporting = true;
      exportStatus = null;
    });
    try {
      final id = guidedSession!['id'] as String;
      final message = await saveBundle(
        jsonEncode(guidedSession),
        'phonopticon-$id',
      );
      if (mounted) setState(() => exportStatus = message);
    } catch (error) {
      if (mounted)
        setState(() => exportStatus = 'Session export failed: $error');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> startMeter() async {
    final backend = runner.backend;
    if (backend is! MicrophoneMeterBackend || meterActive || runner.busy)
      return;
    setState(() {
      meterActive = true;
      meterLevel = 0;
      meterStatus = 'Starting microphone…';
    });
    try {
      await (backend as MicrophoneMeterBackend).startMeter(
        onLevel: (level) {
          if (mounted && meterActive)
            setState(() {
              meterLevel = level.clamp(0, 1);
              meterStatus =
                  'Microphone level · no sound emitted or samples saved';
            });
        },
      );
      if (mounted) setState(() => meterStatus = 'Microphone check stopped.');
    } catch (error) {
      if (mounted)
        setState(() => meterStatus = 'Microphone check failed: $error');
    } finally {
      if (mounted)
        setState(() {
          meterActive = false;
        });
    }
  }

  void stopMeter() {
    final backend = runner.backend;
    if (backend is MicrophoneMeterBackend && meterActive) {
      (backend as MicrophoneMeterBackend).stopMeter();
    }
  }

  void applyGuidedStep(int index) {
    final step = guidedTrials[index];
    setState(() {
      guidedIndex = index;
      guidedExportRequested = false;
      mode = ProbeMode.values.byName(step['mode'] as String);
      scenario = Scenario.values.byName(step['scenario'] as String);
      duration = (step['durationSeconds'] as num).toDouble();
      amplitude = (step['amplitude'] as num).toDouble();
      range = (step['breathingGateMeters'] as num?)?.toDouble() ?? .6;
      nearUltrasonic = step['nearUltrasonic'] as bool;
      clearResults();
      guidedSession?['index'] = index;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    native = widget.backend?.capabilities.sourceKind == 'PHYSICAL';
    sessionStore = widget.sessionStore ?? createSessionStore();
    calibration = widget.initialCalibration;
    _makeRunner();
    loadSavedSession();
  }

  void _makeRunner() {
    runner = TrialRunner(
      widget.backend ?? (native ? createComputerBackend() : SimulatedBackend()),
    );
    runner.onChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    runner.dispose();
    stopMeter();
    for (final controller in notesControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (runner.busy) runner.stop();
      stopMeter();
    }
  }

  void clearResults() {
    runner.result = null;
    runner.capture = null;
    runner.error = null;
    runner.state = TrialState.idle;
    exportStatus = null;
    selectedFrame = 0;
  }

  Future<void> start() async {
    setState(() {
      selectedFrame = 0;
      exportStatus = null;
    });
    await runner.start(
      ExperimentConfig(
        mode: mode,
        scenario: scenario,
        durationSeconds: runDuration,
        amplitude: amplitude,
        rangeMeters: breathing ? .6 : range,
        breathingGateMeters: range,
        motionMeters: breathing ? .004 : .12,
        motionHz: breathing ? ExperimentConfig.calibrationRhythmHz : .7,
        toneHz: nearUltrasonic ? 19000 : 10000,
        startHz: nearUltrasonic ? 18000 : 3000,
        endHz: nearUltrasonic ? 20000 : 10000,
      ),
    );
    if (!mounted) return;
    setState(() {
      final capture = runner.capture;
      if (native &&
          mode == ProbeMode.tone &&
          calibration != null &&
          guidedIndex == null &&
          capture != null &&
          runner.result != null) {
        runner.result = calibration!.apply(capture, runner.result!);
      }
      if (validationPlan != null) {
        validationTrials.add({
          'index': validationTrials.length + 1,
          'expectedCondition': scenario.name,
          'state': runner.state.name,
          'error': runner.error,
          'bundle': capture == null
              ? null
              : artifactBundle(capture, runner.result),
        });
        slotRecorded = true;
      }
      if (guidedIndex != null && guidedSession != null) {
        guidedSession!['complete'] = false;
        final id =
            'phonopticon-${DateTime.now().toUtc().microsecondsSinceEpoch}';
        (guidedSession!['attempts'] as List).add({
          'step': guidedIndex,
          'id': guidedTrials[guidedIndex!]['id'],
          'state': runner.state.name,
          'error': runner.error,
          'exported': false,
          'bundle': capture == null
              ? null
              : artifactBundle(capture, runner.result, trialId: id),
        });
        guidedExportRequested = false;
        comparison = null;
        comparisonStatus = null;
        guidedSession!.remove('comparison');
      }
    });
    if (guidedIndex != null) await saveGuidedSession();
  }

  Future<void> loadCalibration() async {
    try {
      final text = await importProfile();
      if (!mounted || text == null) return;
      final parsed = ToneCalibration.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
      setState(() {
        calibration = parsed;
        calibrationStatus =
            'Loaded experimental profile ${parsed.id}. Keep route, system volume and position unchanged.';
        clearResults();
      });
    } catch (e) {
      if (mounted)
        setState(() => calibrationStatus = 'Calibration load failed: $e');
    }
  }

  void beginValidation() {
    final p = calibration!;
    if (p.sampleRate != 48000 ||
        p.toneHz != 10000 ||
        p.amplitude != amplitude ||
        p.durationSeconds != duration ||
        nearUltrasonic) {
      setState(
        () => calibrationStatus =
            'Use the matching profile settings: 10 kHz, ${p.durationSeconds} s, amplitude ${p.amplitude}.',
      );
      return;
    }
    setState(() {
      validationPlan = [
        for (var i = 0; i < 5; i++) ...[
          Scenario.stationary,
          Scenario.moving,
          Scenario.transmitterOff,
        ],
      ]..shuffle(math.Random(20261104));
      validationTrials.clear();
      slotRecorded = false;
      scenario = validationPlan!.first;
      clearResults();
    });
  }

  void nextValidation() {
    setState(() {
      scenario = validationPlan![validationTrials.length];
      slotRecorded = false;
      clearResults();
    });
  }

  Future<void> exportValidation() async {
    setState(() => exporting = true);
    try {
      final session = {
        'schemaVersion': 1,
        'kind': 'tone-held-out-validation',
        'profile': calibration!.toJson(),
        'protocol': {
          'seed': 20261104,
          'order': validationPlan!.map((s) => s.name).toList(),
          'plannedPerCondition': 5,
          'automaticEmission': false,
          'targetMovingHits': 4,
          'maximumControlFalseAlarms': 1,
          'note':
              'Preliminary local feasibility only; off/probe-absent and other unavailable decisions must be reported separately.',
        },
        'completedTrials': validationTrials.length,
        'trials': validationTrials,
      };
      final message = await saveBundle(
        jsonEncode(session),
        'phonopticon-validation-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      if (mounted) setState(() => calibrationStatus = message);
    } catch (e) {
      if (mounted)
        setState(() => calibrationStatus = 'Validation export failed: $e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  List<Widget> calibrationControls() => [
    const Divider(),
    const Text(
      'Tone calibration',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    if (calibration == null)
      const Text(
        'Load a profile fitted to separate stationary, moving and transmitter-off pilot recordings. Fresh validation is required.',
      ),
    if (calibration != null)
      Text(
        'Experimental profile ${calibration!.id} · ratio threshold ${calibration!.threshold.toStringAsPrecision(3)} · calibration trials ${calibration!.trainingCounts.values.reduce((a, b) => a + b)}',
      ),
    if (validationPlan == null)
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: runner.busy ? null : loadCalibration,
            child: const Text('Load calibration profile'),
          ),
          if (calibration != null)
            OutlinedButton(
              key: const Key('begin-validation'),
              onPressed: runner.busy ? null : beginValidation,
              child: const Text('Begin 15-trial validation'),
            ),
        ],
      ),
    if (validationPlan != null) ...[
      Text(
        'Validation ${validationTrials.length}/15 recorded · ${slotRecorded ? 'review result' : 'press Start when ready'}',
        key: const Key('validation-progress'),
      ),
      if (slotRecorded && validationTrials.length < 15)
        FilledButton(
          key: const Key('next-validation'),
          onPressed: nextValidation,
          child: const Text('Save result kept · next planned trial'),
        ),
      OutlinedButton(
        onPressed: exporting ? null : exportValidation,
        child: const Text('Export validation session'),
      ),
      const Text(
        'Every Start is manual. Failures and cancelled trials stay in the session. Export before leaving or reloading.',
      ),
    ],
    if (calibrationStatus != null) SelectableText(calibrationStatus!),
    const SizedBox(height: 12),
  ];

  Future<void> export() async {
    final capture = runner.capture;
    if (capture == null) return;
    setState(() {
      exporting = true;
      exportStatus = null;
    });
    try {
      final id = 'phonopticon-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final bundle = artifactBundle(capture, runner.result, trialId: id);
      final message = await saveBundle(jsonEncode(bundle), id);
      if (mounted) {
        setState(() {
          exportStatus = message;
          final retrievable =
              message.startsWith('Shared via selected destination:') ||
              message.startsWith('Saved to selected destination:') ||
              message.startsWith('Saved locally:') ||
              message.startsWith('Download requested:');
          guidedExportRequested = guidedIndex != null && retrievable;
        });
      }
      if (guidedIndex != null && guidedExportRequested) {
        final attempts = guidedSession?['attempts'] as List?;
        if (attempts != null && attempts.isNotEmpty) {
          (attempts.last as Map)['exported'] = true;
          await saveGuidedSession();
        }
      }
    } catch (e) {
      if (mounted) setState(() => exportStatus = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget panel(Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Semantics(container: true, explicitChildNodes: true, child: child),
    ),
  );
  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: Color(0xff526377))),
      ],
    ),
  );
  String comparisonValue(Object? value) =>
      value is num ? value.toStringAsPrecision(3) : 'unavailable';
  Widget slider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: settingsLocked ? null : changed,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final r = runner.result;
    final busy = runner.busy;
    final colors = Theme.of(context).colorScheme;
    final recording = runner.state == TrialState.running && runner.elapsed > 0;
    final probeOff =
        scenario == Scenario.transmitterOff || scenario == Scenario.silence;
    final offControlRecorded =
        breathing &&
        scenario == Scenario.transmitterOff &&
        r != null &&
        r.quality.length == 1 &&
        r.quality.single == 'No coherent chirp probe found';
    final guidedCanAdvance =
        !sessionSaving &&
        !sessionSaveFailed &&
        runner.capture != null &&
        !runner.capture!.cancelled &&
        (r?.valid == true || offControlRecorded);
    final (status, statusIcon, statusColor) = switch (runner.state) {
      TrialState.idle => (
        'IDLE · Ready to start',
        Icons.play_circle_outline,
        colors.primary,
      ),
      TrialState.preparing => (
        'Preparing audio',
        Icons.hourglass_empty,
        colors.primary,
      ),
      TrialState.running => (
        recording
            ? (native ? 'Recording' : 'Running simulation')
            : 'Preparing audio',
        recording && native ? Icons.fiber_manual_record : Icons.hourglass_empty,
        recording && native ? colors.error : colors.primary,
      ),
      TrialState.stopping => (
        'Stopping',
        Icons.stop_circle_outlined,
        colors.error,
      ),
      TrialState.complete => (
        'COMPLETE · Ready to export',
        Icons.check_circle_outline,
        colors.primary,
      ),
      TrialState.cancelled => (
        'CANCELLED',
        Icons.stop_circle_outlined,
        colors.onSurfaceVariant,
      ),
      TrialState.failed when offControlRecorded => (
        'Control recorded · Ready to export',
        Icons.volume_off_outlined,
        colors.primary,
      ),
      TrialState.failed => (
        'FAILED · Check the recording',
        Icons.error_outline,
        colors.error,
      ),
    };
    final remaining = (runDuration - runner.elapsed).clamp(0, runDuration);
    final guidedStep = guidedIndex == null ? null : guidedTrials[guidedIndex!];
    final controls = panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            'Configure a trial',
            native
                ? 'Computer microphone + speaker · experimental'
                : 'Synthetic audio · no speaker or microphone access',
          ),
          if (guidedStep == null && validationPlan == null)
            OutlinedButton.icon(
              key: const Key('begin-guided'),
              onPressed:
                  sessionLoaded &&
                      !busy &&
                      !meterActive &&
                      native &&
                      runner.backend.capabilities.available
                  ? beginGuidedSession
                  : null,
              icon: const Icon(Icons.playlist_play),
              label: const Text('Begin guided calibration'),
            ),
          if (guidedStep == null && resumableSession != null)
            OutlinedButton.icon(
              key: const Key('resume-guided'),
              onPressed: !busy && !meterActive && native
                  ? resumeGuidedSession
                  : null,
              icon: const Icon(Icons.restore),
              label: const Text('Resume saved session'),
            ),
          if (sessionStatus != null) Text(sessionStatus!),
          if (guidedStep == null && !native)
            const Text(
              'Select Computer mic + speaker to begin guided calibration.',
            ),
          if (guidedStep != null) ...[
            Text(
              'Trial ${guidedIndex! + 1} of ${guidedTrials.length} · ${guidedStep['id']}',
              key: const Key('guided-progress'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(guidedStep['instruction'] as String),
            const Text(
              'Attempts are saved locally after each trial. Export the complete session for a portable copy.',
            ),
            if (sessionSaveFailed)
              OutlinedButton(
                key: const Key('retry-save'),
                onPressed: sessionSaving ? null : saveGuidedSession,
                child: const Text('Retry saving session'),
              ),
            ExpansionTile(
              title: const Text('Session notes'),
              subtitle: Text(
                notesDirty
                    ? 'Unsaved notes'
                    : 'Operator-reported setup and observations',
              ),
              children: [
                for (final entry in const {
                  'systemVolume': 'System volume',
                  'distance': 'Reflector distance',
                  'reflector': 'Reflector type',
                  'deviceStability': 'Device stability',
                  'unexpectedSounds': 'Unexpected sounds',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      key: Key('note-${entry.key}'),
                      controller: notesControllers[entry.key],
                      enabled: !sessionSaving,
                      onChanged: (_) => setState(() => notesDirty = true),
                      decoration: InputDecoration(
                        labelText: entry.value,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                TextButton(
                  key: const Key('save-notes'),
                  onPressed: sessionSaving ? null : saveGuidedSession,
                  child: const Text('Save notes locally'),
                ),
              ],
            ),
            OutlinedButton.icon(
              key: const Key('export-guided-session'),
              onPressed: exporting || sessionSaving
                  ? null
                  : exportGuidedSession,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Export complete session'),
            ),
            TextButton(
              key: const Key('end-guided'),
              onPressed:
                  busy ||
                      exporting ||
                      sessionSaving ||
                      sessionSaveFailed ||
                      notesDirty
                  ? null
                  : () => setState(() {
                      guidedIndex = null;
                      guidedExportRequested = false;
                    }),
              child: const Text('End guided sequence'),
            ),
            const SizedBox(height: 12),
          ],
          SegmentedButton<ProbeMode>(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(56, 48)),
            ),
            segments: const [
              ButtonSegment(
                value: ProbeMode.tone,
                label: Text('Tone movement'),
              ),
              ButtonSegment(
                value: ProbeMode.chirp,
                label: Text('Chirp ranging'),
              ),
              ButtonSegment(
                value: ProbeMode.breathing,
                label: Text('Breathing'),
              ),
            ],
            showSelectedIcon: false,
            selected: {mode},
            onSelectionChanged: settingsLocked
                ? null
                : (s) => setState(() {
                    mode = s.single;
                    if (breathing) {
                      scenario = native ? Scenario.stationary : Scenario.moving;
                      nearUltrasonic = false;
                    }
                    clearResults();
                  }),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<Scenario>(
            key: ValueKey(
              '$native-$mode-${validationPlan == null ? 'free' : validationTrials.length}-$slotRecorded',
            ),
            isExpanded: true,
            initialValue: scenario,
            decoration: const InputDecoration(
              labelText: 'Trial condition',
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: Scenario.moving,
                child: Text(
                  breathing ? 'Small, slow motion' : 'Moving reflector',
                ),
              ),
              DropdownMenuItem(
                value: Scenario.stationary,
                child: Text('Stationary reflector'),
              ),
              DropdownMenuItem(
                value: Scenario.transmitterOff,
                child: Text('Transmitter off · ambient noise'),
              ),
              DropdownMenuItem(
                enabled: !native,
                value: Scenario.silence,
                child: Text('Silence'),
              ),
              DropdownMenuItem(
                enabled: !native,
                value: Scenario.invalid,
                child: Text('Invalid PCM · failure check'),
              ),
            ],
            onChanged: settingsLocked
                ? null
                : (v) => setState(() {
                    scenario = v!;
                    clearResults();
                  }),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Near-ultrasonic candidate'),
            subtitle: Text(
              nearUltrasonic
                  ? '19 kHz tone / 18–20 kHz chirp · ${native ? 'unverified hardware band' : 'simulated'}'
                  : '10 kHz tone / 3–10 kHz chirp · ${native ? 'physical' : 'simulated'}',
            ),
            value: nearUltrasonic,
            onChanged: settingsLocked
                ? null
                : (v) => setState(() {
                    nearUltrasonic = v;
                    clearResults();
                  }),
          ),
          if (breathing)
            const Text('30-second foreground capture · manual Start and Stop')
          else
            slider(
              'Duration · ${duration.toStringAsFixed(0)} s / 10 s maximum',
              duration,
              1,
              10,
              9,
              (v) => setState(() {
                duration = v;
                clearResults();
              }),
            ),
          slider(
            'Digital peak amplitude · ${amplitude.toStringAsFixed(3)}',
            amplitude,
            0.005,
            0.05,
            9,
            (v) => setState(() {
              amplitude = v;
              clearResults();
            }),
          ),
          if (!native || breathing)
            slider(
              '${breathing ? 'Echo window center' : 'Fixture reflector range'} · ${range.toStringAsFixed(2)} m',
              range,
              0.3,
              1.0,
              14,
              (v) => setState(() {
                range = v;
                clearResults();
              }),
            ),
          if (!native && !breathing)
            const Text(
              '48 kHz · seed 42 · ±0.12 m motion at 0.7 Hz. Fixture parameters are not measurement results.',
              style: TextStyle(fontSize: 12, color: Color(0xff526377)),
            ),
          const Divider(height: 28),
          DropdownButtonFormField<bool>(
            isExpanded: true,
            initialValue: native,
            decoration: const InputDecoration(
              labelText: 'Audio backend',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: false,
                child: Text('Simulated PCM'),
              ),
              DropdownMenuItem(
                value: true,
                child: Text(
                  computerBackendAvailable()
                      ? 'Computer mic + speaker (experimental)'
                      : 'Native audio · unavailable',
                ),
              ),
            ],
            onChanged: settingsLocked || widget.backend != null
                ? null
                : (v) async {
                    await runner.dispose();
                    if (!mounted) return;
                    setState(() {
                      native = v!;
                      if (native) scenario = Scenario.stationary;
                      _makeRunner();
                      clearResults();
                    });
                  },
          ),
          const SizedBox(height: 14),
          if (native)
            Text(
              runner.backend.capabilities.available
                  ? probeOff
                        ? 'Start records the microphone with the speaker probe off.'
                        : 'Start records the microphone and plays a low-level probe. Use built-in speakers at low volume.'
                  : 'Native backend is not implemented. No silent fallback to simulation.',
              style: TextStyle(color: Color(0xffa25d18)),
            ),
          if (native && mode == ProbeMode.tone && guidedStep == null)
            ...calibrationControls(),
          if (runner.backend is MicrophoneMeterBackend) ...[
            const SizedBox(height: 12),
            const Text(
              'Microphone check: speak to see input level. No probe sound is played.',
            ),
            LinearProgressIndicator(
              key: const Key('meter-level'),
              value: meterLevel,
              semanticsLabel: 'Microphone input level',
            ),
            Wrap(
              children: [
                TextButton.icon(
                  key: const Key('start-meter'),
                  onPressed: busy || meterActive || sessionSaving
                      ? null
                      : startMeter,
                  icon: const Icon(Icons.mic),
                  label: const Text('Start microphone check'),
                ),
                TextButton.icon(
                  key: const Key('stop-meter'),
                  onPressed: meterActive ? stopMeter : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop check'),
                ),
              ],
            ),
            if (meterStatus != null) Text(meterStatus!),
          ],
          const SizedBox(height: 12),
          TrialGuide(
            mode: mode,
            scenario: scenario,
            physical: native,
            validatingTone: validationPlan != null,
            recording: recording,
            elapsed: runner.elapsed,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('start'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed:
                      busy ||
                          meterActive ||
                          sessionSaving ||
                          sessionSaveFailed ||
                          slotRecorded ||
                          !runner.backend.capabilities.available
                      ? null
                      : start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start trial'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const Key('stop'),
                onPressed: busy ? runner.stop : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  minimumSize: const Size(88, 48),
                ),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            semanticsLabel: 'Trial progress',
            color: statusColor,
            value: busy
                ? (runner.elapsed / runDuration).clamp(0.0, 1.0)
                : (runner.state == TrialState.complete || offControlRecorded
                      ? 1
                      : 0),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(statusIcon, size: 20, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    key: const Key('trial-state'),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (busy) Text('${remaining.toStringAsFixed(1)} s left'),
            ],
          ),
          if (runner.error != null && !offControlRecorded)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(runner.error!, style: TextStyle(color: colors.error)),
            ),
          if (r?.quality.contains(silentMicrophoneInput) ?? false)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Check the Mac’s Sound input meter. Then try Tone movement → Transmitter off for 4 seconds while speaking.',
              ),
            ),
          if (guidedStep != null &&
              runner.capture != null &&
              !guidedCanAdvance &&
              !sessionSaving)
            const Text(
              'This capture needs attention. Retry the trial before continuing.',
            ),
          if (guidedStep != null && guidedCanAdvance) ...[
            const SizedBox(height: 12),
            Text(
              guidedIndex == 0
                  ? 'Confirm the microphone check captured your voice before continuing.'
                  : 'The attempt was saved locally. You can retry it or continue.',
            ),
            FilledButton.icon(
              key: const Key('next-guided'),
              onPressed: () async {
                if (guidedIndex! + 1 == guidedTrials.length) {
                  guidedSession!['complete'] = true;
                  compareGuided();
                  await saveGuidedSession();
                } else {
                  applyGuidedStep(guidedIndex! + 1);
                  await saveGuidedSession();
                }
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                guidedIndex! + 1 == guidedTrials.length
                    ? 'Finish guided sequence'
                    : 'Next trial',
              ),
            ),
          ],
          if (comparisonStatus != null) Text(comparisonStatus!),
          if (comparison != null) ...[
            const SizedBox(height: 12),
            Text(
              'Calibration criteria ${comparison!['calibrationCriteriaMet'] == true ? 'met' : 'not met'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Stationary control quiet: ${comparison!['stationaryControlQuiet']} · Transmitter-off rejected: ${comparison!['offProbeRejected']} · Motion cadence recovered: ${comparison!['movingCadenceRecovered']}',
            ),
            Text(
              'Fixed periodic fraction ≥ ${((comparison!['minimumPeriodicFraction'] as num) * 100).toStringAsFixed(0)}%; motion RMS threshold ${comparison!['periodicRmsThreshold']}.',
            ),
            for (final row in comparison!['trials'] as List)
              Text(
                '${(row as Map)['condition']}: peak ${comparisonValue((row['analysis'] as Map)['peakHz'])} Hz · periodic fraction ${comparisonValue((row['analysis'] as Map)['periodicFraction'])} · periodic RMS ${comparisonValue((row['analysis'] as Map)['periodicRms'])}',
              ),
            const Text(
              'Operator-paced movement; timing and displacement are not independently measured. This is not a breathing or medical validation.',
            ),
          ],
        ],
      ),
    );
    final results = panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            'Inspect the evidence',
            r == null
                ? 'Run a trial to inspect audio-derived results.'
                : offControlRecorded
                ? (native
                      ? 'The microphone recorded with the chirp off.'
                      : 'Simulated ambient audio with the chirp off.')
                : !r.valid
                ? 'Unknown · analysis unavailable'
                : breathing
                ? 'Experimental echo trace · compare with both controls'
                : r.movementDetected
                ? (native
                      ? (r.settings['calibrationProfile'] != null
                            ? 'Movement above frozen calibration threshold'
                            : 'Score above uncalibrated threshold')
                      : 'Movement above fixture threshold')
                : (native
                      ? (r.settings['calibrationProfile'] != null
                            ? 'No movement above frozen calibration threshold'
                            : 'Score below uncalibrated threshold')
                      : 'No movement above fixture threshold'),
          ),
          if (r == null)
            SizedBox(
              height: 330,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.waves, size: 60, color: Color(0xff86a2ac)),
                    SizedBox(height: 16),
                    Text('Your experiment starts here'),
                    SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          if (r != null && !r.valid && !offControlRecorded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(r.quality.join('\n')),
            ),
          if (r != null && r.frames.isNotEmpty) ...[
            Text(
              mode == ProbeMode.tone
                  ? 'Doppler spectrum over time'
                  : 'Equivalent range over time',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TrialPlot(result: r),
            const SizedBox(height: 15),
            Text(
              breathing
                  ? 'Slow echo variation over time'
                  : r.settings['calibrationProfile'] == null
                  ? 'Movement score · threshold ${r.threshold} · at least 2 frames'
                  : 'Received sideband/carrier ratio · trial 80th percentile threshold ${r.threshold.toStringAsPrecision(3)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TrialPlot(result: r, movement: true),
            if (breathing)
              Text(
                'Candidate rhythm: ${(r.settings['peakHz'] as double).toStringAsFixed(2)} Hz · periodic fraction ${(r.settings['periodicFraction'] as double).toStringAsFixed(2)}. Echo variation is relative to the direct probe.',
              ),
            if (r.settings['calibrationProfile'] != null)
              Text(
                'Trial ratio score: ${r.settings['trialScore']} · usable carrier fraction: ${r.settings['carrierFraction']} · experimental calibration',
              ),
            const SizedBox(height: 8),
            Text('Frame inspector · ${r.frames.length} frames'),
            Slider(
              key: const Key('frame-inspector'),
              value: selectedFrame.clamp(0, r.frames.length - 1).toDouble(),
              min: 0,
              max: (r.frames.length - 1).toDouble(),
              divisions: r.frames.length > 1 ? r.frames.length - 1 : null,
              onChanged: (v) => setState(() => selectedFrame = v.round()),
            ),
            Builder(
              builder: (_) {
                final f = r.frames[selectedFrame.clamp(0, r.frames.length - 1)];
                if (breathing)
                  return Text(
                    '${f.time.toStringAsFixed(3)} s · echo variation ${f.movement.toStringAsFixed(4)}',
                  );
                return Text(
                  '${f.time.toStringAsFixed(3)} s · movement ${f.movement.toStringAsFixed(4)}'
                  '${mode == ProbeMode.chirp ? ' · equivalent range ${f.range == null ? 'unavailable' : '${f.range!.toStringAsFixed(3)} m'}' : ' · single tone provides no absolute range'}',
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Native spectral bin: ${r.nativeBinWidth.toStringAsFixed(4)} ${mode == ProbeMode.tone ? 'Hz' : 'm equivalent'}. '
              '${mode == ProbeMode.chirp ? 'Alignment: ${r.alignmentSamples} samples. ' : ''}Zero padding does not increase physical resolution.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const Divider(height: 30),
          FilledButton.tonalIcon(
            key: const Key('export'),
            onPressed: runner.capture == null || busy || exporting
                ? null
                : export,
            icon: const Icon(Icons.download),
            label: Text(
              exporting ? 'Preparing export…' : 'Save or share trial bundle',
            ),
          ),
          if (exportStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SelectableText(exportStatus!),
            ),
          const SizedBox(height: 12),
          const Text(
            'JSON bundle: raw WAVs, configuration, timing, analysis arrays, metrics CSV and SVG plots. No upload.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Phonopticon',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Chip(
                        avatar: const Icon(Icons.science_outlined, size: 18),
                        label: Text(
                          native
                              ? 'PHYSICAL · experimental capture'
                              : 'SIMULATED · feasibility runner',
                        ),
                      ),
                      IconButton(
                        tooltip: 'About and licenses',
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => showAboutDialog(
                          context: context,
                          applicationName: 'Phonopticon',
                          applicationVersion: '0.1.0',
                          applicationLegalese:
                              'Independent acoustic feasibility experiment. '
                              'Background: Joao Nuno Carvalho FMCW exploration; Nandakumar, Gollakota and Watson, ApneaApp; Gupta et al., SoundWave. '
                              'No upstream recordings or source code are redistributed. See THIRD_PARTY_NOTICES.md.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Explore acoustic motion and ranging with reproducible local experiments.',
                  ),
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, box) => box.maxWidth >= 950
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 430, child: controls),
                              const SizedBox(width: 20),
                              Expanded(child: results),
                            ],
                          )
                        : Column(
                            children: [
                              controls,
                              const SizedBox(height: 20),
                              results,
                            ],
                          ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    native
                        ? 'Physical recording is experimental. Echo processing, latency and hardware response need calibration; fixture thresholds are not validated physical detections. Keep recordings local. Not a medical device.'
                        : 'Simulation verifies the workflow and numerical model. It does not validate phone frequency response, processing, latency, multipath or physical detection. Not a medical device.',
                    style: TextStyle(color: Color(0xff526377)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
