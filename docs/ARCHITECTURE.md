# Inline Keyboard architecture and feature list

**English** · [简体中文](ARCHITECTURE.zh-CN.md)

A touch-keyboard plugin (DMS plugin). The plugin draws the keyboard itself; all input-method
capability comes from fcitx5.

---

## 1. Talking to fcitx5

Live data goes over a **Unix socket** (private line protocol); low-frequency commands go through
`$XDG_RUNTIME_DIR/inlineKeyboard-*` files. **There is no polling at all**: the addon pushes both the panel
state and the input-method list.

### Channels

**Main channel: Unix socket (real time)**

`$XDG_RUNTIME_DIR/inline-keyboard.sock`. The addon is the server; QML connects with `Quickshell.Io/Socket`.

| Message | Direction | Contents |
|---|---|---|
| `key:<keysym>[:<mods>]` | QML → addon | Key pass-through, turned into a `VirtualKeyboardEvent` |
| `text:<utf8>` | QML → addon | Emoji / symbol commit: the addon calls `InputContext::commitString()` directly; multi-codepoint emoji can only go this way |
| `state:{json}` | addon → QML | Panel-state push (skipped when nothing changed) |
| `imlist:{json}` | addon → QML | Input-method list; pushed when the keyboard opens, and re-sent when a new client connects |

Latency: sending takes **0.0014 ms**; end to end (key → fcitx5 processes it → state back in QML)
**about 2.2 ms**, against **25 ms** for ydotool.

**Routing rules** (decided inside `injectKey`):

```
direct (socket): !fcitxImKeyboard and no Ctrl/Alt/Super combination
ydotool:         plain keyboard layout (keyboard-us), or any combination carrying modifiers
```

- Under a plain keyboard layout fcitx5's `inputMethodEngine()` returns null and virtual-keyboard
  events are dropped (measured: nothing reaches the screen)
- Combinations with modifiers have to be visible to the compositor (Alt+Tab, Mod+number); the
  socket cannot reach it

**Auxiliary channel: files (buffers / self-checks)**

| File | Direction | Written by | Read by | Contents |
|---|---|---|---|---|
| `inline-keyboard-active` | plugin → addon | daemon | addon | Whether the keyboard is open (file exists = open). Drives UI takeover/release |
| `inline-keyboard-status.json` | addon → test tools | addon | `probe.sh` | Panel-state snapshot (same payload as the push; kept for self-checks, QML no longer reads it) |
| `inline-keyboard-imlist.json` | addon → test tools | addon | `probe.sh` | Input-method list snapshot (QML gets it over the socket) |
| `inline-keyboard-allcand.json` | addon → plugin | addon | `FcitxBridge` | Full candidate array (fallback when the socket is not connected) |
| `inline-keyboard-expand` | plugin → addon | `FcitxBridge` | addon | Request the full candidate set (writes `1`; the addon deletes the file after reading) |
| `inline-keyboard-select` | plugin → addon | `FcitxBridge` | addon | Select candidate N (writes the index; the addon deletes the file after reading) |
| `inline-keyboard-physical-input` | addon → plugin | addon | daemon | Marker that a physical key was pressed (deleted after reading; used to collapse the keyboard) |

### Transport details

- **socket**: `SplitParser` splits on `\n`, one line per message; the addon writes non-blocking and
  drops the payload on `EAGAIN`, waiting for the next round
- **files** (only four low-frequency commands are left: expand / select / physical-input /
  keyboard-active): atomic write via `tmp` + `rename`; the addon polls, reads, then `unlink`s

**Two socket constraints:**

1. A `DataStream` without a `parser` set **never** emits `read` — not a single byte arrives even
   though the connection is up
2. `SplitParser` has already cut the line out; searching for `\n` again in the callback drops the
   entire message

### Non-file channels

