# Input Latency

## The split

Widget interactions fall into two categories:

**Client-local (no round-trip):**
- Sorting a table column
- Filtering/searching within a dataset the client already has
- Scrolling
- Selection highlighting (the visual feedback of "this row is selected")
- Tab switching (if tab content is already loaded)
- Expanding/collapsing tree nodes the client has data for
- Text input echo (show the keystroke immediately)

**Server round-trip (~200ms on typical SSH):**
- Navigating to a new view (clicking a directory in a file browser)
- Submitting a form or command
- Deleting/creating/mutating a resource
- Any action that changes app state

## Why the split exists

Over SSH, a round-trip is ~100-400ms. For text typing, the client applies keystrokes optimistically (show immediately, sync later). But for actions like "user clicked row 3," the client can't predict what the app will do — it might navigate, expand, filter, or do nothing. So those take a round-trip.

This is the same model the web uses. Clicking a link takes a round-trip. Sorting a table client-side is instant. Users are trained for this.

## v1 rule

The client owns sort, filter, scroll, and selection highlight. These never generate a message to the runtime.

Actions (navigate, submit, delete, toggle) send an `input` event and wait for a new `render` or `data` message. The client may optimistically highlight the selected row, but does not predict the app's response.

## v2 candidate: optimistic hints

Apps could declare in the render tree what happens on interaction:

```json
{
  "type": "list",
  "bind": "files",
  "on_select": { "optimistic": "highlight" },
  "on_action": { "navigate": { "optimistic": "loading" } }
}
```

The client applies the hint immediately and corrects when the server responds. This is how optimistic UI works in React/Apollo. Adds complexity to the render tree spec — defer until the round-trip latency is a proven pain point.
