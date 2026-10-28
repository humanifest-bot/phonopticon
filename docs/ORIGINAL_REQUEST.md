# Original request and approved direction

## Initial user request

The user requested research and a detailed conceptual build plan for the following specification. The quoted specification is retained with its original wording and punctuation so omissions can be reviewed independently of the build plan.

> Build a small, reproducible acoustic-sonar MVP starting from:
>
> https://github.com/joaocarvalhoopen/Partial_implementation_of_the_ApneaAPP_paper___FMCW_sonar
>
> Reference paper:
> https://apnea.cs.washington.edu/apneaapp.pdf
>
> Objective
> Demonstrate and measure detection of a moving reflector using an ordinary
> speaker and microphone. The eventual target is an unmodified iPhone, but
> first establish a working desktop baseline using the existing Python code.
>
> This is a feasibility experiment, not a medical device, a surveillance
> deployment, or evidence that any third party uses acoustic surveillance.
>
> Before implementation
>
> 1. Read applicable AGENTS.md instructions and inspect the repository,dependencies, source files, sample recordings, and license statements..
> 2. Verify reuse terms, including whether the MIT statement covers the filesbeing reused. Preserve attribution. Identify any unresolved restrictions..
> 3. Read the relevant methods in the paper. Distinguish the originalresearchers’ results from this independent partial implementation..
> 4. State the smallest implementation plan and observable acceptance criteria.Do not assume the existing code works or that near-ultrasonic frequencieswork on the available hardware..
>
> MVP scope
>
> • Reproduce analysis of the supplied recording, if usable..
> • Generate a configurable FMCW chirp and record speaker/microphone audioon a supported desktop..
> • Save raw recordings, emitted waveform parameters, sample rate, devicedetails, timestamps, and analysis settings for reproducibility..
> • Show an inspectable range-versus-time plot and a movement metric..
> • Label estimated distances and describe calibration limitations..
> • Provide a simple local interface or CLI using the existing stack..
> • Include explicit start/stop controls, a short recording-duration limit,and low default output amplitude. No automatic or background emission..
> • Keep recordings local by default..
> • Avoid medical classification, room reconstruction, multiple-phonesynchronization, cloud services, and machine learning in this MVP..
>
> Verification
>
> • Use a synthetic delayed echo with known delay to check the distancecalculation. Explain why synthetic success does not establish real-worldperformance..
> • Compare stationary-reflector and moving-reflector trials..
> • Include transmitter-off trials to test whether ambient sound aloneproduces apparent movement..
> • Where hardware access permits, repeat trials at measured distances andreport errors, false detections, and failures..
> • Separate supplied-recording reproduction, synthetic verification, andnewly collected physical results..
> • If microphone or speaker access is unavailable, complete the offlinedeliverable and provide an exact physical-test procedure. Do not claimphysical validation..
>
> iPhone path
> After the desktop baseline, assess what can be reused and what needs a
> native iOS implementation. Check current official Apple documentation for
> audio capture/playback, permissions, routing, sample rates, and processing
> controls. Do not assume the desktop implementation’s timing or frequency
> response transfers to an iPhone.
>
> If the available environment supports an iOS build, implement the smallest
> foreground capture/playback app and export recordings for the validated
> analysis pipeline. Otherwise deliver a concrete porting plan and clearly
> identify the unverified hardware assumptions.
>
> Deliverables
>
> • Minimal runnable implementation with preserved attribution..
> • Setup instructions and exact run commands..
> • Reproducible example output and experiment configuration..
> • Actual verification commands and results..
> • Short limitations report and the next measurable milestone toward iPhone..
>
> Do not send messages, publish, push, incur paid-service charges, or delete
> existing user material. Keep changes local and reviewable.

## Subsequent user decisions

The user questioned the value of a desktop app and proposed using the mobile simulated runner. The agreed direction replaces the desktop-first GUI with a shared mobile workflow and preserves offline/reference analysis. Desktop hardware capture is deferred; it is not silently counted as implemented.

The user accepted Flutter after discussion of a shared interface with native audio adapters. The user then authorized:

> let's build the Flutter MVP with tone movement and chirp ranging modes, starting with the simulated runner and keeping the native audio backend replaceable
>
> incorporate these considerations into the build plan then set it as a goal

This authorizes small reversible implementation edits and bounded inspected local verification under the supplied working agreements. It does not authorize installation, live model/network calls, hardware emission, remote writes, permission changes, deployment or editorial acceptance. The original prohibitions and evidence boundaries continue to apply.

## Remote Git authorization

The user subsequently instructed:

> commit and push regularly to https://github.com/humanifest-bot/phonopticon

This supersedes the earlier no-push restriction for coherent task milestones in this repository only. Other execution and disclosure boundaries remain in force.
