# Roth Chat agent guide

## Current target

- World of Warcraft Retail `12.1.0`
- Interface `120100`
- Roth Chat `1.1.1`
- Verified Blizzard source baseline `12.1.0.69497` / `Gethe/wow-ui-source@027d26c3406d`

Before changing chat or restriction-sensitive code, read the corresponding material in [`UnknownAlienHuman/wow-addon-engineering-kb`](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb), especially `KB/nodes/BlizzardUI_Chat.md`, `KB/core/BlizzardUI_security.md` and the active upstream issue list.

## Start here

Read [`RothChat.toc`](RothChat.toc), then [`Util.lua`](Util.lua) and [`Core.lua`](Core.lua).

The active load order is:

1. bundled libraries;
2. `Util.lua`;
3. `Core.lua`;
4. Dock, Style, Controls, ChatBar, Restore, CopyOverlay, UrlCopy, Colors, Resize, Ticker, Timestamps, Cleaner, Alerts and Sticky;
5. root `Options.lua`.

`Modules/History.lua` is deliberately excluded. `Modules/Restore.lua` is the only active persistence owner.

## Runtime ownership

`Core.lua` owns:

- `RothChatDB` initialization and migrations;
- configured module defaults and runtime activation state;
- one-shot `Init` and `OnLogin` delivery;
- owner cleanup for listeners, filters and `AddMessage` callbacks;
- the internal event bus;
- centralized message-event filters;
- the consolidated `AddMessage` post-hook;
- Blizzard chat-frame lifecycle routing;
- combat-deferred work with preserved argument arity.

`Util.lua` owns shared safety, accessibility checks, restriction checks, scheduling, fading, chat-frame discovery, text collection and visual helpers. Modules own one feature each and communicate through core APIs instead of adding parallel global hooks.

## Module lifecycle contract

Use the correct state query:

- `core:IsModuleEnabled(name)` reads the configured SavedVariables choice.
- `core:IsModuleActive(name)` confirms that `OnEnable` completed successfully in the current runtime.

Rules:

- `Init` is one-shot and must create durable module resources only.
- `OnEnable` must rebuild owner-aware registrations and be safe after a prior disable.
- `OnDisable` must stop local timers/animations and restore state the module exclusively owns.
- Core defensively removes owner listeners, message filters and `AddMessage` callbacks after disable.
- `OnLogin` is delivered once to an active module; a module first enabled after login receives it immediately after successful activation.
- A permanent `hooksecurefunc`/`HookScript` callback cannot be removed, so it must check current runtime activation before changing state.
- Do not infer activation from a configured checkbox inside hot callbacks.

The executable lifecycle contract is [`tests/core_module_lifecycle_spec.lua`](tests/core_module_lifecycle_spec.lua).

## Retail 12.1 message-filter contract

Never hard-code a 14-argument or 19-argument callback signature in the core dispatcher. Preserve the exact tuple received, including interior and trailing `nil` positions.

Module callbacks use this narrow contract:

```lua
-- No discard and no text change.
return false

-- Discard the message.
return true

-- Replace visible arg1 only. Core rebuilds the complete current tuple.
return false, newArg1
```

Core rules:

- no-op returns only `false`; Blizzard retains its secure transformed tuple;
- discard returns only `true`;
- a truthy replacement updates only `arg1`;
- the transformed path returns every field received, with the original arity;
- later Roth Chat filters receive the latest transformed `arg1`;
- filter failures degrade to a no-op;
- callbacks are optional and stateless because Blizzard may skip them when values are inaccessible.

Do not return `false, newArg1` directly from an independently registered Blizzard filter unless every remaining current field is also preserved. Do not use a message filter as a guaranteed log or state machine.

The executable contract is [`tests/core_chat_filter_spec.lua`](tests/core_chat_filter_spec.lua).

## SavedVariables and persistence

`RothChatDB.profile.__version` records the addon version. A migration may initialize missing fields, normalize obsolete values or retire legacy state, but it must not overwrite explicit feature or module choices.

Module toggles are stored as `module_<ModuleName>_enabled`. Defaults are written only when a key is absent. Raising `RothChat.version` must not re-enable modules the user disabled.

