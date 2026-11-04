# Roth Chat engineering guide

## Current target and evidence

- World of Warcraft Retail build `12.1.5.70688`; expected TOC interface `120105`.
- Addon version `1.2.0`.
- Blizzard UI source checked 2026-11-02: [`Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`](https://github.com/Gethe/wow-ui-source/commit/d07eb00237d8891f153215db98a5df880a26cfe5).
- Engineering KB reference: [`wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/commit/b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83).
- PR5 changes selectively reviewed at [`40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f`](https://github.com/UnknownAlienHuman/roth-chat/commit/40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f), based on [`main@3c995183626002965043e38a837346fb290acd8a`](https://github.com/UnknownAlienHuman/roth-chat/commit/3c995183626002965043e38a837346fb290acd8a).
- Live-client status: **NOT RUN**. Static tests and source inspection do not establish runtime behavior.

For chat, taint, or restricted-value changes, read the current pinned chat and security material in the KB before coding. Preserve research provenance in `RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md` and exact third-party file provenance in `ThirdParty/ATTRIBUTIONS.md`.

## Load order and ownership

Read `RothChat.toc` for the authoritative runtime order. In broad terms: bundled libraries; `Util.lua`, `Platform.lua`, `VisualPrimitives.lua`, `ChatText.lua`; `Core.lua`, `CoreListeners.lua`, `CoreDispatch.lua`, `ChatLifecycle.lua`; feature modules; then `Options.lua`.

Shared `NS` helpers in that order are required dependencies. Call them directly; keep optional-client and external-library capability checks at the integration boundary. Use `core:DeferKeyed` with a stable owner/action key and cancel it on teardown.

- `Util.lua`: ordinary-value safety, scheduling, fades, and bounded generic helpers.
- `Platform.lua`: client API/frame adapters, diagnostics, restriction queries, and frame discovery.
- `VisualPrimitives.lua`: applied decoration and its textures.
- `ChatText.lua`: accessible chat timestamp, durable-storage, and copy transformations.
- `Core.lua`: SavedVariables, module lifecycle, configuration/presets, and keyed combat deferral.
- `CoreListeners.lua`: internal event bus.
- `CoreDispatch.lua`: sole message-filter and displayed `AddMessage` dispatch owner.
- `ChatLifecycle.lua`: coalesced native chat lifecycle/update routing.
- `Options.lua`: Blizzard Settings UI.
- Each `Modules/*.lua`: one feature, registered through Core and shared owners.

The standalone StyleOwnership and ControlsOwnership files have been folded into their owning modules and are removed. `Modules/History.lua` is deleted and must remain absent from the TOC. `Modules/Restore.lua` is the sole addon persistence owner. Leave existing `RothChatDB.history` and obsolete profile keys untouched; do not allocate a new History store.

See `ARCHITECTURE.md` for data flow and ownership boundaries.

## Module lifecycle

- `core:IsModuleEnabled(name)` reports configured SavedVariables state.
- `core:IsModuleActive(name)` reports successful runtime activation.
- `Init` runs once and creates durable module resources; `OnEnable` rebuilds registrations after each activation; `OnDisable` stops local work and restores state the module owns.
- Core removes owner listeners, filters, and displayed-message callbacks after disable.
- `OnLogin` is delivered once to active modules; modules enabled later receive it after activation.
- Permanent `hooksecurefunc` hooks must check current active state before acting.
- Migrations and resets must preserve explicit user choices; only missing settings receive defaults.

## Chat filters and displayed messages

`CoreDispatch.lua` is the only owner of these entry points. Do not add per-module Blizzard filters or another `AddMessage` hook system.

Filter callbacks follow this contract:

```lua
return false              -- no change; Blizzard keeps its tuple
return true               -- discard
return false, replacement -- replace visible arg1; Core rebuilds the received tuple
```

Core gates the whole synchronous filter tuple before dispatch, preserves the exact received arity and `nil` positions, and returns the tuple only when visible text changes. Never assume a fixed 14- or 19-argument signature. Module filters may affect visible `arg1`; they do not own opaque sender, routing, line-ID, access-ID, or trailing fields. Filters may be skipped by Blizzard and must not act as guaranteed logs.

Displayed-message callbacks receive only the chat frame, accessible string, and safe RGB values. Unknown trailing AddMessage metadata is discarded. Callbacks must remain optional and should not retain whole tuples. One denied `AddMessage` hook attempt is terminal for that frame lifetime; never retry the same forbidden hook on each layout update.

## Accessibility, lockdown, and retained content

- Gate values with `NS.CanAccessValue` before type-dependent processing or comparison; use `NS.CanAccessObject` before table/frame traversal.
- Keep chat messaging lockdown distinct from ordinary value accessibility. Under lockdown, do not process, compare, format, animate, copy, or retain chat content.
- A restriction transition discards pending content work. Never queue opaque payloads for replay after access returns.
- Do not store raw chat event payloads. Restore may retain only already displayed text after `NS.SanitizeDurableChatText` and must remain bounded.
- Exclude temporary whisper windows from durable Restore identity.
- Native `HistoryKeeper` remains Blizzard-owned. Do not patch, replace, or duplicate it.
- Clear temporary copy/popup content on restriction entry and module disable.
- Do not add retries around denied or forbidden operations.

## Settings and UI behavior

Current appearance presets: **Minimal**, **Obsidian**, and **Ember**. Font and size presets are separate. Keep the configuration model in Core and the UI in `Options.lua`; feature effects belong to the owning module. Preserve all existing module and feature choices across version upgrades.

Controls owns its mouse-wheel wrapper while active and delegates to the captured original while inactive. Controls and Ticker coordinate alpha with CopyOverlay through the visibility event. Restore owns only its bounded SavedVariables buckets and one-shot replay state; Blizzard retains `ScrollingMessageFrame` capacity and fade policy. Do not create parallel owners for these behaviors.

## Performance and validation

- Scheduler/fade update scripts run only while work is pending.
- Coalesce chat lifecycle/layout updates and combat-deferred work; cancel stale keyed jobs.
- Treat `CHAT_FRAME_CLOSED` as terminal for its current coalesced flush; a later native generation may announce a reused frame as ready.
- Keep Restore and Ticker data bounded; do not scan the full database per message. Restore replay is capped by the frame's current `GetMaxLines()` and skips malformed/unknown-version rows.
- Unknown newer persistence schemas remain untouched; suspend their reader/writer until a supported schema is available.
- Reuse one `AddMessage` hook per frame and one dispatcher per event.
- Keep error reporting rate-limited and do not include raw callback errors or chat content in diagnostics.
- Run `python3 scripts/validate.py --lua lua5.1 --lua lua5.4` for the local full gate, plus relevant focused specs. The Actions workflow is manual `workflow_dispatch` only. Report exactly which checks ran; do not imply a whole-suite, CI, or live-client pass from a focused test.

Validation procedure, pinned evidence, and the required in-game matrix are in `docs/VALIDATION.md`. Current live-client status is **NOT RUN**.

## Third-party material

Do not edit or remove third-party notices without rechecking exact provenance. `Util.lua` contains the marked adapted easing helper; `VisualPrimitives.lua` contains marked LS: Glass-derived applied decoration. Their Apache-2.0 scope is distinct from the two MIT original Glass assets and from vendored-library licenses. See `ThirdParty/ATTRIBUTIONS.md` and ship each applicable notice with releases.
