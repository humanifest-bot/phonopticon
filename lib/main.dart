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
import 'ui/recording_diagnostics.dart';
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
  String? sessionBaseline, resumableBaseline;
  bool sessionConflict = false;
  Map? currentGuidedAttempt;
  List<String> savedSessionIds = [];
  bool sessionOpening = false;
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
  RecordingDiagnostics? recordingDiagnostics;
  String? diagnosticStatus;
  AlignedTrialTraces? trialTraces;
  List<({String id, RecordingDiagnostics summary})> comparisonDiagnostics = [];
  String? comparisonDiagnosticStatus;
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
      sessionOpening ||
      exporting ||
      meterActive;

  Future<void> loadSavedSession() async {
    try {
      final value = await sessionStore.loadLatest();
      if (mounted && value != null) {
        final decoded = decodeSavedSession(value);
        setState(() {
          resumableSession = decoded;
          resumableBaseline = value;
          sessionStatus = 'A local session is available to resume.';
        });
      }
    } catch (error) {
      if (mounted)
        setState(() => sessionStatus = 'Session restore unavailable: $error');
    } finally {
      await refreshSessionList();
      if (mounted) setState(() => sessionLoaded = true);
    }
  }

  Map<String, dynamic> decodeSavedSession(String value, {String? expectedId}) {
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['id'] is! String ||
        (expectedId != null && decoded['id'] != expectedId) ||
        decoded['attempts'] is! List ||
        (decoded['selectedAttempts'] != null &&
            decoded['selectedAttempts'] is! Map) ||
        decoded['index'] is! int ||
        (decoded['index'] as int) < 0 ||
        (decoded['index'] as int) >= guidedTrials.length) {
      throw const FormatException('Unsupported or invalid saved session');
    }
    for (final attempt in decoded['attempts'] as List) {
      if (attempt is! Map) throw const FormatException('Invalid saved attempt');
      final bundle = attempt['bundle'];
      if (bundle != null &&
          (bundle is! Map ||
              bundle['manifest'] is! Map ||
              (bundle['manifest'] as Map)['trialId'] is! String ||
              bundle['files'] is! Map)) {
        throw const FormatException('Invalid saved attempt bundle');
      }
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> refreshSessionList() async {
    final store = sessionStore;
    if (store is! SessionArchive) return;
    try {
      final ids = await (store as SessionArchive).listSessionIds();
      if (mounted) setState(() => savedSessionIds = ids.reversed.toList());
    } catch (error) {
      if (mounted)
        setState(() => sessionStatus = 'Session list unavailable: $error');
    }
  }

  Future<void> openSavedSession(String id) async {
    final store = sessionStore;
    if (store is! SessionArchive ||
        sessionOpening ||
        guidedIndex != null ||
        runner.busy ||
        meterActive ||
        exporting)
      return;
    setState(() {
      sessionOpening = true;
      sessionStatus = 'Opening saved session…';
    });
    try {
      final value = await (store as SessionArchive).loadById(id);
      if (value == null) throw StateError('Saved session is missing.');
      final decoded = decodeSavedSession(value, expectedId: id);
      if (!mounted) return;
      resumableSession = decoded;
      resumableBaseline = value;
      final restored = resumeGuidedSession(fromArchive: true);
      if (mounted && restored)
        setState(() => sessionStatus = 'Opened local session $id.');
    } catch (error) {
      if (mounted)
        setState(() => sessionStatus = 'Could not open session $id: $error');
    } finally {
      if (mounted) setState(() => sessionOpening = false);
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
      final snapshot = jsonEncode(session);
      final store = sessionStore;
      if (store is GuardedSessionStore) {
        await (store as GuardedSessionStore).saveIfUnchanged(
          session['id'] as String,
          snapshot,
          expectedSnapshot: sessionBaseline,
        );
      } else {
        await store.save(session['id'] as String, snapshot);
      }
      if (mounted)
        setState(() {
          sessionStatus = 'Session saved locally.';
          resumableSession = session;
          sessionBaseline = snapshot;
          resumableBaseline = snapshot;
          sessionConflict = false;
          final id = session['id'] as String;
          if (!savedSessionIds.contains(id)) {
            savedSessionIds = [id, ...savedSessionIds];
          }
          sessionSaveFailed = false;
          notesDirty = false;
        });
      return true;
    } catch (error) {
      if (mounted)
        setState(() {
          sessionSaveFailed = true;
          sessionConflict = error is SessionWriteConflict;
          sessionStatus = sessionConflict
              ? 'Session changed in another window or is locked. Export your work or save it as a new session.'
              : 'Session save failed: $error. Retry saving before continuing.';
        });
      return false;
    } finally {
      if (mounted) setState(() => sessionSaving = false);
    }
  }

  String newSessionId() {
    final random = math.Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'session-${DateTime.now().toUtc().microsecondsSinceEpoch}-$nonce';
  }

  Future<void> saveGuidedAsCopy() async {
    final session = guidedSession;
    if (session == null || sessionSaving || exporting || !sessionConflict)
      return;
    final previousId = session['id'];
    final String copyId;
    try {
      copyId = newSessionId();
    } catch (_) {
      setState(
        () => sessionStatus =
            'Could not create a secure session ID. Export your current work.',
      );
      return;
    }
    setState(() {
      session['id'] = copyId;
      session['copiedFromSessionId'] = previousId;
      session['copiedUtc'] = DateTime.now().toUtc().toIso8601String();
      sessionBaseline = null;
      sessionConflict = false;
    });
    await saveGuidedSession();
  }

  Future<void> beginGuidedSession() async {
    if (sessionOpening ||
        guidedIndex != null ||
        runner.busy ||
        meterActive ||
        exporting)
      return;
    final String id;
    try {
      id = newSessionId();
    } catch (_) {
      setState(
        () => sessionStatus =
            'Could not create a secure session ID. Existing sessions are unchanged.',
      );
      return;
    }
    for (final controller in notesControllers.values) {
      controller.clear();
    }
    guidedSession = {
      'schemaVersion': 1,
      'id': id,
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
      sessionConflict = false;
      sessionBaseline = null;
    });
    applyGuidedStep(0);
    await saveGuidedSession();
  }

  bool resumeGuidedSession({bool fromArchive = false}) {
    if ((sessionOpening && !fromArchive) ||
        guidedIndex != null ||
        runner.busy ||
        meterActive ||
        exporting)
      return false;
    final saved = resumableSession;
    if (saved == null) return false;
    guidedSession = saved;
    sessionBaseline = resumableBaseline;
    final notes = saved['notes'];
    for (final entry in notesControllers.entries) {
      entry.value.text = notes is Map && notes[entry.key] is String
          ? notes[entry.key] as String
          : '';
    }
    comparison = null;
    comparisonStatus = null;
    applyGuidedStep(saved['index'] as int);
    final restored = restoreLatestStepAttempt();
    setState(() {
      resumableSession = null;
      notesDirty = false;
    });
    if (saved['complete'] == true &&
        (!restored || !canFinishGuided || !compareGuided()))
      saved['complete'] = false;
    return restored;
  }

  bool restoreLatestStepAttempt() {
    final attempts = (guidedSession?['attempts'] as List? ?? const [])
        .whereType<Map>()
        .where((a) => a['step'] == guidedIndex)
        .toList();
    if (attempts.isEmpty) return true;
    final last = attempts.last;
    currentGuidedAttempt = last;
    try {
      final bundle = last['bundle'];
      if (bundle is Map) {
        runner.capture = readPhysicalBundle(
          Map<String, dynamic>.from(bundle),
          mode: mode,
        );
        if (!runner.capture!.cancelled)
          runner.result = analyze(runner.capture!);
        recordingDiagnostics = summarizeRecording(
          runner.capture!,
          analysis: runner.result,
        );
      }
      runner.state = TrialState.values.byName(last['state'] as String);
      runner.error = last['error'] as String?;
      guidedExportRequested = last['exported'] == true;
    } catch (error) {
      runner.capture = null;
      runner.result = null;
      runner.state = TrialState.failed;
      recordingDiagnostics = null;
      runner.error = 'Saved attempt could not be restored: $error';
      sessionStatus = runner.error;
      return false;
    }
    return true;
  }

  List<int> comparisonCandidates(int step) {
    final attempts = guidedSession?['attempts'] as List? ?? const [];
    return [
      for (var i = 0; i < attempts.length; i++)
        if (attempts[i] is Map &&
            attempts[i]['step'] == step &&
            attempts[i]['bundle'] is Map &&
            (attempts[i]['bundle'] as Map)['manifest'] is Map &&
            ((attempts[i]['bundle'] as Map)['manifest'] as Map)['trialId']
                is String &&
            attempts[i]['state'] != 'cancelled')
          i,
    ];
  }

  int? selectedComparisonAttempt(int step) {
    final candidates = comparisonCandidates(step);
    if (candidates.isEmpty) return null;
    final selected = (guidedSession?['selectedAttempts'] as Map?)?['$step'];
    return selected is int && candidates.contains(selected)
        ? selected
        : candidates.last;
  }

  String attemptLabel(int index) {
    final attempt = (guidedSession!['attempts'] as List)[index] as Map;
    final bundle = attempt['bundle'] as Map;
    final manifest = bundle['manifest'] as Map;
    final number = (guidedSession!['attempts'] as List)
        .take(index + 1)
        .where((a) => a is Map && a['step'] == attempt['step'])
        .length;
    return 'Attempt $number · ${manifest['trialId']} · ${manifest['startedUtc']} · ${attempt['state']}';
  }

  String attemptHistoryLabel(int index) {
    final attempt = (guidedSession!['attempts'] as List)[index] as Map;
    final step = attempt['step'];
    final condition = step is int && step >= 0 && step < guidedTrials.length
        ? guidedTrials[step]['id']
        : 'unknown condition';
    final bundle = attempt['bundle'];
    final manifest = bundle is Map ? bundle['manifest'] : null;
    final id = manifest is Map ? manifest['trialId'] : null;
    final time = manifest is Map
        ? manifest['startedUtc']
        : (attempt['loggedUtc'] ?? attempt['endedUtc']);
    final error = attempt['error'];
    return '${index + 1}. $condition · ${attempt['state'] ?? 'unknown'} · ${id ?? 'no audio bundle'} · ${time ?? 'time unavailable'}${error == null ? '' : '\n$error'}';
  }

  bool compareGuided() {
    final session = guidedSession;
    if (session == null) return false;
    try {
      final attempts = session['attempts'] as List;
      final captures = <AudioCapture>[];
      final ids = <String?>[];
      final revisions = <String?>[];
      List<AnalysisResult>? analyzed;
      for (var step = 1; step <= 3; step++) {
        final selected = selectedComparisonAttempt(step);
        if (selected == null)
          throw StateError(
            'Complete a stationary, motion and transmitter-off trial first.',
          );
        final bundle = Map<String, dynamic>.from(
          (attempts[selected] as Map)['bundle'] as Map,
        );
        captures.add(readPhysicalBundle(bundle, mode: ProbeMode.breathing));
        ids.add((bundle['manifest'] as Map)['trialId'] as String?);
        revisions.add((bundle['manifest'] as Map)['sourceRevision'] as String?);
      }
      final result = compareBreathingCaptures(
        captures,
        trialIds: ids,
        sourceRevisions: revisions,
        onAnalyzed: (results) => analyzed = results,
      );
      final results = analyzed!;
      trialTraces = alignTrialTraces({
        'Stationary': results[0],
        'Moving': results[1],
        'Transmitter off': results[2],
      });
      try {
        comparisonDiagnostics = [
          for (var i = 0; i < captures.length; i++)
            (
              id: ids[i] ?? 'unknown trial',
              summary: summarizeRecording(captures[i], analysis: results[i]),
            ),
        ];
        comparisonDiagnosticStatus = null;
      } catch (error) {
        comparisonDiagnostics = [];
        comparisonDiagnosticStatus =
            'Selected-recording diagnostics unavailable: $error';
      }
      setState(() {
        comparison = result;
        comparisonStatus = null;
        session['comparison'] = result;
      });
      return true;
    } catch (error) {
      setState(() {
        comparison = null;
        trialTraces = null;
        comparisonDiagnostics = [];
        comparisonDiagnosticStatus = null;
        comparisonStatus = 'Comparison unavailable: $error';
        session.remove('comparison');
      });
      return false;
    }
  }

  bool get hasCompletedMicrophoneCheck =>
      (guidedSession?['attempts'] as List? ?? const []).any(
        (attempt) =>
            attempt is Map &&
            attempt['step'] == 0 &&
            attempt['state'] == 'complete' &&
            attempt['bundle'] is Map,
      );

  bool get canFinishGuided =>
      hasCompletedMicrophoneCheck &&
      [1, 2, 3].every((step) => selectedComparisonAttempt(step) != null);

  Future<void> exportGuidedSession() async {
    if (guidedSession == null) return;
    setState(() {
      exporting = true;
      exportStatus = null;
    });
    try {
      final id = guidedSession!['id'] as String;
      final snapshot = Map<String, dynamic>.from(guidedSession!)
        ..['notes'] = {
          for (final entry in notesControllers.entries)
            entry.key: entry.value.text,
        };
      final message = await saveBundle(jsonEncode(snapshot), 'phonopticon-$id');
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
              meterStatus = level < .001
                  ? 'Input is currently very low. Speak or check the selected microphone; silence alone does not prove a fault.'
                  : 'Microphone level · no sound emitted or samples saved';
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
      currentGuidedAttempt = null;
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
    recordingDiagnostics = null;
    diagnosticStatus = null;
    exportStatus = null;
    selectedFrame = 0;
  }

  Future<void> start() async {
    setState(() {
      selectedFrame = 0;
      exportStatus = null;
      recordingDiagnostics = null;
      diagnosticStatus = null;
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
    RecordingDiagnostics? diagnostic;
    String? diagnosticError;
    try {
      if (runner.capture != null) {
        diagnostic = summarizeRecording(
          runner.capture!,
          analysis: runner.result,
        );
      }
    } catch (error) {
      diagnosticError = 'Recording diagnostics unavailable: $error';
    }
    setState(() {
      recordingDiagnostics = diagnostic;
      diagnosticStatus = diagnosticError;
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
          'loggedUtc': DateTime.now().toUtc().toIso8601String(),
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
        final attempts = guidedSession!['attempts'] as List;
        final attempt = {
          'step': guidedIndex,
          'id': guidedTrials[guidedIndex!]['id'],
          'state': runner.state.name,
          'error': runner.error,
          'loggedUtc': DateTime.now().toUtc().toIso8601String(),
          'operatorNotes': {
            for (final entry in notesControllers.entries)
              entry.key: entry.value.text,
          },
          'exported': false,
          'bundle': capture == null
              ? null
              : artifactBundle(capture, runner.result, trialId: id),
        };
        attempts.add(attempt);
        currentGuidedAttempt = attempt;
        if (capture != null && !capture.cancelled && guidedIndex! > 0) {
          final selection =
              (guidedSession!['selectedAttempts'] ??= <String, dynamic>{})
                  as Map;
          selection['$guidedIndex'] = attempts.length - 1;
        }
        guidedExportRequested = false;
        comparison = null;
        trialTraces = null;
        comparisonDiagnostics = [];
        comparisonDiagnosticStatus = null;
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
    final exportedAttempt = currentGuidedAttempt;
    setState(() {
      exporting = true;
      exportStatus = null;
    });
    try {
      final savedBundle = exportedAttempt?['bundle'];
      final bundle = guidedIndex != null && savedBundle is Map
          ? Map<String, dynamic>.from(savedBundle)
          : artifactBundle(capture, runner.result);
      final id = (bundle['manifest'] as Map)['trialId'] as String;
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
        if (exportedAttempt != null) {
          exportedAttempt['exported'] = true;
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
        !busy &&
        !exporting &&
        !meterActive &&
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
                      !sessionOpening &&
                      !exporting &&
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
              onPressed:
                  !busy &&
                      !meterActive &&
                      !sessionOpening &&
                      !exporting &&
                      native
                  ? () => resumeGuidedSession()
                  : null,
              icon: const Icon(Icons.restore),
              label: const Text('Resume saved session'),
            ),
          if (guidedStep == null && savedSessionIds.isNotEmpty)
            ExpansionTile(
              key: const Key('saved-sessions'),
              title: Text('Saved sessions (${savedSessionIds.length})'),
              subtitle: const Text(
                'Choose a saved session to review or resume.',
              ),
              children: [
                for (final id in savedSessionIds)
                  ListTile(
                    key: Key('open-session-$id'),
                    title: Text(id),
                    trailing: const Icon(Icons.chevron_right),
                    enabled:
                        !busy &&
                        !meterActive &&
                        !sessionOpening &&
                        !exporting &&
                        native,
                    onTap:
                        !busy &&
                            !meterActive &&
                            !sessionOpening &&
                            !exporting &&
                            native
                        ? () => openSavedSession(id)
                        : null,
                  ),
              ],
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
            DropdownButtonFormField<int>(
              key: const Key('guided-step-selector'),
              initialValue: guidedIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Review or retry a trial',
              ),
              items: [
                for (var i = 0; i < guidedTrials.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text('${i + 1}. ${guidedTrials[i]['id']}'),
                  ),
              ],
              onChanged:
                  busy ||
                      sessionSaving ||
                      sessionSaveFailed ||
                      notesDirty ||
                      exporting ||
                      meterActive
                  ? null
                  : (index) async {
                      if (index == null || index == guidedIndex) return;
                      applyGuidedStep(index);
                      restoreLatestStepAttempt();
                      if (mounted) setState(() {});
                      await saveGuidedSession();
                    },
            ),
            const Text(
              'Attempts are saved locally after each trial. Export the complete session for a portable copy.',
            ),
            if (sessionSaveFailed)
              OutlinedButton(
                key: const Key('retry-save'),
                onPressed: sessionSaving || exporting
                    ? null
                    : saveGuidedSession,
                child: const Text('Retry saving session'),
              ),
            if (sessionConflict)
              OutlinedButton.icon(
                key: const Key('save-session-copy'),
                onPressed: sessionSaving || exporting ? null : saveGuidedAsCopy,
                icon: const Icon(Icons.copy),
                label: const Text('Save as a new local session'),
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
                      enabled: !sessionSaving && !exporting,
                      onChanged: (_) => setState(() => notesDirty = true),
                      decoration: InputDecoration(
                        labelText: entry.value,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                TextButton(
                  key: const Key('save-notes'),
                  onPressed: sessionSaving || exporting
                      ? null
                      : saveGuidedSession,
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
                  onPressed:
                      busy ||
                          meterActive ||
                          sessionSaving ||
                          exporting ||
                          sessionOpening
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
                          sessionOpening ||
                          exporting ||
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
            if (guidedIndex == guidedTrials.length - 1 && !canFinishGuided)
              const Text(
                'Complete the microphone check and all three comparison recordings before finishing.',
              ),
            FilledButton.icon(
              key: const Key('next-guided'),
              onPressed:
                  guidedIndex == guidedTrials.length - 1 && !canFinishGuided
                  ? null
                  : () async {
                      if (guidedIndex! + 1 == guidedTrials.length) {
                        guidedSession!['complete'] = compareGuided();
                        await saveGuidedSession();
                      } else {
                        applyGuidedStep(guidedIndex! + 1);
                        restoreLatestStepAttempt();
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
          if (guidedStep != null) ...[
            const SizedBox(height: 12),
            if ((guidedSession?['attempts'] as List? ?? const []).isNotEmpty)
              ExpansionTile(
                title: Text(
                  'Attempt history (${(guidedSession!['attempts'] as List).length})',
                ),
                subtitle: const Text('Includes failed and cancelled attempts.'),
                children: [
                  for (
                    var i = 0;
                    i < (guidedSession!['attempts'] as List).length;
                    i++
                  )
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(attemptHistoryLabel(i)),
                    ),
                ],
              ),
            const Text(
              'Comparison recordings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'The latest eligible attempt is selected initially. Check or change each selection; cancelled and missing captures are not eligible.',
            ),
            for (var step = 1; step <= 3; step++)
              if (comparisonCandidates(step).isNotEmpty)
                DropdownButtonFormField<int>(
                  key: Key('comparison-attempt-$step'),
                  initialValue: selectedComparisonAttempt(step),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '${guidedTrials[step]['id']} recording',
                  ),
                  selectedItemBuilder: (context) => [
                    for (final index in comparisonCandidates(step))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          attemptLabel(index),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  items: [
                    for (final index in comparisonCandidates(step))
                      DropdownMenuItem(
                        value: index,
                        child: Text(
                          attemptLabel(index),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged:
                      busy ||
                          meterActive ||
                          sessionSaving ||
                          sessionSaveFailed ||
                          notesDirty ||
                          exporting
                      ? null
                      : (index) async {
                          if (index == null) return;
                          final selection =
                              (guidedSession!['selectedAttempts'] ??=
                                      <String, dynamic>{})
                                  as Map;
                          selection['$step'] = index;
                          if (guidedSession!['complete'] == true) {
                            guidedSession!['complete'] = compareGuided();
                          } else {
                            setState(() {
                              comparison = null;
                              trialTraces = null;
                              comparisonStatus = null;
                              guidedSession!.remove('comparison');
                            });
                          }
                          await saveGuidedSession();
                        },
                ),
            for (var step = 1; step <= 3; step++)
              if (selectedComparisonAttempt(step) != null)
                SelectableText(
                  'Selected ${guidedTrials[step]['id']}: ${attemptLabel(selectedComparisonAttempt(step)!)}',
                ),
            if ([
              1,
              2,
              3,
            ].every((step) => selectedComparisonAttempt(step) != null))
              TextButton(
                key: const Key('compare-selected'),
                onPressed:
                    busy ||
                        sessionSaving ||
                        sessionSaveFailed ||
                        notesDirty ||
                        exporting
                    ? null
                    : () async {
                        compareGuided();
                        await saveGuidedSession();
                      },
                child: const Text('Compare selected attempts'),
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
            const Text(
              'Matching reported settings does not verify the physical output route, system volume, or unreported audio processing.',
            ),
            if (trialTraces != null)
              TrialTraceComparisonPanel(comparison: trialTraces!),
            if (comparisonDiagnosticStatus != null)
              Text(comparisonDiagnosticStatus!),
            if (comparisonDiagnostics.isNotEmpty)
              ExpansionTile(
                title: const Text('Quality of selected recordings'),
                subtitle: const Text(
                  'Values are tied to the IDs used in this comparison.',
                ),
                children: [
                  for (final item in comparisonDiagnostics)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: RecordingDiagnosticsPanel(
                        summary: item.summary,
                        label: item.id,
                      ),
                    ),
                ],
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
          if (recordingDiagnostics != null) ...[
            RecordingDiagnosticsPanel(
              summary: recordingDiagnostics!,
              label:
                  currentGuidedAttempt?['bundle'] is Map &&
                      (currentGuidedAttempt!['bundle'] as Map)['manifest']
                          is Map
                  ? 'Current displayed recording · ${((currentGuidedAttempt!['bundle'] as Map)['manifest'] as Map)['trialId']}'
                  : 'Current displayed recording',
            ),
            const SizedBox(height: 16),
          ],
          if (diagnosticStatus != null) Text(diagnosticStatus!),
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
