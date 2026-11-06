# Research: `meshtastic` Rust crate fit

Resolves issue #2 (map: #1). Researched 2026-11-05 from primary sources: the crate source (github.com/meshtastic/rust at `6310bd8`, 2026-10-29), the crates.io 0.1.9 tarball and API, and the GitHub API for meshtastic/protobufs and meshtastic/firmware. **Nothing here was compiled or run against a device** (no `cargo` in the research sandbox); behaviour claims come from reading source and are marked "unverified" where they depend on runtime behaviour.

## Answer in brief

- Use it for protocol/protobuf types and framing, but not as a drop-in: it is **GPL-3.0** and **hard-wired to tokio**.
- **License** is the gating question. The crate (`license = "GPL-3.0"` in Cargo.toml and on every crates.io version) and the protobufs repo (GPLv3 LICENSE file; GitHub reports GPL-3.0) are both GPL-3.0. Linking it makes mesh-tui a GPL-3.0 combined work. Check this against the repo's own `LICENSE` and intent before depending on it.
- **Version**: crates.io `0.1.9` (2026-05-25) has generated protobuf code byte-identical to git `main` (`src/generated/meshtastic.rs`, 10284 lines, `diff` clean). Git main has 4 later commits (BLE fixes, MSRV 1.88) that do not touch TCP. Prefer crates.io unless a BLE fix is wanted.
- **Freshness**: generated code is from a protobufs submodule pin dated 2026-03-22 (`cb1f893`); protobufs master was 402 commits ahead on 2026-11-05. Firmware is at v2.8.2 (2026-10-29). Unknown fields are skipped by prost, so older generated code generally still decodes, but new fields/enum values are missing (see "Freshness").
- **Tokio fit**: the I/O layer (TCP, framing, heartbeat, config handshake) is async-only and `tokio::spawn`s its own tasks, so a runtime must exist. It can be hosted on one background thread with a private runtime and bridged to std `mpsc`; this is workable but is a design decision, not free.
- **Feature coverage**: connect, text send, config write: helpers exist. Node DB, config read, traceroute, telemetry, text receive: no helpers; only the raw protobuf types and a `FromRadio` stream.

## Versions

| Source | Version | Date | License |
|---|---|---|---|
| crates.io | 0.1.9 (latest; 0.1.0-0.1.9 all published) | 2026-05-25 | GPL-3.0 |
| git `main` | 0.1.9 + 4 commits, head `6310bd8` | 2026-10-29 | GPL-3.0 |

