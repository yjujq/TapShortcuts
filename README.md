# TapShortcuts

Trackpad gestures run actions on macOS. Tap with three fingers and a shortcut
opens; hold one finger and tap to its right and the window closes. Lives in the
menu bar, with no window and no Dock icon.

Swift, AppKit and SwiftUI only, no third-party dependencies. Tested on a
MacBook Pro M3 Pro, macOS 26.

## Gestures

**39 gestures** are recognised, in eight families:

| Family | What it covers |
|---|---|
| Tap | 2, 3, 4, 5 fingers |
| Double tap | 2, 3, 4 fingers |
| Hold | 2, 3, 4 fingers for longer than 0.6 s |
| Tap beside a held finger | left and right, with one anchor or two |
| Swipe | 3, 4, 5 fingers in four directions |
| Pinch in and out | 2, 3, 4 fingers |
| Rotate | clockwise and anticlockwise |
| Corner tap | four corners, one finger |

Nine of them are **claimed by the system** — three- and four-finger swipes, the
two-finger tap, zoom and rotation. They can still be bound, but they will not
always fire: macOS takes some of those events before we see them. Such gestures
are marked with a warning symbol.

### Tap beside a held finger

A gesture of two contacts: one finger rests while another taps next to it. The
side is decided by comparing against the anchor finger's position.

It is separated from the system's secondary click, from ordinary scrolling and
from an ordinary click, by four required conditions:

- the anchor landed **at least 0.15 s** before the tap;
- the anchor is **still** — in scrolling both fingers travel, and without this
  check a travelling one passed for an anchor;
- there was **no noticeable motion** in the touch at all;
- the tap landed **beside the anchor** — far enough sideways to tell which side
  it fell on, and close enough in both axes to be next to it.

The last one was missing at first, and only a lower bound on the sideways
distance was checked. That made the gesture mean "tap anywhere, while another
finger rests anywhere" — which is precisely an ordinary click with a thumb on
the pad, and every other condition was already satisfied by one. Clicking sent
the frontmost application away roughly every second time. The vertical bound
does most of the separating: a resting thumb sits near the near edge while the
clicking finger is up in the middle, whereas two fingers side by side are at
much the same height.

The first threshold was raised to 0.25 s at one point and turned out to silence
the gesture entirely: the anchor usually rests longer than `tapDuration`, so an
inflated lead does not soften the trigger, it removes it. It now sits at a safe
minimum above the spread seen in ordinary scrolling.

## Actions

Each gesture can be bound to one of:

- **19 system actions** — Mission Control, App Exposé, Launchpad, Show Desktop,
  moving between spaces, lock screen, sleep display, playback and tracks,
  volume, brightness, screenshots, dark mode;
- **previous application** — directly, without the switcher;
- **a key combination** — a dozen common ones in the list;
- **opening an application** — any that is installed;
- **a shortcut** — any installed in the system.

Choosing goes through a chooser with search: click the bound action, type part
of a name, and the list narrows as you type.

Bound gestures are lifted into a section at the top while free ones stay in
their families, so there is no hunting for the bound ones among four dozen rows.
A filter above the list — all, bound, free — drops either half outright.

Settings themselves are a path rather than one scroll: the root lists General,
Excluded apps and Gestures, and the header prints where you are. Searching from
the root covers every page at once, including which gesture runs what.

### Shell commands and scripts

They are not in the list — they need a text field and the list is long enough
already. They are written by hand:

```bash
defaults write local.tapshortcuts bindings.v2 -dict-add tap4 "shell:open -a Terminal"
defaults write local.tapshortcuts bindings.v2 -dict-add tap5 "script:display notification \"hello\""
```

The prefixes `shell:` and `script:` are recognised.

## Exclusions

Applications where gestures do not fire are listed in settings. They are needed
where the trackpad is already spoken for: drawing tools and games interpret
multi-finger touches themselves, and interception gets in their way.

The frontmost application is asked of the system **at the moment of the
gesture** rather than tracked continuously: gestures are rare, and tracking
would mean subscribing to every window switch. With an empty list the check
returns immediately and never touches the system at all.

An application removed from the system stays in the list and is shown by its
bundle identifier instead of a name — so it remains visible and removable.
Disappearing quietly is not an option: that would look like settings changing
by themselves.

## Guards against accidental triggers

Four guards, all turned on by a single switch in settings.

**Palm rejection.** The framework reports the size of each contact, and a palm's
is several times larger than a fingertip's. Anything above the threshold is
discarded before any analysis: otherwise a hand resting on the trackpad would
count as fingers and turn every touch into a multi-finger gesture. Ghosts are
filtered out too — contacts too faint to be a real touch.

