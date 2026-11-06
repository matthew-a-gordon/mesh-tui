# Research: termtastic architecture and reuse

Resolves issue #3 (map: #1). Researched 2026-11-05 by reading the source of
`acelot/termtastic` at commit `1288b416c3ea4a1047c3a8a1312a95f0de4836cc`
(master, 2026-11-04, release `v1.0.0-alpha7`), plus the GitHub API. Nothing was
built or run, and nothing is tested on hardware (untested on hardware, 2026-11-05).

## Answer in one paragraph

termtastic is a young (first preview release 2026-07, seven alphas between
2026-10-23 and 2026-11-04), effectively single-author, GPL-3.0, Tokio actor-style
Rust TUI. It already implements nearly every v1 feature (channel and direct chat,
node list, full device config, traceroute, telemetry, position as text) over TCP,
BLE and serial. It matches the conventions on 16 ANSI colours, keyboard-only use,
ratatui, offline-first and a small-screen floor (70x20, below our 80x24). It
conflicts on concurrency model (async Tokio vs std threads + mpsc on a 100 ms
tick), hotkey model (F-keys and plain letters, not Ctrl-chords), quit behaviour
(no confirmation) and testability (zero tests). Recommendation: do not fork; use
it as a reference and port selected pieces (see "Recommendation"). The final
fork-vs-port call belongs to the map; this is the input.

## Facts

### Project health

- GPL-3.0, Rust edition 2024, about 20k lines in `src/` (62 files). Same licence as
  our target, so copying code is licence-compatible (keep attribution).
- 206 commits, 205 by `acelot`, 1 by another person: one maintainer.
- 92 stars, 12 open issues. Last push 2026-11-04. Open bugs include "Crash on
  changing settings form with index out of bounds" (#68, 2026-11-05) and "Node
  config save stuck sometimes" (#67). The README warns "things may change
  completely without notice."
- Release CI (`.github/workflows/build.yml`) cross-builds `aarch64-unknown-linux-gnu`
  and `arm-unknown-linux-gnueabihf` among others, so a CM4 binary is plausible. We
  did not run it.
- README claims "vibecode-free" (hand-written) and "optimized for small screens
  (down to 70x20)".
- Zero tests: grep for `#[test]` / `#[cfg(test)]` in `src` returns 0 hits. About 110
  `unwrap()`/`expect(` occurrences; 0 `unsafe`.

### Crate structure

Single binary crate, no workspace (`Cargo.toml`). Modules (`src/main.rs`): `app`,
`log2state`, `meshtastic`, `repository`, `serde`, `service`, `state`, `types`, `ui`.

- `meshtastic/`: `connect.rs` (TCP/BLE/serial connect), `radio.rs` (pumps
  `FromRadio`), `service.rs` (commands in, events out), `types.rs`.
- `service/`: one actor per concern (Chat, Config, Connection, Nodes, Persistence,
  Settings, Telemetry, Traceroute, Ui) plus `forms.rs` (3144 lines, settings forms).
- `state/`: `State` (flat struct), `StateAction`, `Store` (1260 lines, the reducer).
- `repository/`: SQLite via rusqlite (bundled) with 3 migrations; tables for nodes,
  messages, positions, telemetry, traceroutes.
- `ui/`: `screen/` (chat, messenger, nodes, settings, connection, logs, layout) and
  `widget/` (popups, node info, traceroute, telemetry, position, header, hotkeys).
- `serde/`: custom form (de)serialisers (about 1.6k lines) for the settings forms.

### State and event model

`app.rs` wires everything with Tokio channels and `tokio-graceful-shutdown`.

- One `Store` owns `State` and applies `StateAction`s from an unbounded `mpsc`,
  publishing snapshots over a `tokio::sync::watch`. It ticks every 33 ms
  (`TICK_INTERVAL_MILLIS`, `state/store.rs`) for indicators and toasts, and
  rebroadcasts "stored" actions to the persistence service.
- The UI (`ui/ui.rs`) reads crossterm `EventStream`, redraws on watch change and
  after each input event. Input becomes a `UiEvent` on a `broadcast` channel. About
  ten services subscribe, send `CommandToMeshtastic` (mpsc), listen to
  `MeshtasticEvent` (broadcast), and write back via `StateAction`.
- So it is an Elm/Redux-like unidirectional flow with one store. `Layout::render`
  takes `&State`, but widgets keep their own UI state, and the reducer is a method
  on a channel-owning `Store`, not a pure function, so it is not a "pure testable
  App" in the rig-tui sense.

### How it talks to the radio

- Uses the `meshtastic` Rust crate (0.1.9) through a personal git fork pinned by rev:
  `meshtastic = { git = "https://github.com/acelot/rust-meshtastic.git", rev =
  "1741a83", features = ["bluetooth-le"] }`. The fork is GPL-3.0, 2 commits ahead
  and 3 behind `meshtastic/rust` (GitHub compare API, 2026-11-05). Upstream is
  GPL-3.0, 151 stars, last push 2026-10-29, no GitHub releases. We need this crate
  (or an equivalent) whether we fork or port.
- TCP: `connect_via_tcp` (`meshtastic/connect.rs`) defaults the port to 4403, with
  a 5 s timeout, via `build_tcp_stream`, `StreamApi::connect`, `.configure(rand_id)`.
  That is the `meshtasticd` port, so compatibility is expected but unverified
  (untested on hardware).
- BLE (btleplug, 60 s timeout) and serial are also implemented (deferred by the
  map). `btleplug` and, on Linux, vendored `libdbus-sys` are unconditional
  dependencies, so dropping BLE needs a Cargo change.