Sources: `https://crates.io/api/v1/crates/meshtastic`; `gh api repos/meshtastic/rust/commits`. Release cadence is slow (0.1.6 in 2024-03, 0.1.7 in 2025-07, 0.1.8 in 2025-11) with ~33k downloads. MSRV 1.88, edition 2021. Open issues include one about the `PacketRouter` trait (#63) and malformed-packet false positives with UTF-8 emoji (#71) (titles only; not read in depth).

## API surface

All in `src/connections/stream_api.rs` unless noted. Everything is `async`.

- **TCP connect**: `utils::stream::build_tcp_stream(addr: String).await` returns `StreamHandle<tokio::net::TcpStream>` with a hard-coded 3 s connect timeout (`utils_internal.rs`). Then `StreamApi::new().connect(handle).await` returns `(PacketReceiver, ConnectedStreamApi<Connected>)`. `PacketReceiver` is `tokio::sync::mpsc::UnboundedReceiver<protobufs::FromRadio>`. `connect` spawns four tokio tasks: read, write, framing/processing, and a heartbeat (`CLIENT_HEARTBEAT_INTERVAL`).
- **Handshake**: `.configure(config_id).await` sends `ToRadio::WantConfigId`; the radio then streams its state as `FromRadio` messages. Typestate (`Connected` -> `Configured`) enforces this at compile time. `disconnect().await` returns the `StreamApi`.
- **Text send**: `send_text(&mut self, packet_router: &mut R, text, PacketDestination, want_ack, MeshChannel)`. Requires a `PacketRouter` impl (trait in `connections/mod.rs`) which supplies `source_node_id()` and `handle_packet_from_radio`; used to echo sent packets back into your own handling. You must implement this trait even if you do not want echo.
- **Text receive**: no helper. Read `FromRadio`, match `PayloadVariant::Packet(MeshPacket)`, then `Decoded(Data)` with `portnum == TextMessageApp`, and decode `payload` as UTF-8 yourself (see `examples/message_filtering.rs`).
- **Node DB**: the crate keeps none. Nodes arrive as `FromRadio::NodeInfo` (`protobufs::NodeInfo`) during the `configure` dump and as `NodeinfoApp` packets afterwards; the app must store them.
- **Config read**: no getter. The initial dump is expected to include `FromRadio` `Config`, `ModuleConfig`, `Channel`, `MyInfo`, `Metadata` variants (standard Meshtastic handshake; the crate just forwards them; not verified against a device). Later reads would need hand-built `AdminMessage` requests via `send_mesh_packet` (unverified; not exercised by the crate).
- **Config write**: `update_config`, `update_module_config`, `update_channel_config`, `update_user`, `start_config_transaction` / `commit_config_transaction`, and bulk `set_local_config`, `set_local_module_config`, `set_message_channel_config`. These are the strongest part of the API.
- **Traceroute**: nothing dedicated. Types exist (`PortNum::TracerouteApp = 70`, `RouteDiscovery`). Send via the generic `send_mesh_packet(..., PortNum::TracerouteApp, ..., want_response = true, ...)` with an encoded `RouteDiscovery`, and decode replies yourself. Unverified that the firmware accepts exactly this request shape.
- **Telemetry**: no helper; `protobufs::Telemetry` with variants `DeviceMetrics`, `EnvironmentMetrics`, `AirQualityMetrics`, `PowerMetrics` (and others) is decoded by you from `TelemetryApp` packets.
- Also: `send_waypoint`, `send_position`, `send_raw`, `write_input_sender()` (an `UnboundedSender` of pre-framed bytes, usable for fully manual sends), serial and (feature `bluetooth-le`) BLE connections.

## Fit with std threads + mpsc on a 100 ms tick

Facts from source:
- `tokio` is an optional dependency in a **default** feature, and the whole `api`, `packet`, `utils` and `errors` modules are `#[cfg(feature = "tokio")]`. Only `protobufs` (and `prost::Message`) compile without it. README line 8: "designed to be used within the tokio asynchronous runtime".
- Dependency is `tokio = { features = ["full"] }`, so it pulls in the full tokio feature set, plus `tokio-serial` and `tokio-util`. `serde`/`strum` defaults are also on.
- The handlers call `tokio::spawn`, so `connect` is expected to panic outside a runtime (inference from `spawn` in `handlers.rs`; unverified at runtime).
- The receive side is a tokio `UnboundedReceiver`, which has `try_recv()` (non-blocking, works from non-async code) and `blocking_recv()`. Sends go through async methods only, but `write_input_sender()` is a plain `UnboundedSender` whose `send` is sync.

Integration options:
1. **Bridge thread (most compatible)**: one std thread owns a `tokio::runtime::Builder::new_current_thread()` (or multi-thread), runs the connection, and forwards `FromRadio` into an `std::sync::mpsc::Sender` that the UI drains each tick; UI-to-radio commands arrive over a std channel the bridge polls (or a tokio channel the UI sends into with sync `send`). Adds tokio to the dependency tree but keeps the app threaded as designed.
2. **Hold the runtime handle and `try_recv` from the UI thread**: avoids a forwarding hop for receive; sends still need `runtime.block_on` or `handle.spawn`. Mixed model, more subtle.
3. **Use only the protobufs**: depend on the crate with `default-features = false` (only `protobufs`), write the std-thread TCP loop (port 4403, `0x94 0xC3` header + length framing, as in `stream_buffer.rs`) yourself. Avoids tokio and keeps the types, but re-implements framing, handshake and heartbeat, and the `PacketRouter`-based send helpers are lost because they are tokio-gated. Whether `default-features = false` builds cleanly is unverified.

## Freshness against current firmware

- `src/protobufs` submodule gitlink in the crate is `cb1f89372a70b0d4b4f8caf05aec28de8d4a13e0`, dated 2026-03-22. `gh api repos/meshtastic/protobufs/compare/cb1f893...master` reports 402 commits ahead (checked 2026-11-05). Recent upstream changes include `DeviceMetadata.ble_address` (2026-11-01) and a new `NotificationType` value (2026-11-04).
- Latest firmware release: v2.8.2 (2026-10-29), with a dev tag on 2026-11-04. protobufs has a v2.8.2 release tag (2026-10-29). The crate's pin therefore predates 2.8.x by months; which fields it lacks was not diffed. Protobuf wire format is forward-compatible, so core text/nodeinfo/config traffic is expected to decode, but any new fields would be silently dropped. Unverified against a real 2.8.x device.
- Regenerating is possible: feature `gen` (prost-build + vendored protoc) rebuilds `src/generated/` from the submodule, so one can vendor a fork or bump the submodule. That means depending on git or a fork rather than crates.io.

## Licenses

- `meshtastic` crate: `GPL-3.0` (Cargo.toml; LICENSE file is full GPLv3 text).
- `meshtastic/protobufs`: LICENSE file is GNU GPL v3; GitHub API reports `GPL-3.0`. Generated Rust code in the crate is derived from it.
- Consequence: distributing a binary that links the crate requires GPL-3.0-compatible licensing and a source offer for mesh-tui. Writing own bindings by copying or compiling the `.proto` files is also derivative of GPL-3.0 files. This is not legal advice; resolve it with the repo owner.

## Open questions for the map

1. Is GPL-3.0 acceptable for mesh-tui? (Blocks any dependence on the crate or the protos.)
2. Bridge thread (option 1) vs own framing with protobufs only (option 3).
3. Whether the stale protobuf pin matters for v1 features; test against a 2.8.x node or simulator before committing (the crate's `basic_tcp` example points to the firmware Docker image for a simulated radio over TCP).
4. Traceroute and admin-read request shapes are unverified; prototype them.

## Sources

- https://github.com/meshtastic/rust (`Cargo.toml`, `src/lib.rs`, `src/connections/{stream_api,handlers,stream_buffer,mod}.rs`, `src/utils_internal.rs`, `examples/basic_tcp.rs`, `README.md`, `.gitmodules`)
- https://crates.io/api/v1/crates/meshtastic and the 0.1.9 download tarball
- https://github.com/meshtastic/protobufs (LICENSE, commits, releases) via `gh api`
- https://github.com/meshtastic/firmware releases via `gh api`
