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
import 'ui/plots.dart';

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
  bool get settingsLocked => runner.busy || validationPlan != null;
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
        durationSeconds: duration,
        amplitude: amplitude,
        rangeMeters: range,
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
      Text(
        scenario == Scenario.stationary
            ? 'Sit still and avoid speaking for the full trial.'
            : scenario == Scenario.moving
            ? 'Lean toward/away about 10 cm, once per second. Keep the computer fixed.'
            : 'No probe tone. Repeat the same leaning motion; keep system volume unchanged.',
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
      if (mounted) setState(() => exportStatus = message);
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
          SegmentedButton<ProbeMode>(
            segments: const [
              ButtonSegment(
                value: ProbeMode.tone,
                label: Text('Tone movement'),
                icon: Icon(Icons.graphic_eq),
              ),
              ButtonSegment(
                value: ProbeMode.chirp,
                label: Text('Chirp ranging'),
                icon: Icon(Icons.radar),
              ),
            ],
            selected: {mode},
            onSelectionChanged: settingsLocked
                ? null
                : (s) => setState(() {
                    mode = s.single;
                    clearResults();
                  }),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<Scenario>(
            key: ValueKey(
              '$native-${validationPlan == null ? 'free' : validationTrials.length}-$slotRecorded',
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
                child: Text('Moving reflector'),
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
          if (!native)
            slider(
              'Fixture reflector range · ${range.toStringAsFixed(2)} m',
              range,
              0.3,
              1.0,
              14,
              (v) => setState(() {
                range = v;
                clearResults();
              }),
            ),
          if (!native)
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
              computerBackendAvailable()
                  ? 'Start requests microphone permission and plays a low-level sound. Use built-in speakers; keep system volume low. No upload. Thresholds are uncalibrated.'
                  : 'Native backend is not implemented. No silent fallback to simulation.',
              style: TextStyle(color: Color(0xffa25d18)),
            ),
          if (native && mode == ProbeMode.tone) ...calibrationControls(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('start'),
                  onPressed:
                      busy ||
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
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: busy
                ? runner.elapsed / duration
                : (runner.state == TrialState.complete ? 1 : 0),
          ),
          const SizedBox(height: 8),
          Text(
            '${runner.state.name.toUpperCase()} · ${busy ? (duration - runner.elapsed).clamp(0, duration).toStringAsFixed(1) : '0.0'} s remaining',
            key: const Key('trial-state'),
          ),
          if (runner.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                runner.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
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
                : !r.valid
                ? 'Unknown · analysis unavailable'
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
                    Text(
                      native
                          ? 'Press Start to request microphone access and play a low-level probe.'
                          : 'Choose a mode and press Start. No audio is emitted.',
                    ),
                  ],
                ),
              ),
            ),
          if (r != null && !r.valid)
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
              r.settings['calibrationProfile'] == null
                  ? 'Movement score · threshold ${r.threshold} · at least 2 frames'
                  : 'Received sideband/carrier ratio · trial 80th percentile threshold ${r.threshold.toStringAsPrecision(3)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TrialPlot(result: r, movement: true),
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
          OutlinedButton.icon(
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
