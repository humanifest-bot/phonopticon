# Guided breathing trials

The computer microphone/speaker backend is experimental; simulated trials do
not measure the room. Nothing here diagnoses breathing or sleep apnea.

## Prepare and check the microphone

Use the computer backend in a supported browser. Place the computer and a
rigid reflector on stable supports about 60 cm apart; keep the room and system
volume unchanged across the set. Set a low speaker volume. Note the device,
route, volume, reflector position, ambient noise and any interruptions. A
digital amplitude of 0.02 does not guarantee a particular acoustic loudness.

The browser microphone meter is an explicitly started, foreground check: allow
microphone permission, speak and look for a changing level, then stop it. It
does not emit a probe or retain samples; it stops after 30 seconds or when the
page is hidden. A moving meter confirms input activity, not that the chirp is
audible, clean or suitable for detecting movement. A denied permission or a
silent meter needs attention before recording. Browser input-processing settings
are requests and may not be honored.

## Run the matched set

Start each recording yourself and keep the app in the foreground. The guided
configuration uses a 4-second transmitter-off microphone recording, followed
by three 30-second Breathing-mode recordings with an estimated 0.6 m range
gate, amplitude 0.02 and the audible-band setting:

1. **Microphone check:** speak while the transmitter is off; review the capture.
2. **Stationary:** hold the reflector and computer still.
3. **Small motion:** move the reflector smoothly by approximately 5–10 mm,
   two seconds each way, following the four-second rhythm.
4. **Transmitter off:** repeat the same motion without the chirp to check for
   ambient and handling-sound confounds.

Avoid touching the computer or desk, and keep people and other moving objects
out of the test area. Add notes about what actually happened, including any
noise, motion, changes of route or volume, and imperfect pacing. Retry a failed
or interrupted trial; preserve its record and explain the retry in the notes.
Stop is available during capture; an interrupted recording is not a completed
trial. Export individual bundles so raw audio and metadata can be inspected
independently.

## Save, resume and compare

The guided session keeps attempts and saved notes locally. Resume the latest
session or choose an older one from **Saved sessions**. Use **Review or retry a
trial** to return to a condition without starting audio; all attempts remain
in the session. Browser storage is specific to the browser
and site and can be cleared or unavailable. Check the save status and export a
copy of the complete session for safekeeping; local storage is not a backup. An exported recording
contains microphone audio, so share it only deliberately.

Compare one completed stationary, motion and transmitter-off capture from the
same setup. The comparison shows the selected trial IDs and times and initially
selects the latest eligible attempts. Check the selections; choose a specific
attempt to reproduce the comparison. Cancelled and missing captures are not
eligible. Record why a retry or selection was made; choosing after inspecting
results can bias an evaluation. The fixed-criteria analyzer checks the recorded source,
condition, settings, input route, unique PCM and emitted waveform before
recomputing the results. It requires a quiet stationary control, rejection of
the absent chirp in the off control, and motion near 0.25 Hz (within 0.05 Hz)
with periodic fraction at least 0.25 and periodic RMS at least the larger of
0.001 or three times stationary RMS. A failed or unavailable comparison is not
a pass. Keep these criteria fixed while diagnosing; evaluate changes to the
analysis or thresholds with fresh trials.

The recording-quality panel reports input RMS, exact-zero and clipped samples,
probe alignment where available, sampled energy in the nominal probe band, and
high-RMS 100 ms windows. Band energy with the probe on includes the probe; the
transmitter-off recording helps characterize ambient and handling sounds. A
flagged window does not identify the sound's cause. The trial-trace chart uses
elapsed time from each separate recording and labels its selected gate and I/Q
component; the traces are not synchronized and may represent different
components. A transmitter-off echo trace can legitimately be unavailable.

One matched set is calibration evidence, not a measured reliability or false
alarm rate. The operator's movement and timing are not independently measured;
room echoes, noise, audio processing and device movement can affect the trace.
The range gate is an estimate, not a calibrated distance. Repeat controlled,
independently measured trials before making sensitivity claims. Mobile native
audio capture/playback and iPhone hardware behavior remain unverified. See
[PHYSICAL_TEST_PLAN.md](PHYSICAL_TEST_PLAN.md) and
[LIMITATIONS.md](LIMITATIONS.md) for the wider evaluation and limitations.
For a proposed held-out repeated-trial procedure with independent timing and
displacement reference, see [REPEATABLE_CALIBRATION.md](REPEATABLE_CALIBRATION.md).
