# Inline Keyboard — feature and test checklist

**English** · [简体中文](TEST-PLAN.zh-CN.md)

Automated tests can only cover pure logic. Anything drawn on screen, any gesture, and
anything that depends on the real compositor has to be checked by hand. This document
splits the whole feature set into lines and marks what `node --test` covers versus what
must be verified manually.

```bash
node --test tests/          # 243 cases, pure logic only
```

---

## 1. Automated coverage (no manual check needed)

| File | Cases | What it guards |
|---|---:|---|
| `tests/actions.test.js` | 80 | Action-table sanitising and merging, drag reorder and drop-index math, quick-bar capacity and ejection, visibility filtering |
| `tests/data.test.js` | 53 | addon JSON parsing and fallback, input-method rows and globe cycling, candidate slicing, Esc↔\` swap |
| `tests/modifiers.test.js` | 40 | Four-mode modifier state machine, Caps, Fn / page, combo key sequence |
| `tests/resize.test.js` | 23 | Drag-to-resize, min/max bounds, symmetric and aspect-locked, persisted value clamping |
| `tests/special-keys.test.js` | 14 | Special-key label / short / icon forms |
| `tests/keyroute.test.js` | 13 | Whether a key goes to fcitx5 or ydotool |
| `tests/candidates.test.js` | 10 | Candidate row packing and width distribution (no truncation, flush right edge) |
| `tests/emoji.test.js` | 5 | Emoji group completeness, commit protocol (no newlines) |
| `tests/layout.test.js` | 5 | Layout structure, page-key targets, no overlapping keys |

Changing only these files? Running the unit tests is enough:

- `actions.js`, `data.js`, `keyroute.js`, `candidates.js`, `modifiers.js`
- `layouts/phone.js`, `layouts/emoji.js`, `layouts/resize.js`, `layouts/special-keys.js`

Changes to QML components, windows, gestures or the settings page require the manual checklist below.

### Semi-automated: acceptance script in 8 blocks

`scripts/acceptance.py` is split by feature area, so you can run just the block you touched:

```bash
python3 scripts/acceptance.py               # all 8 blocks (~1.5 min)
python3 scripts/acceptance.py keys          # keys only (~50 s)
python3 scripts/acceptance.py keys drag     # two blocks
python3 scripts/acceptance.py --list        # list blocks
```

| Block | Covers | Run it when you touch |
|---|---|---|
| `keys` | full walk of page1 (50 keys) and page2 (41 keys), Fn layer, Shift layer, page keys × 4 modes, modifier keys, dry run | key data, `keyroute.js`, `modifiers.js`, page keys |
| `cand` | candidate injection, bar/list split, expand/collapse, side keys, globe key | `CandidateBar` / `CandidatePanel` / `candidates.js` / fcitx bridge |
| `pages` | emoji page in/out, symbol segment, category chips | `EmojiPanel` / `EmojiCategoryBar` / `layouts/emoji.js` |
| `act` | action slot, nav, tiles, transparency panel, minimise, close/reopen | `QuickBar` / `ActionList` / action table |
| `geo` | size, opacity, floating position (set → read back → restore) | `resize.js`, geometry |
| `drag` | tap, 800ms hold, drag outside the card, drag from the bar | `DragInitiator` / `DragGhost` / drop rules |
| `settings` | temporarily change settings (escSwap / dockFillWidth / specialKeyStyle / slotActionId / bgOpacity) → verify → restore | settings logic |
| `env` | settings persist across restart, restart smoke test | settings I/O, `plugin.json`, packaging |

Three rules:

- **Every block cleans up after itself** (restore settings, clear candidates, back to page1), so
  any combination and any order is safe
- **Every real key tap is preceded by a guard**: read back `now=on` to prove dry run is active →
  tap a normal key → tap a repeatable key and wait 0.9s to see the log still has exactly 2 entries
  → the addon `key sent` counter must not move → the keyboard must still be open. Any failure
  aborts before another key is touched. This is what stops "rapid taps eat the release → the
  repeat timer never stops → the input method gets flooded"
- It asserts **state, not pixels**, so the "looks and feels"
items in the checklist below still need a human.

### Simulated user flow: tap / long-press / drag

All three are **injected inside the plugin** — they call the very functions a real user
gesture would call. No system input, no pointer movement, no screen coordinates:

| Gesture | Entry point | What it goes through |
|---|---|---|
| Tap | `debugTap <target> <arg1> <arg2>` | The widget's own `tapAt()`; targets: key/expand/side/bottom/nav/action/bar/slot/emojiCat |
| Long-press | same, `hold` > 400 | Repeat after 400ms, hold-to-activate modifiers |
| Drag | `debugDrag <index> <x> <y>` + `debugDrop` | The card's real `endDrag()` commit path |

```bash
dms ipc call inlineKeyboard debugTap key layers 40      # tap the page key
dms ipc call inlineKeyboard debugTap key Ctrl 800       # hold Ctrl for 800ms
dms ipc call inlineKeyboard debugDrag 0 99999 99999     # drag outside the card
dms ipc call inlineKeyboard debugDrop
```

Labels use the raw layout text (`Enter` / `F1` / `A` / `↑` / `layers`; letters are
uppercase). Use large positive coordinates for "outside the card" — negative values are
parsed as CLI flags.

### Dry run: check what would be sent, without sending it

After `debugSetDryRun true` a key press is no longer injected — it only records what
*would* have happened:

```bash
dms ipc call inlineKeyboard debugSetDryRun true
dms ipc call inlineKeyboard debugTap key Enter 40
dms ipc call inlineKeyboard debugInjected
#   INJECTED[1]:Enter/key/ydotool/28/m0
dms ipc call inlineKeyboard debugSetDryRun false
```

Each entry is `label/kind/route/code/mods`. `acceptance.py` uses this to verify which
route Enter, Backspace, digits and letters take, and compares addon log line counts
before/after to prove nothing was actually sent. Bool arguments must be `true` / `false` —
passing `on` fails to parse.

### Geometry and opacity: read / write

```bash
dms ipc call inlineKeyboard debugGeometry
#   GEO:x=538 y=42 w=840 h=443 bg=73 key=100 float=0 dockFill=0 saved=840x457 screen=1920x1080 pos=-

