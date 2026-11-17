import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'audio/audio_backend.dart';
import 'audio/computer_backend.dart';
import 'audio/simulated_backend.dart';
import 'calibration/tone_calibration.dart';
import 'calibration/import_profile.dart';
import 'domain/experiment.dart';
import 'export/artifacts.dart';
import 'export/export_bundle.dart';
import 'runner/trial_runner.dart';
import 'signal/analysis.dart' show silentMicrophoneInput;
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
  const PhonopticonApp({super.key, this.backend, this.initialCalibration});
  final AudioBackend? backend;
  final ToneCalibration? initialCalibration;
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
    ),
  );
}

class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({super.key, this.backend, this.initialCalibration});
  final AudioBackend? backend;
  final ToneCalibration? initialCalibration;
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
      runner.busy || validationPlan != null || guidedIndex != null;

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
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    native = widget.backend?.capabilities.sourceKind == 'PHYSICAL';
    calibration = widget.initialCalibration;
    _makeRunner();
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && runner.busy) runner.stop();
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
    });
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
        'Validation ${validationTrials.length}/15 saved · ${slotRecorded ? 'review result' : 'press Start when ready'}',
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
          guidedExportRequested = guidedIndex != null;
        });
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
        guidedExportRequested &&
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
                  !busy && native && runner.backend.capabilities.available
                  ? () => applyGuidedStep(0)
                  : null,
              icon: const Icon(Icons.playlist_play),
              label: const Text('Begin guided calibration'),
            ),
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
              'Export each trial before continuing. Progress resets if this page reloads.',
            ),
            TextButton(
              key: const Key('end-guided'),
              onPressed: busy || exporting
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
                  onPressed:
                      busy ||
                          slotRecorded ||
                          (guidedStep != null && guidedCanAdvance) ||
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
                style: OutlinedButton.styleFrom(foregroundColor: colors.error),
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
          if (guidedStep != null && guidedExportRequested && !guidedCanAdvance)
            const Text(
              'This capture needs attention. Retry the trial before continuing.',
            ),
          if (guidedStep != null && guidedCanAdvance) ...[
            const SizedBox(height: 12),
            Text(
              guidedIndex == 0
                  ? 'Confirm the microphone check captured your voice before continuing.'
                  : 'Confirm the trial bundle downloaded before continuing.',
            ),
            FilledButton.icon(
              key: const Key('next-guided'),
              onPressed: () {
                if (guidedIndex! + 1 == guidedTrials.length) {
                  setState(() {
                    guidedIndex = null;
                    guidedExportRequested = false;
                  });
                } else {
                  applyGuidedStep(guidedIndex! + 1);
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
              exporting ? 'Preparing export…' : 'Export local trial bundle',
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
