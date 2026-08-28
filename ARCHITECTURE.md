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

`Util.lua` provides shared accessibility/restriction checks, bounded scheduling, fading, chat-frame discovery, text collection and visual helpers.

`Core.lua` is the ownership boundary for SavedVariables, module lifecycle, the internal bus, Blizzard chat-frame lifecycle hooks, message-event filters and the consolidated `AddMessage` post-hook.

Feature modules remain independent:

- presentation: Style, Colors, Resize;
- chat-frame interaction: Dock, Controls, ChatBar, CopyOverlay, UrlCopy;
- runtime behavior: Restore, Ticker, Timestamps, Cleaner, Alerts, Sticky;
- configuration: root `Options.lua`.

`Modules/History.lua` is legacy and intentionally excluded. `Modules/Restore.lua` is the single persistence owner.

## Startup and module state

1. Blizzard loads libraries, Util, Core and module definitions in TOC order.
2. Modules register through `RothChat:RegisterModule` without activating themselves.
3. `ADDON_LOADED` initializes and migrates `RothChatDB`, preserving explicit user choices.
4. Core initializes and activates configured modules. Successful `OnEnable` transitions a module to runtime-active state.
5. `PLAYER_LOGIN` delivers one login notification to each active module.
6. A module first enabled after login receives its one-time login notification immediately after successful activation.
7. Consolidated `FCF_*` post-hooks route later frame changes through `CHAT_FRAME_READY`, `CHAT_FRAME_CLOSED` and `CHAT_LAYOUT_CHANGED`.

Configured and runtime state are intentionally separate:

```text
configured disabled
  -> no Init / no OnEnable
configured enabled
  -> Init once
  -> OnEnable per activation
  -> active
  -> optional one-time OnLogin
  -> OnDisable
  -> core owner cleanup
  -> inactive, still initialized
```

Core cleanup removes owner bus listeners, message filters and `AddMessage` callbacks even if a module's own disable path is incomplete. Permanent hooks remain installed but must check runtime activation before acting.

## Retail 12.1 filter flow

```text
Blizzard ChatFrameUtil registry
  -> one Roth Chat dispatcher per event
      -> accessibility gate for visible arg1
      -> priority-ordered module callbacks
      -> no-op: return false only
      -> discard: return true only
      -> text change: replace arg1 and return the complete received tuple
  -> Blizzard formatting / routing / HistoryKeeper
```

The core dispatcher packs incoming varargs with an explicit count, preserving interior and trailing `nil` values. It mirrors the arity it receives rather than assuming 14 or 19 fields.

Module filters are intentionally narrower: they may discard a message or propose a new visible `arg1`; they do not own sender, routing, line-ID, access-ID or metadata fields. A no-op never repacks the tuple through addon code.

## Displayed-message flow

Each discovered chat frame receives one secure `AddMessage` post-hook. Core fans already displayed, accessible messages out to registered module callbacks in priority order.

Primary consumers:

- Restore retains bounded accessible text for permanent chat-window identities;
- Ticker accepts only messages arriving while its primary chat frame is hidden;
- Alerts starts inactive dock-tab flash after display;
- Controls animates bottom-of-chat smooth scrolling only while active.

The feed is optional. No consumer may depend on guaranteed delivery or evaluate inaccessible text before its gate.

## Chat-frame lifecycle

Blizzard may create, select, dock, undock, close and reuse chat frames after login. Core collapses overlapping `FCF_*` calls into one queued lifecycle pass.

- Controls attaches hover surfaces and its owned mouse-wheel script.
- ChatBar transfers hover ownership when the selected dock frame changes.
- Style reapplies guarded visual state.
- Resize creates or hides frame-specific grips and cancels stale animations.
- Restore applies owned fade settings to newly discovered frames.
- CopyOverlay creates frame-local copy surfaces and closes them on frame teardown.

Temporary whisper frames are reusable runtime surfaces, not durable persistence identities.

## Visibility and alpha arbitration

Controls owns hover state; Ticker owns immersion alpha for the configured primary chat frame; CopyOverlay is a temporary modal surface.

```text
CopyOverlay close
  -> restore pre-overlay alpha snapshot
  -> emit COPY_OVERLAY_VISIBILITY(false)
  -> Controls/Ticker calculate authoritative current alpha
```

This ordering prevents a stale overlay snapshot from overriding the current hover or immersion state.

## Persistence

`RothChatDB.profile` stores settings, module flags and the addon version. Migrations initialize only missing or obsolete fields and preserve explicit choices.

Restore stores bounded entries only for permanent indexed chat windows. It snapshots Blizzard `fading`, `timeVisible` and `fadeDuration` values before changing them and restores those values when disabled.

`RothChatDB.history` is legacy compatibility data. `History.lua` must not be enabled alongside Restore without an intentional replacement migration.

## Scheduling and performance

The shared scheduler coalesces keyed deferred jobs. The fade updater and scheduler remove their `OnUpdate` scripts when idle. Ticker head operations use indexed queue bookkeeping. Combat-interrupted Resize, Dock and Style work cancels or deduplicates its active driver and defers at most one continuation.

Controls owns `OnMouseWheel` while active rather than stacking another `HookScript` path over Blizzard scrolling. When inactive, its wrapper delegates to the captured original script.

## Localization

Cleaner snapshots Blizzard's current localized format strings. Normal mode removes brackets around the sender placeholder without replacing localized channel labels. Compact language-neutral tags are applied only when `cleanerShorten` is enabled. Disable restores a snapshot only when no later writer changed the same global.

## Restriction boundary

`canaccessvalue` compatibility is the operational gate. Chat callbacks may be skipped when values are inaccessible. No filter, ticker, copy, alert or restore path may depend on guaranteed callback delivery. Raw event payloads must not become durable feature state; only already displayed, accessible text may cross into bounded Restore/copy surfaces.

Automated contracts live under `tests/` and `.github/workflows/validate.yml`. Runtime gates are recorded in `MIGRATION_12_1.md`.
