# iTerm quick start receipt

Created on 2026-10-30 for the current Phonopticon checkout. Effective user verified as legion on Darwin. The app requires one local static web-preview server; no API/database/worker/native-audio or Norway execution is configured.

## Installed entry

**Phonopticon — local — Legion Mac — all servers**

- Installed profile: `/Users/legion/Library/Application Support/iTerm2/DynamicProfiles/Phonopticon-Local.json`.
- Project-owned source profile, manifest and launcher: `tool/Phonopticon-Local.iterm.json`, `tool/dev_launch.json`, `tool/dev_session.zsh`, `tool/dev_server.py`.
- Python: existing `/opt/homebrew/bin/python3`; no dependencies installed.
- Server: foreground static HTTP for `build/web`, loopback `127.0.0.1:8765`.
- Reservation: `/Users/legion/Documents/Codex/dev-ports.json`.
- Lock/run metadata: `/Users/legion/Documents/Codex/phonopticon-dev`.
- Logs: directly in the pane, retained after process exit. No persistent terminal-input logging.
- Stop: Ctrl-C forwards to the launcher-owned child only; pane prints STOPPED and exit status. Restart `r`, status `s`, quit `q`. No automatic restart.

This is a single-process all-servers entry because the current app has only one server. Multiple service orchestration, Docker and remote modes are not needed or represented as working.

## Inspection and validation

Read the project README and development-session skill; inspected existing local Dynamic Profile attributes as a known-good reference and official iTerm Dynamic Profiles documentation. iTerm app metadata reports 3.7.6; supported attribute names were additionally checked in the installed app binary. No default profiles or OS automation permissions changed. The Dynamic Profile JSON and property-list round trip validate; installed content exactly matches the versioned template. A direct `plutil -lint` on JSON was not a useful validator on this host; JSON parsing and plist serialization round-trip were used instead.

Initial listener inspection found no listener on 8765. lsof warned about an unrelated unavailable SMB mount; it was not accessed. Actual exclusive socket binding/readiness checks subsequently verified availability. A process-list probe was unavailable within the tool environment; no broader process enumeration or iTerm GUI automation was required. The setup does not claim a verified click through the iTerm Profiles menu; Dynamic Profile installation and command behavior are verified.

Installation ran `python3 -B tool/install_iterm_profile.py` with scoped sandbox escalation for the authorized external configuration paths. New profile/registry files are mode 0600 and state directory 0700. Existing parent permissions and unrelated profiles are preserved. No server is started by the installer.

Reviewed test scripts for writes/subprocesses/network before execution. Effects are own disposable directories/children, loopback sockets and captured console output only. No downloads, Flutter rebuilds, credentials, audio, remote connections or migrations.

Checks actually run:

- `/bin/zsh -n tool/dev_session.zsh`: passed.
- JSON parsing of manifest/profile and installed-template equality: passed.
- `python3 -B tool/test_dev_server.py`: five tests passed, covering owned start/duplicate/stop with stale metadata, occupied-port preservation, missing dependency, identity mismatch, and symlink refusal. A test-pipe ResourceWarning in the first run was corrected; the rerun was clean.
- Actual profile-command smoke test on 8765: confirmed live HTTP health matches project/workspace/run identity, confirmed server process group belongs to the exact test wrapper, sent Ctrl-C to that wrapper, observed owned-child cleanup, STOPPED/exit=0 and retained restart prompt, then quit. No server left running.
- Actual wrapper failure test with an owned disposable listener occupying 8765: preserved listener, displayed PORT CONFLICT, STOPPED/exit=4 and restart prompt, then quit with exit 4. No listener left running after test cleanup.

The launcher rejects missing build assets and symlinks, verifies live HTTP identity rather than trusting stale PID files, uses an exclusive advisory lock against duplicate launch, and preserves unknown listeners. It does not silently select a new port or kill existing services. No iTerm session was automatically started for handoff: selecting the installed profile is the quick-start action.

Reference: https://iterm2.com/documentation-dynamic-profiles.html
