# Roth Chat agent guide

## Target

- World of Warcraft Retail / Midnight `12.1.0`
- Interface `120100`
- Roth Chat `1.1.0`
- Author: Neomorph

The current Blizzard-source baseline is recorded in the engineering knowledge base. Revalidate that baseline before changing chat filters, restricted-value handling, or Blizzard frame integration.

## Start here

Read [`RothChat.toc`](RothChat.toc), then [`Util.lua`](Util.lua) and [`Core.lua`](Core.lua). The TOC order is bundled libraries -> `Util.lua` -> `Core.lua` -> registered modules in this exact order: Dock, Style, Controls, ChatBar, Restore, CopyOverlay, UrlCopy, Colors, Resize, Ticker, Timestamps, Cleaner, Alerts, Sticky -> root `Options.lua`. `Modules/History.lua` is deliberately disabled; current persistence is owned by `Modules/Restore.lua`.

## Runtime and data flow

`Core.lua` creates the addon frame and namespace, initializes `RothChatDB` on `ADDON_LOADED`, enables registered modules, and calls module `OnLogin` methods on `PLAYER_LOGIN`. Its internal bus (`RothChat:On`, `Off`, `Emit`) carries `CHAT_FRAME_READY`, `CHAT_FRAME_CLOSED`, `CHAT_LAYOUT_CHANGED`, `CONTROLS_VISIBILITY`, and copy-overlay events. `EnsureChatLifecycleHooks` post-hooks Blizzard `FCF_*` functions and queues a consolidated lifecycle refresh through `Util.lua`.

Modules register with `RothChat:RegisterModule`; each module owns one concern and communicates through core-owned registries. Message transformations use the centralized priority filter registry (`RegisterMessageFilter`) and one consolidated `AddMessage` hook (`RegisterAddMessageHook`).

For Retail 12.1, the shared chat filter accepts the complete 19-argument tuple. Roth Chat callbacks may replace only `arg1`, the visible message text. A no-op callback path returns only `false`, allowing Blizzard to retain its current secure tuple. When `arg1` actually changes, the dispatcher returns all 19 fields and preserves every routing, sender, line-ID, access-ID, and metadata value unchanged. A discard path returns only `true`.

The post-`AddMessage` boundary is render-facing: it accepts only accessible string text, normalizes colors to accessible numbers or `nil`, and deliberately does not forward trailing opaque metadata to addon modules.

## State and dependencies

The only declared SavedVariables root is `RothChatDB`; `Core.lua` owns `RothChatDB.profile` and `RothChatDB.history`. Module toggles are keys named `module_<ModuleName>_enabled`. Version migration is additive: new missing defaults may be added, but an upgrade must not re-enable a module or feature that the user explicitly disabled.

`/rothchat` opens the Settings category. `Options.lua` owns the Settings controls and writes through `RothChat:Get` / `Set`, then refreshes affected modules. Bundled libraries are LibStub, CallbackHandler-1.0, and LibSharedMedia-3.0; no external TOC dependency is declared.

## Security invariants

- Treat `canaccessvalue` and `canaccessallvalues` as operation gates. `issecretvalue` is provenance information, not permission to use a value.
- Gate before nil/type checks, truth tests, comparisons, arithmetic, formatting, concatenation, length, table key/index use, iteration, logging, persistence, API forwarding, or timer/closure capture.
- If any incoming 19-field filter tuple value is inaccessible, skip Roth Chat filtering and let Blizzard continue with the untouched payload.
- Return only `false` when text is unchanged. A truthy second callback return activates Blizzard tuple replacement; therefore a real text replacement must include all 19 fields.
- Never retain raw event/filter tuples or trailing `AddMessage` metadata. Only access-normalized render text and ordinary primitives may enter module state.
- Keep `Modules/History.lua` disabled unless intentionally replacing Restore; enabling both duplicates persistence and filtering.
- `Util.lua` has two demand-driven `OnUpdate` drivers (scheduler and fader). They must be active only while work exists; do not add permanent per-frame scans.
- Register chat-frame message consumers through the one core `AddMessage` dispatcher rather than independently hooking every frame.
- Use `CHAT_FRAME_READY` / `CHAT_LAYOUT_CHANGED` and the shared scheduler for lifecycle-sensitive geometry.
- Do not replace Blizzard chat globals or shared `ChatFrameUtil` functions.

## Change routing

- Shared access gates, scheduling, frame helpers: `Util.lua`.
- Core bus, module enablement, filter tuple, lifecycle: `Core.lua`.
- Appearance and geometry: `Modules/Style.lua`, `Colors.lua`, `Resize.lua`, `Dock.lua`.
- Interaction and copy: `Controls.lua`, `ChatBar.lua`, `CopyOverlay.lua`, `UrlCopy.lua`.
- Persistence and message behavior: `Restore.lua`, `Ticker.lua`, `Timestamps.lua`, `Cleaner.lua`, `Alerts.lua`, `Sticky.lua`.
- Settings: root `Options.lua`, not `Modules/Options.lua`.

## Verification

Static checks:

1. Confirm `RothChat.toc` targets the intended Interface and load order.
2. Parse every changed Lua file with a compatible Lua parser where available.
3. Confirm each enabled module calls `RothChat:RegisterModule`.
4. Inspect the branch diff for accidental global replacement, raw payload retention, whitespace errors, or unrelated edits.
5. Confirm no-op filter paths return only `false`; transformed paths return all 19 arguments and replace only `arg1`.

Live-client checks:

1. Run `/rothchat` and toggle each module.
2. Exercise say, party, raid, guild, channel, whisper, Battle.net whisper, system, achievement, and monster-yell paths.
3. Test combat/chat restrictions and verify inaccessible callbacks degrade silently.
4. Create, select, undock, redock, and close normal and temporary whisper windows.
5. Test URL conversion, timestamps, copy overlay, inactive-tab alerts, ticker/immersion, smooth scrolling, and reload persistence.
6. Verify zero Roth Chat, HistoryKeeper, taint, secret-value, forbidden, or repeating Lua errors.

Do not describe a release as live-client verified unless that matrix was actually run in WoW.