- `RadioService` forwards `FromRadio` payloads and pauses after `MyInfo` until
  resumed (config-sync handshake). Reconnection with backoff is in the state
  (`connection_attempt`, `reconnection_backoff`).

### v1 feature coverage

| v1 feature | Present | Evidence |
|---|---|---|
| Channel messages | Yes (multi-line, reply, emoji reactions) | `ui/screen/messenger.rs`, `service/chat.rs` |
| Direct messages | Yes | `DirectChatRequested` in `layout.rs`; README |
| Node list | Mostly: name, hops, last heard, hw model, role, id per row (`ui/screen/nodes.rs`); sort and filter; SNR/RSSI stored (`0001.sql`) but whether SNR is shown in the list rows is unverified | `nodes.rs`, `0001.sql` |
| Position as text | Yes, with source tag POS/FIX/INT/EXT (`widget/position.rs`) | |
| Device config | Yes, "all available sections, including module configs" | `service/settings.rs`, `service/forms.rs` |
| Traceroute | Yes, with 60 s timeout and SNR display | `service/traceroute.rs`, `widget/traceroute*.rs` |
| Telemetry | Yes, history per node | `service/telemetry.rs`, `widget/telemetry_item.rs` |

Listed as not implemented (README): ignore node, favourites, import config link,
fixed GPS position, set time from host, lazy loading of messages. Extras beyond
v1: BLE/serial discovery, mDNS, logs screen, emoji picker, clipboard.

### Fit with the map's conventions

| Convention (map #1 Notes) | termtastic | Verdict |
|---|---|---|
| 80x24 floor | `MIN_TERMINAL_SIZE = (70, 20)` (`layout.rs`), "too small" widget below it | Meets. Real layout quality at 80x24 and use of 1280x720 not inspected (unverified). |
| 16 ANSI colours + non-colour cues | Only named `ratatui::Color` values in `src/ui` (no `Rgb`/`Indexed` by grep). Some non-colour cues (POS/FIX/INT tags, thick vs plain selection border). SNR/RSSI/battery use red/yellow/green (`ui/helpers.rs`); text cue not checked | Mostly meets |
| Quit always asks | Ctrl-C quits immediately; Esc twice within 300 ms quits with no dialog; one Esc shows a toast (`layout.rs`, `service/ui.rs`) | Conflict |
| Plain hotkeys only without a focused text area | Chat uses F2, F4-F7 for message actions, which avoids hijacking typing. Other screens use plain letters (`c`, `s`, `r`, `t`, `d`) in lists/forms (`connection.rs`, `settings.rs`, `logs.rs`) | Partial |
| Ctrl-chords everywhere | Only Ctrl-C | Conflict |
| Modals (Tab, Ctrl-S, Esc asks) | Tab/Shift-Tab switch top-level tabs; settings save is plain `s`; Esc cancels forms; dirty-form confirm not checked | Conflict |
| ratatui | ratatui 0.30.2, crossterm 0.29, ratatui-textarea, tui-widget-list | Matches |
| std threads + mpsc, 100 ms tick | Tokio, broadcast/watch/mpsc, 33 ms store tick, event-driven redraw | Conflict |
| Offline-first | SQLite persistence loaded at start | Good fit |
| Pure testable App | No tests; state logic inside channel-owning `Store` | Conflict |
| GLOSSARY vocabulary | Uses Node, Channel, Message, Chat | Compatible (check "Chat") |

### Quality notes

- Positives: clear module boundaries, typed commands and events, DB migrations,
  graceful shutdown, panic hook restores the terminal (`ui/ui.rs`).
- Negatives: `State` is a large flat struct (about 60 fields, including DB-load
  transaction fields); `types.rs` 1451 lines and `forms.rs` 3144 lines; no tests;
  unbounded channels; heavy dependencies (btleplug, mdns-sd, arboard, bundled
  SQLite, emoji set). Dependency versions are very recent; whether they build with
  this repo's Nix toolchain is unverified.

## Recommendation (input to the map, not a decision)

1. Do not fork. A fork inherits an async-actor shell, F-key/Esc input model and no
   tests that disagree with five of the conventions. Conforming means rewriting
   `app`, `store`, `ui/ui.rs`, every screen's key handling and the quit flow, while
   tracking a churning single-maintainer alpha, and carrying BLE/serial/mDNS weight
   the map defers.
2. Port selectively, keeping our own thread-based `App` shell. Adapt, with GPL
   attribution:
   - `meshtastic/connect.rs` TCP slice and the config-handshake handling in
     `radio.rs` (small).
   - Domain logic: `service/traceroute.rs` (including SNR scaling by 4.0),
     `service/telemetry.rs`, `service/nodes.rs`, and the `repository/` schema and
     mappers.
   - `service/forms.rs` as a reference list of config sections and fields (rebuild
     the UI as modals with Ctrl-S).
   - UI ideas: node row layout, position source tag, hotkey bar.
3. Depend on `meshtastic` crate either way. Choose between upstream and acelot's
   fork after inspecting the fork's 2 extra commits (not inspected).

## Unverified / open

- Build and run on the uConsole target and against `meshtasticd` on 127.0.0.1:4403
  (untested on hardware).
- Real rendering at 80x24 and 1280x720.
- Whether SNR is shown in node list rows.
- Esc behaviour on dirty settings forms; text cues for coloured SNR/RSSI.
- What the fork's 2 extra commits change.
- The README's "~20KB" memory claim was not measured and looks implausible for a
  Tokio + SQLite process.
- Stability of the settings flow, given open bugs #67 and #68.
