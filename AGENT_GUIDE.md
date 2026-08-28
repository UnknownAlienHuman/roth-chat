# Roth Chat agent guide

## Current target

- World of Warcraft Retail `12.1.0`
- Interface `120100`
- Roth Chat `1.1.0`
- Verified Blizzard source baseline `12.1.0.69497` / `Gethe/wow-ui-source@027d26c3406d`

Before changing chat or restriction-sensitive code, read the corresponding material in [`UnknownAlienHuman/wow-addon-engineering-kb`](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb), especially `KB/nodes/BlizzardUI_Chat.md` and `KB/core/BlizzardUI_security.md`.

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
- module registration and enablement;
- the internal event bus;
- centralized message-event filters;
- the consolidated `AddMessage` post-hook;
- Blizzard chat-frame lifecycle routing;
- combat-deferred work.

`Util.lua` owns shared safety, restriction checks, scheduling, fading, chat-frame discovery, text collection and visual helpers. Modules own one feature each and communicate through core APIs instead of adding parallel global hooks.

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

The executable contract test is [`tests/core_chat_filter_spec.lua`](tests/core_chat_filter_spec.lua).

## SavedVariables migration rule

`RothChatDB.profile.__version` records the addon version. A version migration may initialize missing fields, normalize obsolete values or retire legacy state, but it must not overwrite explicit feature or module choices.

Module toggles are stored as `module_<ModuleName>_enabled`. Defaults are written only when a key is absent. Raising `RothChat.version` must not re-enable modules the user disabled.

## Restriction and taint boundaries

- Gate secret-capable chat text before comparison, formatting, concatenation, serialization or retention.
- Preserve `NS.IsChatMessagingRestricted`, `NS.IsSecretValue`, `NS.SafeToString` and `NS.SafeCall` boundaries.
- Do not replace Blizzard chat globals or `ChatFrameUtil` functions.
- Use `ChatFrameUtil.AddMessageEventFilter` through `NS.AddMessageEventFilter`; keep the legacy global only as a feature-detected fallback.
- Do not retain raw chat event payloads in SavedVariables.
- Protected or settings changes must degrade cleanly during combat and chat lockdown.
- Do not add retry loops around denied operations.

## Performance invariants

- The scheduler and fader `OnUpdate` handlers run only while work exists.
- Do not add permanent frame scans or per-message frame/closure creation.
- Keep one core `AddMessage` hook per chat frame.
- Register and unregister listeners, filters and hooks through their owner-aware core APIs.
- Queue chat lifecycle/layout refreshes rather than repeating overlapping `FCF_*` work immediately.

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
- run the 19-field dispatcher contract test;
- verify TOC interface, version and author;
- verify every active TOC path exists.

Then perform the in-game matrix on Retail:

- fresh login, `/reload`, logout/login;
- say, party, raid, instance, guild, whisper, reply, Battle.net whisper and numbered channels;
- messages with and without timestamps/URLs;
- forced chat restrictions and real restricted content transitions;
- combat entry/exit;
- create, dock, select, undock and close chat windows;
- copy overlay and persistent Restore data;
- module enable/disable persistence;
- zero repeating taint, secret-value or forbidden-operation errors.

Static validation does not constitute a live-client pass. Record runtime results in `MIGRATION_12_1.md` before packaging a release.

## Third-party boundary

Do not edit or remove bundled license notices. Glass-derived textures retain their original MIT attribution under `ThirdParty/GLASS_LICENSE.txt`.
