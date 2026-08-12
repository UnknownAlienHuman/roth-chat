# Roth Chat agent guide

## Start here

Read [`RothChat.toc`](RothChat.toc), then [`Util.lua`](Util.lua) and [`Core.lua`](Core.lua). The TOC order is bundled libraries -> `Util.lua` -> `Core.lua` -> registered modules in this exact order: Dock, Style, Controls, ChatBar, Restore, CopyOverlay, UrlCopy, Colors, Resize, Ticker, Timestamps, Cleaner, Alerts, Sticky -> root `Options.lua`. `Modules/History.lua` is deliberately commented out and is legacy code; current persistence is in `Modules/Restore.lua`.

## Runtime and data flow

`Core.lua` creates the addon frame and namespace, initializes `RothChatDB` on `ADDON_LOADED`, enables registered modules, and calls module `OnLogin` methods on `PLAYER_LOGIN`. Its internal bus (`RothChat:On`, `Off`, `Emit`) carries `CHAT_FRAME_READY`, `CHAT_FRAME_CLOSED`, `CHAT_LAYOUT_CHANGED`, `CHAT_FEED`, `CONTROLS_VISIBILITY`, and copy-overlay events. `EnsureChatLifecycleHooks` post-hooks Blizzard `FCF_*` functions and queues a single lifecycle refresh through `Util.lua`.

Modules register with `RothChat:RegisterModule`; each module owns one concern and communicates through the core bus. Message transformations use the centralized priority filter registry (`RegisterMessageFilter`) and one consolidated `AddMessage` hook (`RegisterAddMessageHook`). `Util.lua` supplies protected calls, secret-safe string conversion, chat restriction checks, scheduled jobs, fade updates, frame discovery, text collection, and backdrop helpers.

## State, surfaces, dependencies

The only declared SavedVariables root is `RothChatDB`; `Core.lua` owns `RothChatDB.profile` (settings, module enable flags, version) and `RothChatDB.history` (Restore-owned entries). Module toggles are keys named `module_<ModuleName>_enabled`; upgrade migration force-enables critical modules and keeps legacy History disabled by default.

`/rothchat` opens the Settings category (or reports the legacy Interface Options path). `Options.lua` owns the Settings controls and writes through `RothChat:Get`/`Set`, then refreshes affected modules. Bundled libraries are LibStub, CallbackHandler-1.0, and LibSharedMedia-3.0; no external TOC dependency is declared.

## Invariants and risks

- Keep `Modules/History.lua` disabled unless intentionally replacing Restore; enabling both would duplicate persistence/filtering.
- Chat text can be restricted/secret. Preserve `NS.IsChatMessagingRestricted`, `IsSecretValue`, `SafeToString`, and `SafeCall` boundaries; do not concatenate untrusted values directly in new hooks.
- `Util.lua` has two `OnUpdate` drivers (scheduler and fader), but they must be active only while work/fades exist. Do not add permanent per-frame scans.
- One core `AddMessage` dispatch and priority filters prevent N modules from independently hooking every chat frame. Register/unregister through core ownership APIs.
- `FCF_*` hooks and chat-frame creation/close paths are lifecycle-sensitive; use `CHAT_FRAME_READY`/`CHAT_LAYOUT_CHANGED` and `NS.Schedule` for deferred geometry.

## Change routing

- Shared safety/scheduling/frame helpers: `Util.lua`.
- Core bus/module enablement/lifecycle/settings bridge: `Core.lua`.
- Appearance/geometry: `Modules/Style.lua`, `Colors.lua`, `Resize.lua`, `Dock.lua`.
- Interaction/copy: `Controls.lua`, `ChatBar.lua`, `CopyOverlay.lua`, `UrlCopy.lua`.
- Persistence and message behavior: `Restore.lua`, `Ticker.lua`, `Timestamps.lua`, `Cleaner.lua`, `Alerts.lua`, `Sticky.lua`.
- Controls/settings: root `Options.lua` (not `Modules/Options.lua`).

## Verification

Static: verify the TOC list and that every enabled module calls `RothChat:RegisterModule`; parse Lua and run `git diff --check`. In game, run `/rothchat`, toggle each module, create/close temporary and docked chat frames, test whisper/channel URL filtering, copy overlay, timestamps, and reload persistence. Check combat/chat restriction behavior and that no RothChat/module errors appear. This audit does not claim a live client run.