**Landing simultaneity.** The fingers of a real tap land almost together. A hand
settling piecemeal gives the same finger count but stretched in time; the
threshold is 0.12 s between the first and the last.

**Silence while typing.** While typing, hands brush the trackpad constantly and
almost every contact is accidental. Gestures stay silent for 0.6 s after a key
press.

The time since the last key press is asked of the system through
`CGEventSource.secondsSinceLastEventType`. That is a public facility and needs
no special permission — unlike watching the keyboard, which would require Input
Monitoring.

**Silence while a button is held.** A held button means dragging or selecting,
where multi-finger contacts have nothing to do with gestures.

Taps beside a held finger are exempt from the last guard: the tap physically
coincides with the system's tap-to-click, and the OS generates its own click for
the same contact. `pressedMouseButtons` becomes true for an instant not because
of dragging but as a side effect of the tap itself, and the guard was
suppressing a third of the real gestures.

## How it works

A few places where the obvious solution does not.

**macOS offers no public path to trackpad touches.** `NSEvent` hands over
already-interpreted gestures and does not report the finger count of a tap at
all. So the private `MultitouchSupport` framework is used, bound through the
runtime, with its symbols checked at startup. It needs no special permission.

The usual caveat for private frameworks applies: the data layout is not
documented by Apple and may change in a future release. Gesture recognition
would then stop, but the app will not crash.

**Recognition runs on the trackpad thread, and settings must not be touched from
there.** The app used to crash on any tap of two or more fingers, because
recognition asked the settings through `MainActor.assumeIsolated`. That is an
assertion that we are already on the main actor, not a hop onto it: the
assertion turned out false and the runtime tore the process down. The recogniser
now receives ready values — the set of bound gestures and the state of the
guards — rather than a way to ask for them; they are updated from the main
thread and read under a lock.

**The order of analysis matters.** Motion is checked before tapping, otherwise a
swipe would count as a tap. Pinch before rotation, rotation before hold.

**Initial values are taken not on the first frame** but 0.03 s in: at the very
start of a touch the coordinates jump about and the finger spread comes out
false.

**Drift is measured from the start**, not between frames: a finger's tremor
would accumulate and drown recognition.

**A double tap requires holding back the single one** — otherwise the first tap
fires before the second arrives. The delay is only applied when the double is
bound to something; otherwise the single fires at once.

**Modifiers are pressed for real.** A flag on the key alone is not enough: it
makes no difference for ⌘W, but the app switcher waits precisely for Command to
be released, or it stays on screen instead of completing the switch.

**Keys are read from the keyboard layout, not from a list.** They were once
listed by hand, and the list had no digits: both screenshot actions did nothing
at all, their only complaint going to a log that hides a non-system process's
text. A list is wrong in principle too. Applications match ⌘Q by the character,
so on AZERTY the Q sits where QWERTY has its A. The layout asked is the
ASCII-capable one the system itself falls back to for shortcuts — with a Russian
layout active, no key types a "w" at all.

**System shortcuts are the exception, sent by key code.** The system matches
them that way, and looked up by character they would break: on AZERTY the "4" is
found only on the keypad, which the screenshot shortcut ignores. Their codes and
modifiers are read from the user's own `com.apple.symbolichotkeys`, so a shortcut
moved in System Settings is followed, and one switched off there shows as off in
the action list rather than going nowhere without a word.

**Media keys travel as a special event** — subtype 8, with the key code and
state packed into the data field. The system does not accept ordinary key
presses for volume and brightness.

**Switching to the previous application does not use ⌘⇥.** The app remembers
what was frontmost before the current one and activates it directly — no row of
icons, no delay. It does not record itself in that history.

## Building

```bash
./build.sh --install
```

The bundle is staged in a temporary folder outside iCloud sync: the file
provider stamps files with attributes that `codesign` rejects.

The signature matters not for security but because macOS ties the login item and
granted permissions to it.

## Permissions

**Nothing is required** as long as only shortcuts, opening applications and
switching to the previous app are bound.

**Accessibility** is needed for key combinations and for the system actions that
work through them: the system only lets trusted applications post synthetic key
events. Without it a gesture is still recognised, but the key press goes
nowhere — silently, with no error.

A hint about this appears in settings on its own, but only once at least one key
combination is bound.

## Limits

Gestures the system claims are intercepted unreliably. Pressure is not
distinguished: the framework reports contact size, which is only indirectly
related to force.

The thresholds — times, drifts, angles — were chosen by reasoning and can be
adjusted in `Sources/Multitouch.swift`.