Permanent chat-window indices may be used for Restore buckets. Temporary whisper frames are reused by Blizzard and are not durable identities; never store their displayed text under a permanent frame-index bucket.

## Restriction and taint boundaries

- Gate secret-capable values with `NS.CanAccessValue` before comparison, type-dependent formatting, concatenation, serialization, animation or retention.
- `issecretvalue` and `canaccessvalue` are not interchangeable; accessibility is the operational gate.
- Preserve `NS.IsChatMessagingRestricted`, `NS.SafeToString`, `NS.SafeTrunc` and `NS.SafeCall` boundaries.
- Do not replace Blizzard chat globals or `ChatFrameUtil` functions.
- Use `ChatFrameUtil.AddMessageEventFilter` through `NS.AddMessageEventFilter`; keep the legacy global only as a feature-detected fallback.
- Do not retain raw chat-event payloads in SavedVariables.
- Protected or settings changes must degrade cleanly during combat and chat lockdown.
- Do not add retry loops around denied operations.

## Interaction and alpha ownership

- Controls owns hover visibility for chat chrome and accessory frames.
- Ticker owns immersion alpha for the configured primary chat frame.
- CopyOverlay temporarily obscures chat, then emits its visibility change after restoring its snapshot so Controls/Ticker determine the authoritative final state.
- ChatBar and Resize must unregister accessory hover ownership when moving or disabling.
- Controls owns the chat frame's `OnMouseWheel` script while active and delegates to the captured original while inactive; do not add another `HookScript("OnMouseWheel")` path.
- Restore owns its changes to `SetFading`, `SetTimeVisible` and `SetFadeDuration` and must restore prior values on disable.

## Performance invariants

- The scheduler and fader `OnUpdate` handlers run only while work exists.
- Do not add permanent frame scans or per-message frame/closure creation.
- Keep one core `AddMessage` hook per chat frame.
- Keep ticker queues bounded and O(1) at the head.
- Register and unregister listeners, filters and hooks through owner-aware core APIs.
- Queue chat lifecycle/layout refreshes rather than repeating overlapping `FCF_*` work immediately.
- If combat interrupts an animation or layout mutation, cancel the active driver and queue at most one deferred continuation.

## Change routing

- Shared safety, scheduling and frame helpers: `Util.lua`
- Core bus, module lifecycle, filters and SavedVariables: `Core.lua`
- Appearance and geometry: `Modules/Style.lua`, `Colors.lua`, `Resize.lua`, `Dock.lua`
- Interaction and copying: `Controls.lua`, `ChatBar.lua`, `CopyOverlay.lua`, `UrlCopy.lua`
- Persistence and message behavior: `Restore.lua`, `Ticker.lua`, `Timestamps.lua`, `Cleaner.lua`, `Alerts.lua`, `Sticky.lua`
- Settings: root `Options.lua`
- Release/migration evidence: `CHANGELOG.md`, `MIGRATION_12_1.md`

## Verification

Automated validation in `.github/workflows/validate.yml` must pass:

- parse every `.lua` file;
- run the complete chat-filter contract;
- run module activation/cleanup/late-login contracts;
- run URL transformation and accessibility contracts;
- run Cleaner localization/restoration contracts;
- verify TOC interface, version, author and active load paths.

Then perform the in-game matrix on current Retail:

- fresh login, `/reload`, logout/login;
- module disable/re-enable before and after login;
- say, party, raid, instance, guild, whisper, reply, Battle.net whisper and numbered channels;
- messages with and without timestamps/URLs;
- forced chat restrictions and real restricted-content transitions;
- combat entry/exit during resize, dock/style refresh and settings changes;
- create, dock, select, undock, reuse and close chat windows;
- copy overlay, ticker and Restore ownership transitions;
- localized Cleaner formats with compact mode off and on;
- zero repeating taint, secret-value or forbidden-operation errors.

Static validation does not constitute a live-client pass. Record runtime results in `MIGRATION_12_1.md` before packaging a release.

## Third-party boundary

Do not edit or remove bundled license notices. Glass-derived textures retain their original MIT attribution under `ThirdParty/GLASS_LICENSE.txt`.
