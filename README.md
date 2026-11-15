# Custos

Faceless macOS agent: after idle, silently seals ALL input
(keyboard, trackpad, mouse, external USB) behind an escalating verification
theater. Running processes are untouched — builds keep building, logs keep
rolling. Nothing visibly changes until input is attempted.

## Privacy blur

A cosmetic frosted-glass curtain that rises before the seal. Timeline:
blur onset (X seconds of idle, default 3) + lock delay (Y seconds,
default 60) = total time until the lock engages. Blur fades in
animated, passes input through untouched, and lifts instantly on any
interaction — no auth involved. The timer resets on every keystroke,
click, or scroll, same as if blur weren't there. Toggle it off and the
behavior is identical to X = 0. Native behind-window blur means no
screen capture and no Screen Recording permission.

## Escalation tiers

Tier 1: dim overlay, Touch ID prompt.
Tier 2: faux biometric-verification terminal.
Tier 3: red alarm terminal, "final opportunity."
Tier 4 owner ritual: `ESC` (clear hidden buffer), type secret, `Return`.
No feedback is displayed by design — the ritual is constant, so buffer
state is never a guess: always clear first.

Touch ID is asked a maximum of 3 times, ever — hardcoded, not
configurable. The Secure Enclave's ~5-failure biometric lockout is
unreachable by design.

## Setup

Simplest path: the setup window auto-opens on first launch (incomplete
config detected). Or invoke any time: `custos setup` — after first run
this requires Touch ID, so reconfiguration is owner-only.

The unlock secret is set exactly once, in the setup window. Afterwards
the window can never touch it — rotation is a deliberate terminal
ritual: `custos secret` (Touch ID gated, typed with echo disabled).

Setup enforces sane configuration on save: lock delay is a whole number
of at least 5 seconds, number fields accept digits only, and a blank or
mismatched secret refuses to save on first run.

CLI extras: `custos test` fires a notification to verify your phone side.

## Notifications

Optional. Toggle notifications on, enter your ntfy topic:
`https://ntfy.sh/<long-random-string>`, subscribe on your phone.
Topic names are effectively passwords — use `openssl rand -hex 16`.
Every tier fires a real push; multiple endpoints keep "endpoints
notified" literally true.

## Logging

JSONL at `~/.config/custos/attempts.log`: every seal, blur, attempt,
escalation, position snapshot (if enabled), and unlock — one structured
record per event, jq-queryable. No biometric data exists outside the
Secure Enclave; the OS never sees fingerprints. No imagery is ever
captured.

## Escape hatch

Force shutdown (hold power) → reboot → macOS login wall. Same cost as any
tampering; unsaved work is the only casualty.

## Layout

`Sources/` — agent, overlay, setup, config, notifier, locator, logging
`deploy/` — launchd agent plist
`scripts/` — build + install