| Purpose | Method |
|---|---|
| Key injection | **ydotool** (a real `/dev/uinput` device: goes through libinput → compositor → application, so compositor shortcuts work too) |
| Switching input method | **The addon's `im:<name>` command.** `fcitx5-remote -s` only affects the last-focused context and stops working the moment the keyboard window appears, so the addon calls `setCurrentInputMethod()` in-process instead |
| Chinese/English toggle | **rime's own D-Bus `SetAsciiMode`** (`busctl --user call org.fcitx.Fcitx5 /rime org.fcitx.Fcitx.Rime1 SetAsciiMode b …`). Sending Shift through ydotool does not work — with the keyboard window focused the key never reaches the input field |
| Input-method list | **The addon reads `InputMethodGroup::inputMethodList()` directly** (the D-Bus-side `FullInputMethodGroupInfo` was an early experiment and is no longer used) |

---

## 2. How it is built

### Three layers

```text
┌─ fcitx5 process ─────────────────────────────────────────────┐
│ inline-keyboard-status addon (C++ / UI type)                        │
│ · counts as a valid UI only while the keyboard is open       │
│   (UIType=OnScreenKeyboard)                                  │
│ · adaptive polling at 40ms / 200ms / 5s, dumps panel state   │
│ · fetches the full candidate list with BulkCandidateList     │
│ · watches physical key events, writes a marker file          │
└───────────────────┬──────────────────────────────────────────┘
                    │ 7 files (see the table above)
                    ▼
┌─ DMS plugin process ─────────────────────────────────────────┐
│ FcitxBridge.qml (240 lines)                                  │
│ · socket I/O, state parsing, candidates, IM list             │
│ · the only fcitx5 communication layer                        │
├──────────────────────────────────────────────────────────────┤
│ KeyRouter.qml (256 lines)                                    │
│ · modifier three-state machine                               │
│ · key routing: direct to fcitx5 vs ydotool                   │
├──────────────────────────────────────────────────────────────┤
│ InlineKeyboardDaemon.qml (846 lines)                               │
│ · window lifecycle / IPC / settings read-write               │
│ · aliases the properties of the two components above         │
├──────────────────────────────────────────────────────────────┤
│ data.js (213 lines, pure functions + 131 unit tests)         │
│ · JSON → internal keyboard model                             │
│ · parseStatus / buildImRows / nextImRow                      │
├──────────────────────────────────────────────────────────────┤
│ QML components                                               │
│ KeyboardCard / CandidateBar / QuickBar                       │
│ BottomBar / ImPicker / Key / Ripple …                        │
└──────────────────────────────────────────────────────────────┘
```

### Key design decisions

**Why an addon — candidates only exist in-process**

Candidates live only inside the fcitx5 process, in
`InputContext::inputPanel().candidateList()`. The whole D-Bus surface was checked: `Controller1`
only manages input methods, `/virtualkeyboard` only shows and hides, `/rime` only exposes schemas,
and `grep Candidate` over fcitx5's dbus module source comes up empty. It **has to be in-process**.

**Taking over and releasing the UI**

The addon declares `UIType=OnScreenKeyboard` + `UIPriority=50`. When the keyboard opens:

1. the plugin writes `inline-keyboard-active`
2. the addon polls it → `setInputMethodMode(OnScreenKeyboard)`
3. after a 50 ms delay it calls `updateAvailability()` → fcitx5 re-selects a UI → picks the addon
   (higher priority)
4. classicui gets `suspend()`ed and its candidate window steps aside

Closing reverses the sequence; `updateAvailability()` selects classicui again.

**Why keys do not go through the addon**

`KeyEvent` injection would work (`KeyState::Virtual` is not checked inside fcitx5), but keys would
then only circulate inside fcitx5 and compositor shortcuts (Alt+Tab, Mod+number) would not fire.
ydotool is a real device and behaves exactly like a physical keyboard.

**The window layer**

The surface is a layer-shell `PanelWindow` with `keyboardFocus: None`, so injected keys land on the
focused application and never on the keyboard itself. Docked mode sizes the window to the keyboard
plus the preedit reserve and sets `exclusiveZone`, so other windows are pushed up; floating mode opts
out (`exclusionMode: Ignore`) so it can be dragged over the bar.

