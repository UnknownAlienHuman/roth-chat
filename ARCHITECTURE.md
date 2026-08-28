# Roth Chat architecture

## Layers

```text
RothChat.toc
  -> bundled libraries
  -> Util.lua
  -> Core.lua
  -> feature modules
  -> Options.lua
```

`Util.lua` provides shared safety, restriction checks, bounded scheduling, fading, chat-frame discovery, text collection and visual helpers.

`Core.lua` is the ownership boundary for SavedVariables, module lifecycle, the internal bus, Blizzard chat-frame lifecycle hooks, message-event filters and the consolidated `AddMessage` post-hook.

Feature modules remain independent:

- presentation: Style, Colors, Resize;
- chat-frame interaction: Dock, Controls, ChatBar, CopyOverlay, UrlCopy;
- runtime behavior: Restore, Ticker, Timestamps, Cleaner, Alerts, Sticky;
- configuration: root `Options.lua`.

`Modules/History.lua` is legacy and intentionally excluded. `Modules/Restore.lua` is the single persistence owner.

## Startup flow

1. Blizzard loads libraries, Util, Core and every active module in TOC order.
2. Modules register definitions through `RothChat:RegisterModule`.
3. `ADDON_LOADED` initializes and migrates `RothChatDB` without overwriting stored user choices.
4. Core applies module enablement.
5. `PLAYER_LOGIN` gives enabled modules their login pass, initializes settings and queues a complete chat-frame refresh.
6. Consolidated `FCF_*` post-hooks route later frame changes through `CHAT_FRAME_READY`, `CHAT_FRAME_CLOSED` and `CHAT_LAYOUT_CHANGED`.

## Retail 12.1 filter flow

```text
Blizzard ChatFrameUtil registry
  -> one Roth Chat dispatcher per event
      -> priority-ordered module callbacks
      -> no-op: return false only
      -> discard: return true only
      -> text change: replace arg1 and return the complete received tuple
  -> Blizzard formatting / routing / HistoryKeeper
```

The core dispatcher packs incoming varargs with an explicit count, preserving interior and trailing `nil` values. It mirrors the arity it receives rather than assuming 14 or 19 fields. This keeps the adapter compatible with current 12.1 behavior and later contract growth.

Module filters are intentionally narrower: they may discard a message or propose a new visible `arg1`; they do not own sender, routing, line-ID, access-ID or metadata fields.

A no-op never repacks the tuple through addon code. This is both a taint reduction and a performance invariant.

## AddMessage flow

Each discovered chat frame receives one secure post-hook. Core fans the displayed message out to registered module callbacks in priority order. Modules must treat this feed as optional and must not evaluate secret-capable text before their safety gate.

## Persistence

`RothChatDB.profile` stores settings, module flags and the addon version. Migrations initialize only missing or obsolete fields and preserve explicit module/feature choices.

`RothChatDB.history` is owned by Restore. History.lua must not be enabled alongside Restore without an intentional replacement migration.

## Scheduling and performance

The shared scheduler coalesces keyed deferred jobs. The fade updater and scheduler remove their `OnUpdate` scripts when idle. Chat lifecycle changes are queued and collapsed to avoid repeating geometry and module refreshes for overlapping Blizzard calls.

## Restriction boundary

Chat callbacks may be skipped when values are inaccessible. No filter, ticker, copy or restore path may depend on guaranteed callback delivery. Raw event payloads must not become durable feature state; only already displayed, accessible text may cross into bounded Restore/copy surfaces.

Automated structure and filter-contract checks live in `.github/workflows/validate.yml` and `tests/core_chat_filter_spec.lua`. Runtime gates are recorded in `MIGRATION_12_1.md`.
