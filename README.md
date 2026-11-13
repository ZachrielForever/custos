# Custos

Faceless macOS agent: after N seconds of idle, silently seals ALL input
(keyboard, trackpad, mouse, external USB) until the owner's Touch ID.
The screen stays live and nothing visibly changes; the first input attempt
surfaces a biometric-only system prompt. No password fallback by design —
the keyboard is sealed while the prompt is up.

Built for Apple T2 Macs as a "walk away mid-build" tamper seal. Pair with
"Require password immediately" in Lock Screen settings for reboot coverage.

## Setup
1. `scripts/build.sh` then `scripts/install.sh`
2. System Settings → Privacy & Security → grant **Accessibility** and
   **Input Monitoring** to `/usr/local/bin/custos`
3. System Settings → Lock Screen → "Require password immediately"
4. Log out / log in (grants take effect on next launch)

## Configuration
`~/.config/custos/config.json` — hot-reloads, no restart needed.
- `idle_threshold_seconds`: 15 for strict, 60 default
- `active_start`/`active_end`: limit protection to a time window; leave
  null (recommended — always on, no vulnerable off-hours)

## Escape hatch
If Touch ID locks out (~5 failed attempts), the machine stays sealed.
Escape is force shutdown (hold power) → reboot → Touch ID/password login
wall. Unsaved work in sealed apps is lost; rely on autosave.

## Layout
- `Sources/` — Swift agent (event tap, idle poll, LocalAuthentication gate)
- `deploy/` — launchd agent plist
- `scripts/` — build and install