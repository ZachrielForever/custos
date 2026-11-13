# Custos

Faceless macOS agent: after N seconds of idle, silently seals ALL input
(keyboard, trackpad, mouse, external USB) behind an escalating verification
theater. Running processes are untouched — builds keep building, logs keep
rolling. Nothing visibly changes until input is attempted.

## Escalation tiers
1. Dimmed stern prompt: "Touch to Unlock" + owner's phone is pinged (ntfy).
2. Desktop drops to a faux verification shell (sysadmin TTY aesthetic),
   real-time station data, second phone alert.
3. Silent red alarm: "forensic record synced, endpoints notified" — all
   true statements; every tier fires a real push notification.
4. The void: black screen, blinking underscore. Unlocks only on the
   Custos secret (salted SHA-512), NOT the macOS password — a leaked
   system password gains nothing here, and this secret grants nothing else.

Tier 4 owner ritual: `ESC` (clear hidden buffer), type secret, `Return`.
No feedback is displayed by design — the ritual is constant, so buffer
state is never a guess: always clear first.

Touch ID is asked a maximum of `max_touchid_attempts` (default 3) times,
ever — the Secure Enclave's ~5-failure biometric lockout is unreachable
by design.

## Setup
1. `scripts/gen-secret.sh` — paste salt/hash into `~/.config/custos/config.json`
2. `scripts/build.sh` then `scripts/install.sh`
3. Privacy & Security: grant **Accessibility**, **Input Monitoring**, and
   (optionally) **Location** to `/usr/local/bin/custos`
4. Lock Screen settings: "Require password immediately" (reboot coverage)
5. Log out / log in

## Notifications
Set `notify_endpoints` to your ntfy topic(s): `https://ntfy.sh/<long-random-string>`.
Subscribe to that topic on your phone. Topic names are effectively
passwords — use `openssl rand -hex 16`. Every tier fires a real push;
multiple endpoints keep "endpoints notified" literally true.

## Logging
JSONL at `~/.config/custos/attempts.log`: every seal, attempt, escalation,
position snapshot (if enabled), and unlock — one structured record per
event, jq-queryable. No biometric data exists outside the Secure Enclave;
the OS never sees fingerprints. No imagery is ever captured.

## Escape hatch
Force shutdown (hold power) → reboot → macOS login wall. Same cost as any
tampering; unsaved work is the only casualty.

## Layout
- `Sources/` — engine, overlay skins, logger, notifier, locator
- `deploy/` — launchd agent plist
- `scripts/` — build, install, secret generation