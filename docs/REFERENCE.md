# Technical Reference

## Proven Systems to Study

### VS Code Remote

The closest existing model to what we're building.

**Architecture**: Local Electron renderer holds a full copy of the text buffer (Piece Tree). Remote runs a Node.js server with language servers, file watchers, PTYs. Communication over SSH → WebSocket with a custom binary protocol.

**Key pieces:**
- **Piece Tree text buffer** — Red-black tree where nodes reference 64KB chunks of the original file (readonly) + an append-only edit buffer. All ops O(log N). Memory ~= file size.
  - Source: `src/vs/editor/common/model/pieceTreeTextBuffer/` in [microsoft/vscode](https://github.com/microsoft/vscode)
  - Blog: https://code.visualstudio.com/blogs/2018/03/23/text-buffer-reimplementation
- **Binary protocol** — 13-byte header (type + ID + ACK + length) + JSON payload over WebSocket. Has ACK-based reliability, keepalive (5s), message replay on reconnect.
  - Source: `src/vs/base/parts/ipc/common/ipc.net.ts`
- **Incremental sync** — Edits sent as `{range: {start, end}, text, version}`. Identical to LSP's `TextDocumentContentChangeEvent`.
- **Split syntax highlighting** — TextMate grammars run locally (instant), semantic tokens from remote language servers (slight delay, applied as overlay).
- **Session persistence** — None. VS Code Server times out after the client disconnects. We need to do better (see Zed/tmux model).

### Zed

The best reference for high-performance remote editing with collaboration.

**Architecture**: Native Rust client with GPU-rendered UI. Remote server is a static `musl` binary (no dynamic deps, works everywhere). Protocol is protobuf over SSH stdin/stdout. Server runs as persistent daemon — survives disconnects.

**Key pieces:**
- **SumTree** — B+ tree where every node stores a `TextSummary` (len, lines, longest_row, etc.). Enables O(log N) seeks by any dimension (offset, line number, UTF-16 position) plus aggregate queries in the same traversal. Used everywhere in Zed, not just text.
  - Source: `crates/sum_tree/` in [zed-industries/zed](https://github.com/zed-industries/zed)
  - Blog: https://zed.dev/blog/zed-decoded-rope-sumtree
- **CRDTs for collaboration** — Every insertion gets a unique `(replica_id, seq)` ID. Positions are anchors: `(insertion_id, offset)`, not absolute positions. Deletions are tombstones (hidden, not removed). Deletes carry a version vector to exclude concurrent inserts.
  - Blog: https://zed.dev/blog/crdts
- **Protobuf protocol** — Defined in `crates/proto/proto/zed.proto` and `buffer.proto`.
- **SSH remoting** — Uses SSH ControlMaster for persistent connections. Auto-downloads server binary. Server runs as daemon, persists across reconnects.
  - Blog: https://zed.dev/blog/remote-development

### LSP (Language Server Protocol)

Our edit sync protocol should follow LSP's incremental text sync exactly.

- `TextDocumentSyncKind.Incremental` — full content on open, then `{range, text}` deltas
- `version` field on every change — monotonic, incremented per edit
- Position encoding: `{line, character}` (zero-based)
- Spec: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_synchronization

## Data Structures

### Piece Table / Piece Tree (use this)

What VS Code uses. Best fit for Pond v1 — simpler than CRDTs, proven at scale.

```
Buffers: [original_64kb_chunks..., append_only_edit_buffer]
Tree:    B-tree of Pieces, each referencing a range in a buffer
Ops:     insert/delete = split pieces, add to tree. O(log N)
Memory:  ~1x file size
```

Good for: single-user editing, local-first optimistic rendering, version-based conflict detection.

### CRDTs (v2, for collaboration)

What Zed uses. Needed only if we add multi-user editing.

- **RGA (Replicated Growable Array)** — per-element IDs sorted by Lamport timestamp. Simple but memory-heavy (tombstones).
- **Yjs Y.Text** — compound items (run-length), state-based deletes, compact sync via state vectors. Most mature JS CRDT. https://github.com/yjs/yjs
- **Automerge** — RGA-based, full operation log, higher memory than Yjs. Used by Zed historically.

Don't use these for v1. The version-tagged op approach (LSP model) handles single-user remote editing correctly with far less complexity.

### Diff Algorithms

- **Myers diff** — O(ND) where D = edit distance. Used by Git, VS Code. Fast for similar files. The standard choice.
- **Patience diff** — Myers + unique-line anchoring. Better diffs for code. `git diff --patience`.
- For our sync protocol: we don't diff. We send ops (insert/delete ranges). Diffing is only needed for conflict display.

### Delta Encoding

- **Rsync algorithm** — rolling checksum + block matching. Relevant if we ever do file-level sync without op history.
- **Fossil delta** — compact literal/copy instructions. Good reference for binary delta formats.
- **VCDIFF (RFC 3284)** — standardized binary delta. Overkill for us but good to know about.

## Key Design Decisions

### Optimistic Local Rendering (non-negotiable)

Both VS Code and Zed do this:
1. Apply edit to local buffer immediately → render (5ms)
2. Send op to server async
3. Server accepts (version matches) or rejects (stale version, sends current state)

This means typing feels local even on a 200ms-latency SSH connection. Without this, Pond is unusable for remote editing.

### Version-Based Conflict Detection (simple, correct)

Every file state has a monotonic version number. Every edit references its base version. Server only accepts if base version is current. On mismatch: server sends current state, renderer shows conflict.

This is sufficient for single-user editing. CRDTs only needed for multi-user collaboration.

### Protocol Framing

```
[4 bytes: payload length (big-endian u32)]
[1 byte:  encoding (0x00=JSON, 0x01=msgpack reserved)]
[N bytes: payload]
```

JSON for v1. The encoding byte lets us add binary later. Sequence numbers + ACKs + keepalive for reliability (steal from VS Code's `ipc.net.ts`).

### Renderer: Tauri + WebView

- System webview (~15MB) not Electron (~150MB)
- xterm.js for legacy PTY panes
- CodeMirror 6 or Monaco for structured editor panes
- TextMate grammar highlighting runs locally (instant)
- Semantic tokens from remote LSP as overlay

### Agent: Persistent Daemon

Run as a daemon on the server (like tmux). Survives SSH drops. Auto-reconnect from client. On reconnect: agent sends full current state, renderer redraws. Keep last N lines of scrollback per pane.

## Other References

- **mosh** — Mobile Shell. Does optimistic local echo over SSH. The original proof that local-first terminal rendering works. Uses SSH for initial connection, then its own UDP protocol. https://mosh.org
- **Textual** — Python TUI framework. Good DX reference for declarative terminal UI. https://github.com/Textualize/textual
- **xterm.js** — Terminal emulator component for the web. Battle-tested (VS Code uses it). Handles VT100/xterm escape sequences, Unicode, true color. https://github.com/xtermjs/xterm.js
- **Tree-sitter** — Incremental parsing for syntax highlighting. Runs locally in the renderer via WASM. https://tree-sitter.github.io
