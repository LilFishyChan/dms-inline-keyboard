# Keyboard layout and geometry (as implemented)

**English** · [简体中文](layout.zh-CN.md)

> The early v0.2 prototype spec (always-visible number row + separate number/symbol pages +
> three key heights) never made it into the implementation; that draft is obsolete. What follows
> describes what the code actually does.

## Regions (top to bottom)

1. **Quick bar** (`QuickBar.qml`) — navigation/confirm circle on the left, quick-action slots in
   the middle, one circular action slot on the right
2. **Candidate / quick strip** (`CandidateBar.qml`) — only takes up height while `showCandBar` is
   on; the candidate data is still demo data
3. **Main area** (one of three, constant height) — key area / action tiles / opacity panel
4. **Handle bar** (`BottomBar.qml`) — collapse on the left, drag handle in the middle (floating
   mode only), input-method switch on the right

Main area height = 5 key rows + 4 gaps. The function page is "4 scrolling rows + 1 edit row", so
the card never grows or shrinks when switching pages.

## Size derivation

Everything lives in `KeyboardMetrics.qml` (shared by the docked and floating windows — do not
write a second copy inside a window):

```text
cardW  = min(kbWidth, screenW - 24)
unit   = (cardW - 2*pad - (15-1)*gap) / 15          // 15 units per row
kbHeight = 2*pad + 0.78*keyH + gap
         + rows*keyH + (rows-1)*gap
         + 0.5*keyH                                  // quick strip 0.78 / handle 0.5 key height
keyH   = solved from the equation above (Math.max(28, …))
```

- Default nominal size `kbWidth = 1050`, `kbHeight = 444` (`baseKbWidth`/`baseKbHeight` in
  `InlineKeyboardDaemon.qml`), multiplied by the scale setting (50–100%).
- Key width is computed from units: `w*unit + (w-1)*gap` — that way the bottom row with only 8
  keys still lines up with the right edge of the 15-key rows above it.
- Never derive sizes from `card.width / card.height`: that is a window ← card ← window feedback
  loop, and the floating window shrinks by itself as soon as you drag it.

## Key map (`layouts/phone.js`)

`page1` is the main key area (number row with an Fn layer for Esc/F1–F12, three QWERTY rows, bottom
row Ctrl/Win/Alt/Space/Fn/menu/emoji/page-2). `page2` is the F-key block + navigation + numpad
(15 columns, with empty columns in between as separators). Keys spanning two rows use `rs: 2`
(numpad `+` and Enter); `k: "spacer"` is a placeholder only and draws no key face.


## Press feedback

`Ripple.qml` is a "stays down while held" ripple: `press(x, y)` expands from the touch point and
stays opaque for as long as the press lasts; `release()` fades it out (180 ms). A `MouseArea` must
wire up all three:

```qml
onPressed: mouse => r.press(mouse.x, mouse.y)
onReleased: r.release()
onCanceled: r.release()   // dragging off the key must clear it too
```

## The three UI states

- `mode: "keys"` — the key area
- `mode: "functions"` — action tile grid; `editing` switches to drag-to-reorder (list ↔ quick bar
  ↔ top-right slot)
- `mode: "transparency"` — two sliders, background and keys; confirm is top-left, cancel is
  top-right (restores the values from before the panel was opened)

`mode` controls *which panel the main area shows*; the key page is a separate axis
(`page: page1 / page2 / emoji`). The emoji page occupies `page: "emoji"` and swaps the main area
for `EmojiPanel`: the top row (`quickH`) becomes an `EmojiCategoryBar` instead of the quick bar,
the middle is a scrolling grid, and the last row is "back / emoji·symbols / backspace". Card height
is still computed from the 5 key rows, so switching to the emoji page never changes the keyboard's
height.

## Where opacity lives

Background and key opacity are stored by the plugin itself (`bgOpacity` / `keyOpacity`). They are
applied as: panel background × `bgOpacity`, and each key/tile × `keyOpacity`; disabled states are
multiplied by an extra 0.5. **These do not follow the DMS theme's alpha.**
