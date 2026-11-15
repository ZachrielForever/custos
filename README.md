# Custos

Faceless macOS agent: after idle, silently seals ALL input
(keyboard, trackpad, mouse, external USB) behind an escalating verification
theater. Running processes are untouched — builds keep building, logs keep
rolling. Nothing visibly changes until input is attempted.

## Privacy blur

A cosmetic frosted-glass curtain rises before the seal. Timeline:
blur onset (X seconds of idle, default 3) + lock delay (Y seconds,
default 60) = total time until the lock engages. The curtain fades in,
passes input through untouched, and lifts instantly on any interaction —
no auth involved. Timers reset on every keystroke, click, or scroll,
same as if blur weren't there. Toggle it off and behavior is identical
to a plain idle seal. Uses native behind-window blur: no screen capture,
no Screen Recording permission.

## Escalation tiers

1. Opaque black curtain, stern prompt: "Touch to Unlock" + owner's phone
   is pinged (ntfy). The system biometric sheet draws beneath the
   curtain — hidden by design; the sensor needs no visible UI.
2. Desktop drops to a faux verification shell (sysadmin TTY aesthetic),
   real-time station data, second phone alert.
3. Silent red alarm: "forensic record synced, endpoints notified" —
   all true statements; every tier fires a real push notification.
4. The void: black screen, blinking underscore. Unlocks only on the
   Custos secret (salted SHA-512), NOT the macOS password — a leaked
   system password gains nothing here, and this secret grants nothing
   else.

Tier 4 owner ritual: `ESC` (clear hidden buffer), type secret, `Return`.
No feedback is displayed by design — the ritual is constant, so buffer
state is never a guess: always clear first.

Touch ID is asked a maximum of 3 times, ever — hardcoded, not
configurable. The Secure Enclave's ~5-failure biometric lockout is
unreachable by design. Prompts have no timeout: the curtain and the
sensor persist until touched or unlocked.

## Permissions

Custos needs **Input Monitoring** (System Settings → Privacy & Security)
to seal input. Grant it to `/usr/local/bin/custos` after install —
System Settings hides system paths; use Cmd+Shift+G in the file picker
to type it.

Sign the binary with a stable identity (`scripts/make-identity.sh`,
once per machine, then trust the cert in Keychain Access → Trust →
Code Signing → Always Trust). Signed binaries keep their permission
grant across every rebuild; unsigned binaries lose it on each rebuild
and must be re-granted.

## Setup

Simplest path: `scripts/install.sh` seeds the default config, registers
the launchd agent, and opens the setup window if no secret is configured.
Or invoke any time: `custos setup` — first run is open; every later run
requires Touch ID. Reconfiguration is owner-only.

The unlock secret is set exactly once, in the setup window. Afterwards
the window can never touch it — rotation is a deliberate terminal
ritual: `custos secret` (Touch ID gated, typed with echo disabled).
Setup enforces sane values on save: lock delay is a whole number of at
least 5 seconds, number fields accept digits only, and a blank or
mismatched secret refuses to save.

CLI extras: `custos test` fires a notification to verify your phone side.

## Notifications

Optional. Toggle notifications on in the setup window and enter your
ntfy topic: `https://ntfy.sh/<long-random-string>`. Subscribe to that
topic on your phone. Topic names are effectively passwords — use
`openssl rand -hex 16`. Every tier fires a real push; multiple endpoints
keep "endpoints notified" literally true.

## Logging

JSONL at `~/.config/custos/attempts.log`: every seal, blur, attempt,
escalation, position snapshot (if enabled), and unlock — one structured
record per event, jq-queryable. No biometric data exists outside the
Secure Enclave; the OS never sees fingerprints. No imagery is ever
captured.

## Escape hatch

Force shutdown (hold power) → reboot → macOS login wall. Same cost as
any tampering; unsaved work is the only casualty.

## Layout

`Sources/` — engine, overlay skins, logger, notifier, locator
`deploy/` — launchd agent plist
`scripts/` — build, install, signing identity