dms ipc call inlineKeyboard debugSetSize 900 400       # → SIZE:900x400 (clamped, persisted)
dms ipc call inlineKeyboard debugSetOpacity 88 92      # → OPACITY:88/92 (bg / key, 0–100)
dms ipc call inlineKeyboard debugSetPosition 200 300   # floating mode only → POS:200,300
```

- `w/h` is the card's **actual** size; `saved` is the **persisted** nominal size (they differ by
  the top inset — 14px measured)
- `pos` only exists in floating mode; docked reports `-`
- All three writes go through the same persistence path as the UI, so they survive a restart
- The acceptance script always does set → read back → restore, so it never changes your settings

### Why there is no QML automation

`qs.Common` / `qs.DCommon.Widgets` are compiled into the qrc of `/usr/bin/dms`, so no
standalone process can load them; `qmltestrunner` also fails silently on this machine.
Logic that has to be tested therefore gets extracted into pure modules
(`keyroute.js`, `candidates.js`); everything else is manual.

---

## 2. Manual acceptance checklist

Rule: touch a line, walk its block; before a release, walk everything.

### A. Window and form factor

- [ ] `dms ipc call inlineKeyboard toggle` opens and closes; the bar icon follows
- [ ] Docked mode sits on the bottom edge and pushes other windows up (never covering them)
- [ ] Docked mode: dragging the bottom handle moves the keyboard, release keeps it there
- [ ] Floating mode: draggable anywhere (including above the bar); position survives a restart
- [ ] Minimise to a single bubble; tapping it restores the previous form factor
- [ ] Close and reopen: page / mode / size / position all restored
- [ ] The keyboard window never takes focus; injected keys land in the app
- [ ] Voice mode (with fcitx5-vinput): voice row appears, recognised text goes into preedit

### B. Typing and keys

- [ ] Pinyin input: preedit shown, space commits the candidate
- [ ] Still types with the socket down / addon missing (falls back to ydotool)
- [ ] Digits (main row and numpad) type digits, not candidate selections
- [ ] Symbols become full-width / CJK punctuation in Chinese mode
- [ ] Shift: single tap is one-shot; double tap locks
- [ ] Caps Lock locks and unlocks
- [ ] Fn layer: 1–0 become F1–F10, `-` `=` become F11 / F12
- [ ] With `escSwap` on, the top-left key becomes Esc and the Fn layer still types \` and ~
- [ ] Long-press Backspace repeats; long-press character keys repeat
- [ ] Page 2: arrows / Home / End / PgUp / PgDn / Del / Ins all work
- [ ] Enter with **no preedit** submits a real key (newline in editors)
- [ ] Enter **with preedit** commits the highlighted candidate
- [ ] Backspace: deletes app text with no preedit, deletes the pinyin string with preedit
- [ ] Ctrl+C / Ctrl+V / Alt+Tab work on the first press
- [ ] Globe key: tap cycles input methods, long-press opens the picker
- [ ] Page key: tap enters page 2, tap again returns; all four `modifierMode` settings behave as documented

### C. Candidates

- [ ] Top bar clips to available width; the first item is capped at 2/3
- [ ] Long candidates render in full — not squeezed into an ellipsis
- [ ] The expand button opens the candidate list page; the back key returns
- [ ] List page: candidates packed into rows, separators centred in the gap, none at row end
- [ ] The four side buttons page up / down, backspace, enter
- [ ] Tapping a candidate commits the right word (original index, not display order)
- [ ] The list page collapses by itself when the preedit disappears
- [ ] Empty state shows "Loading…" / "No candidates"

### D. Emoji and symbols

- [ ] Emoji key opens the emoji page; the X in the corner returns
- [ ] Category strip switches groups and highlights the active one
- [ ] Emoji / symbol segment switch works
- [ ] Tapping an emoji commits it (addon when available, clipboard otherwise)
- [ ] Backspace works on the emoji page

### E. Actions

- [ ] Quick-bar actions fire (close / float / avoid / minimise / opacity / size / clipboard / undo / redo / next IM / settings / mic)
- [ ] Action state colouring is correct: active when floating, disabled for avoid while floating
- [ ] Action grid tiles fire
- [ ] Edit mode: reorder inside the grid, order is persisted on release
- [ ] Reorder inside the quick bar; the ejected action returns to the action table
- [ ] Drag from bar / grid onto the right-hand slot: the two swap, the old slot action takes the vacated cell
- [ ] Drop outside the keyboard: order unchanged, ghost returns to its cell
- [ ] Adding / editing / deleting a custom action in settings shows up immediately

### F. Panels and settings

- [ ] Opacity panel: live preview, cancel restores, confirm persists
- [ ] Resize: all four handles work; docked left/right moves symmetrically; floating moves only the dragged edge
- [ ] Resize: corners keep aspect ratio; bounds apply; reset returns to nominal; fill toggle works
- [ ] Every settings change takes effect without reopening the keyboard
- [ ] `modifierMode`: hold-to-activate / tap-to-activate / tap-to-lock / double-tap-to-lock
- [ ] `specialKeyStyle` / `winKeyStyle` / custom icon switch immediately

### G. Diagnostics

- [ ] `dms ipc call inlineKeyboard diag` reports socket / im / cand / preedit / ydotoold / mods
- [ ] `debug*` IPC works in dev mode and returns `dev mode off` otherwise
- [ ] No `ERROR qml` / `TypeError` / `Binding loop` from this plugin in `journalctl --user -u dms`

---

## 3. Regression hot spots

These three have all produced **silent failures** (no error, just nothing happens).
Walk the matching block whenever you touch neighbouring code:

1. **Key routing** (`keyroute.js` + `KeyRouter.qml`) → block B: enter, backspace, digits, combos
2. **Candidate widths** (`candidates.js` + `CandidatePanel.qml`) → block C: long words, right edge
3. **Drop indices** (`actions.js` + `QuickBar.qml` / `ActionList.qml`) → block E: reorder and slot swap

## 4. Verification log

One line per release.

- **0.1.5** — Enter / Backspace / F1 / arrows now injected as real keys (`key sent` stays flat in the addon log); candidate rows distribute spare width instead of averaging (`fits=ok`, no truncation); page key moved onto the modifier state machine; candidate panel switched to `DListView`; quick-bar ghost `targetX` binding loop removed
