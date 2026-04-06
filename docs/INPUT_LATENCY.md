# Input Latency

## Principle

Pond does not make every interaction optimistic. It makes common widget state local-first, while leaving application meaning authoritative on the runtime.

The client doesn't predict what the app will do. It owns what the widget itself should obviously do.

## Selection vs activation

A table row click is not one thing. It's two:

- **Selection** — "this row is highlighted." Widget-local state. The client does this immediately.
- **Activation** — "do the app's action for this row." Application-semantic state. This round-trips to the server.

These must be separate events in the protocol: `SelectionChanged` is not `Activated`. This single separation makes tables, lists, trees, and menus feel fast without a general optimistic-hints system.

## Three buckets

### Always local

The client owns these entirely. No message to the runtime.

- Hover, pressed, focus
- Caret and text selection
- Scroll position and viewport
- Selection highlight
- Dropdown open/close
- Tree expand/collapse when children are already materialized
- Sort/filter when the client holds the full relevant dataset

### Local-first, server-authoritative

The client applies immediate visual feedback, then reconciles against server state.

- Row/item selection model
- Checkbox toggle appearance
- Tree expansion that may require fetching more data
- Menu choice highlight before commit

A row click: (1) client immediately shows the row as selected, (2) client sends `select(item_id, render_version)`, (3) server either confirms, replaces the view, or ignores it.

### Round-trip by default

The client sends an event and waits for the server's response.

- Navigation (opening a new view)
- Lazy data fetch
- Opening detail panes
- Executing effects
- Mutations whose meaning depends on app logic
- Sort/filter when the client doesn't hold enough data locally

## Identity

Interactions should use stable item identity, not visible index. "Row 3" is brittle under streaming updates, sorting, and filtering. The client sends `item_id` + `render_version`, not a row number. This also feeds into reconnect and stale-operation detection.

## Tentative state

A widget can show three states:
- Current local selection
- Whether that selection is pending confirmation
- Last confirmed server state

This gives fast feel without pretending the client is the authority.

## v2 candidate: optimistic hints

Apps could declare in the render tree what happens on interaction. Defer until the round-trip latency is a proven pain point — the three-bucket model handles v1.
