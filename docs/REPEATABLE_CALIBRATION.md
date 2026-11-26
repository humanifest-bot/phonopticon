# Repeatable small-motion calibration

This is a proposed Mac feasibility experiment for the current experimental
Breathing mode. It asks whether a rigid reflector moving with a known rhythm
can be distinguished from matched controls. It does not measure breathing or
establish medical performance. The 3–10 kHz chirp and this analysis differ
from the original ApneaApp research. No results are claimed by this protocol.

## Freeze the setup before evaluation

Use pilot recordings only to choose a setup. Record the app source revision,
browser and version, Mac and OS, room, device positions, reflector size and
material, audio input and output routes, system volume, and ambient sounds.
Anchor the Mac and fix a rigid, approximately A4-sized board on a low-friction
guide. Measure and record the distance from the Mac's speaker/microphone area
to the board, including the reference points and measurement uncertainty. The
default echo-window center is 0.60 m; it is an analysis setting, not a
calibrated distance reading. Keep people and other moving objects away from
the acoustic path, and keep the support and desk still.

Start with the guided preset: Computer mic + speaker; Breathing; 30 seconds;
3–10 kHz chirp; digital peak amplitude 0.020; echo-window center 0.60 m;
target rhythm 0.25 Hz. System volume is separate from digital amplitude; set
it low and record its setting. Do not assume the band is inaudible or that
the recorded input is unprocessed. Use the same browser, routes, volume,
geometry and settings throughout. Browser-reported input settings are not
proof of the physical output route or processing. Verify what you can and
record unknowns; the current route-signature comparison can treat missing
metadata as matching.

Place two marks 5–10 mm apart along the board's travel. Use the same guide,
hand placement and silent four-second pacer for all motion and off-motion
trials. Avoid touching the Mac or scraping/tapping the guide. Make a short
microphone check and note ambient noise; it is not an evaluation trial.

## Independent reference

Before evaluation, arrange a separate local video camera so that a ruler and
the board's moving edge remain visible, without disturbing the Mac or board.
Record video locally only, with informed consent of anyone visible. Record
frame rate, ruler scale and expected measurement uncertainty. Mark a visible
start event in the video and note the trial ID and approximate app start time;
the synchronization uncertainty must be reported. Do not use the app's echo
trace or on-screen pacer as the measurement of actual displacement. Extract
board position versus video time, or record the method and its limitations;
marks alone establish intended endpoints, not a continuous trajectory.
Inspect whether the measured peak-to-peak travel is 5–10 mm and the observed
rhythm is near 0.25 Hz. Record any deviations, occlusion, missed frames or
inadequate resolution. If no usable independent reference exists, retain the
trial and label its timing and displacement unverified; do not claim measured
sensitivity. A calibrated displacement sensor or motorized stage could
replace the camera if its data and synchronization are recorded independently.

## Frozen rule and held-out trials

Before collecting held-out trials, record the exact source revision,
configuration, analysis version, setup and trial order. Do not alter the
algorithm, range window, criteria or excluded-trial rules after inspecting
held-out results. If a change is needed, label those recordings development
data, document the change, and collect a fresh held-out set.

The current three-recording comparison requires an on/stationary, on/moving,
and off/moving capture in that order. It applies these existing criteria:

* Stationary analysis must be valid and must not simultaneously have a
  periodic fraction of at least 0.25, a peak within 0.05 Hz of 0.25 Hz, and
  periodic RMS of at least 0.001.
* Moving analysis must be valid, its peak within 0.05 Hz of 0.25 Hz, its
  periodic fraction at least 0.25, and its periodic RMS at least the greater
  of 0.001 and three times the paired stationary RMS.
* The off/moving capture must return the specific result `No coherent chirp
  probe found`. A different error is not an off-control pass.

These are algorithm criteria, including a threshold computed from each paired
stationary control, not independently established physical sensitivity. A
pass of one trio is not a validation study. The app also checks settings,
source labels, emitted waveform and duplicate PCM; a successful replay command
only means a report was written, so inspect its individual results.

Predeclare five fresh held-out blocks, each containing one of every condition:

| Condition | Transmitter | Board |
| --- | --- | --- |
| A | On | Stationary |
| B | On | Small, slow motion |
| C | Off | Stationary |
| D | Off | Same small motion as B |

Collect 20 physical recordings total, plus the separate pilot/microphone
check. Randomize each block's order before starting and record the seed and
actual order. The guided workflow defaults to A, B, D, but its trial selector
allows those three to be run in a different manually chosen order; it does not
generate or record a randomized schedule. It does not include C: collect C as
a separately configured/exported trial and document its place in the order.
Only describe a block as randomized if the predeclared order was actually
followed, including that separate C trial.
Use a distinct ID and save every raw local bundle, notes and independent
reference, including failures, interrupted attempts and retries. Retain the
first attempt as the primary result; list retries separately rather than
replacing an unfavorable result. Both off conditions should emit no chirp.

For each block, supply A, B, D in that order to the existing CLI (substitute
actual local paths and a new output filename):

```sh
dart --disable-dart-dev tool/verify_breathing.dart \
  /path/to/A-stationary.json /path/to/B-moving.json /path/to/D-off-moving.json \
  --out /path/to/new-block-report.json
```

The CLI refuses an existing output and does not accept C as a fourth input.
Review C separately as an additional ambient-noise control; do not present it
as having passed a comparison that the current CLI did not perform. Keep raw
recordings and references local by default; exports contain microphone audio.

## Record and interpret every outcome

For each block, report the three comparison flags, overall criteria, periodic
fraction/RMS/peak, analysis errors, route metadata, measured trajectory and
reference uncertainty. Report the number of passing blocks out of all five
attempted, along with missing or invalid results and the separate count of
unavailable off controls. Report control flags and moving failures by
condition; do not silently turn unknowns into true negatives. An off control
that fails the no-probe rule is a control failure, not automatically a proven
motion false positive. List C separately until a defined evaluator exists.

As a small exploratory target, predeclare at least four of five blocks meet
all three existing criteria, with all five paired stationary controls valid
and all five off/moving controls yielding the expected no-probe result. This
is a proposed block-level feasibility target, not
the broader detection/false-positive target in [PHYSICAL_TEST_PLAN.md](PHYSICAL_TEST_PLAN.md)
and not evidence of a low false-positive rate. Five blocks are too few to
establish reliable performance. If the setup, route, volume, algorithm or
reference changes, treat the next set as a new evaluation. Even an achieved
target would establish only performance on these measured reflector trials,
not breathing detection, range accuracy, another device, or medical use.
