"""Install only this project's dynamic profile/reservation; never start servers."""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent


def exclusive_json(path, value):
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def main():
    if os.getuid() != __import__('pwd').getpwnam('legion').pw_uid:
        raise RuntimeError("Install requires the actual legion identity")
    config = json.loads((ROOT / 'tool/dev_launch.json').read_text())
    profile = json.loads((ROOT / 'tool/Phonopticon-Local.iterm.json').read_text())
    target = Path('/Users/legion/Library/Application Support/iTerm2/DynamicProfiles/Phonopticon-Local.json')
    registry = Path(config['port_registry'])
    entry = {'project': 'phonopticon', 'mode': 'local', 'bind': '127.0.0.1', 'port': 8765, 'transport': 'tcp/http'}
    if target.is_symlink() or registry.is_symlink():
        raise RuntimeError('Refusing symlink configuration targets')
    if target.exists() and json.loads(target.read_text()) != profile:
        raise RuntimeError('Existing profile differs; inspect before replacing')
    if registry.exists():
        ports = json.loads(registry.read_text())
        if entry not in ports.get('allocations', []):
            raise RuntimeError('Existing shared registry requires a reviewed merge; not overwritten')
    else:
        ports = {'schema_version': 1, 'allocations': [entry]}
    # Validate all inputs before any installation writes. Existing parent permissions remain unchanged.
    state = Path(config['state_directory'])
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not registry.exists():
        exclusive_json(registry, ports)
    if not target.exists():
        exclusive_json(target, profile)
    print('Installed:', target)
    print('Reservation:', registry)
    print('Profile:', config['profile_name'])
    print('No servers started; choose this entry in iTerm Profiles.')


if __name__ == '__main__':
    os.umask(0o077)
    main()
