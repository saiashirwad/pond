# Terminal Widget

The `terminal` widget renders legacy PTY programs (bash, vim, htop) inside Pond. It is the only widget that deals with character cells, escape-sequence-derived attributes, and cursor state. All of that complexity is contained here — no other widget type or protocol message is affected.

## When it appears

The `terminal` widget is never created by app developers. It is created by the runtime when a user launches a legacy program that speaks escape codes instead of the Pond protocol.

The runtime:
1. Allocates a PTY and spawns the legacy process
2. Feeds PTY output into a server-side VTE (headless terminal emulator)
3. Produces a render tree with a single `terminal` widget bound to a cell-grid stream
4. Sends cell diffs as the program produces output

## Client support is optional

The `terminal` widget is not part of the core widget set. A client that doesn't implement it can still render every native Pond app perfectly.

Clients advertise their capabilities on handshake. If a client doesn't support `terminal`, the fallback mechanism applies:

```json
{
  "type": "terminal",
  "bind": "pty-app-2",
  "fallback": {
    "type": "text",
    "content": "Legacy terminal app (requires terminal-capable client)"
  }
}
```

## What the stream carries

The bound stream for a `terminal` widget carries `TerminalState`:

```
TerminalState = {
  cells: [Cell],            // changed cells only (diff), or full grid on first frame / reconnect
  cursor: Cursor,
  title: string | null,     // window title, if changed
  mode: TerminalMode,       // current terminal mode flags
}
```

### Cell

```
Cell = {
  x: u32,                  // column (0-based)
  y: u32,                  // row (0-based)
  text: string,            // grapheme cluster — usually one character, but can be
                           // multiple codepoints for combining marks, emoji, etc.
  width: 1 | 2,            // display width in cells (2 for CJK wide characters)
  fg: Color | null,        // foreground color, null = terminal default
  bg: Color | null,        // background color, null = terminal default
  attrs: Attrs,
  url: string | null,      // hyperlink target (OSC 8), null if none
}
```

A wide character (width=2) occupies two cell positions. The cell at (x, y) carries the character; the cell at (x+1, y) is implicit and not sent.

### Color

Three representations, matching what terminal programs actually emit:

```
Color =
  | { kind: "indexed", value: u8 }           // 0-15: named, 16-231: 6x6x6 cube, 232-255: grayscale
  | { kind: "rgb", r: u8, g: u8, b: u8 }     // 24-bit true color
```

The VTE resolves named colors (SGR 30-37, 90-97) to indexed values 0-15. Clients map indexed colors to their theme's palette. RGB colors are passed through as-is.

### Attrs

A bitfield for text attributes:

```
Attrs = u16

Bit 0: bold
Bit 1: dim
Bit 2: italic
Bit 3: underline
Bit 4: blink
Bit 5: inverse
Bit 6: hidden
Bit 7: strikethrough
Bits 8-10: underline style (0=none, 1=single, 2=double, 3=curly, 4=dotted, 5=dashed)
Bits 11-15: reserved
```

A bitfield keeps the per-cell overhead low. At 120x40, a full screen is 4,800 cells. Diffs are typically 10-100 cells per update.

### Cursor

```
Cursor = {
  x: u32,
  y: u32,
  visible: bool,
  shape: "block" | "bar" | "underline",
}
```

### TerminalMode

Terminal mode flags that affect input behavior and rendering:

```
TerminalMode = {
  application_cursor: bool,     // arrow keys send application sequences
  application_keypad: bool,     // keypad sends application sequences
  mouse_tracking: bool,         // terminal is capturing mouse events
  bracketed_paste: bool,        // paste should be wrapped in escape brackets
  alternate_screen: bool,       // program is using the alternate screen buffer
}
```

The client needs these to correctly translate input events back to the byte sequences the program expects.

## Input

When a `terminal` widget has focus, the client sends structured input events. The runtime translates them into the byte sequences the PTY program expects (accounting for terminal mode state).

```json
{ "type": "input", "app_id": "app-2", "event": { "kind": "key", "key": "j", "modifiers": [] } }
```

The runtime knows whether the program is in application cursor mode and translates accordingly. The client doesn't need to know escape sequences.

For mouse events (when `mouse_tracking` is true):

```json
{ "type": "input", "app_id": "app-2", "event": { "kind": "mouse", "x": 10, "y": 5, "button": "left", "action": "press" } }
```

## Reconnection

On reconnect, the runtime sends a full `TerminalState` with every cell in the current screen buffer. This is a complete snapshot — the client draws the screen from scratch. No byte replay, no hoping the emulator lands in the same place.

Scrollback history (lines that have scrolled off the top) is included as a bounded buffer:

```
ReconnectState = {
  screen: TerminalState,        // full current screen
  scrollback: [string],         // last N lines of scrollback (plain text, attributes stripped)
  scrollback_total: u64,        // total lines that have existed (for "N lines above" indicator)
}
```

Scrollback is plain text, not cells. This is a deliberate simplification — scrollback doesn't need cursor state, mode flags, or pixel-level attribute fidelity. It's history, not a live screen.

## What this contains

All of the following complexity is inside this widget spec and nowhere else in the protocol:

- Character cell representation
- Color systems (indexed, RGB)
- Text attributes (bold, italic, underline variants, etc.)
- Wide character handling
- Combining characters and grapheme clusters
- Cursor shape and visibility
- Terminal mode flags
- Hyperlinks (OSC 8)
- Scrollback buffers
- PTY resize coordination
- Input-to-escape-sequence translation

Native Pond apps — using `text`, `table`, `list`, `input`, and other core widgets — never encounter any of this.

## Why this is separate

Pond is designed for native apps that emit structured render trees. Legacy PTY support is a compatibility bridge, not the foundation.

By containing the cell grid inside one optional widget type:
- The core protocol stays simple
- Client developers choose whether to support legacy programs
- The cell format can evolve independently of the rest of the protocol
- Native app developers are never exposed to terminal complexity
- A minimal Pond client works without implementing any of this
