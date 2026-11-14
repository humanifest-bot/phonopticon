import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/experiment.dart';

class TrialGuide extends StatelessWidget {
  const TrialGuide({
    super.key,
    required this.mode,
    required this.scenario,
    required this.physical,
    required this.validatingTone,
    required this.recording,
    required this.elapsed,
  });

  final ProbeMode mode;
  final Scenario scenario;
  final bool physical, validatingTone, recording;
  final double elapsed;

  @override
  Widget build(BuildContext context) {
    final breathing = mode == ProbeMode.breathing;
    final (title, icon, accent) = switch (scenario) {
      Scenario.stationary => (
        'Hold still',
        Icons.pause_circle_outline,
        const Color(0xff235988),
      ),
      Scenario.moving => (
        'Move the reflector',
        Icons.swap_horiz,
        const Color(0xff624498),
      ),
      Scenario.transmitterOff => (
        'Transmitter off',
        Icons.volume_off_outlined,
        const Color(0xff465d6b),
      ),
      Scenario.silence => (
        'Silence fixture',
        Icons.volume_off_outlined,
        const Color(0xff465d6b),
      ),
      Scenario.invalid => (
        'Invalid audio fixture',
        Icons.warning_amber_rounded,
        const Color(0xff8b4e20),
      ),
    };
    final instruction = physical
        ? switch (scenario) {
            Scenario.stationary =>
              validatingTone
                  ? 'Sit still and stay quiet for the full trial.'
                  : breathing
                  ? 'Set the Mac on a desk and prop a rigid book about 60 cm away. Keep both still.'
                  : 'Keep the Mac and a rigid reflector still for the full trial.',
            Scenario.moving =>
              validatingTone
                  ? 'Lean toward and away about 10 cm, once per second. Keep the Mac fixed.'
                  : breathing
                  ? 'Keep the Mac fixed. Move the reflector 5–10 mm between the marks, two seconds each way.'
                  : 'Keep the Mac fixed and move a rigid reflector.',
            Scenario.transmitterOff =>
              validatingTone
                  ? 'Repeat the same leaning motion. The microphone records with the probe off.'
                  : breathing
                  ? 'Repeat the same small motion. The microphone records with the chirp off.'
                  : 'The microphone records with the probe off. For a mic check, speak briefly during the trial.',
            _ => 'Choose a physical trial condition.',
          }
        : switch (scenario) {
            Scenario.stationary => 'The simulated reflector stays fixed.',
            Scenario.moving => 'The simulator moves the reflector.',
            Scenario.transmitterOff =>
              'The simulator generates ambient input with the probe off.',
            Scenario.silence => 'The simulator supplies silent audio.',
            Scenario.invalid =>
              'The simulator supplies invalid audio to exercise the error display.',
          };
    final paced =
        breathing &&
        (scenario == Scenario.moving || scenario == Scenario.transmitterOff);
    final phase = (elapsed * ExperimentConfig.calibrationRhythmHz) % 1;
    final away = phase < .5;
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(colors.surface, accent, .08),
        border: Border.all(color: accent.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scenario == Scenario.moving && validatingTone
                            ? 'Move toward and away'
                            : !physical && scenario == Scenario.moving
                            ? 'Simulated motion'
                            : !physical && scenario == Scenario.stationary
                            ? 'Stationary fixture'
                            : title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(instruction),
                    ],
                  ),
                ),
              ],
            ),
            if (paced) ...[
              const SizedBox(height: 12),
              Text(
                recording && physical
                    ? (away ? 'Move away →' : '← Move back')
                    : 'Pacer · one cycle every 4 seconds',
                style: TextStyle(color: accent, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                semanticsLabel: 'Reflector position, near to far',
                color: accent,
                minHeight: 6,
                value: recording ? .5 - .5 * math.cos(2 * math.pi * phase) : 0,
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Near'), Text('Far')],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
