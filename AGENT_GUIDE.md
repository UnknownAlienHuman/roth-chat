# Roth Chat engineering guide

## Target and evidence

- Retail build: `12.1.5.70688`; TOC interface: `120105`; addon version: `1.2.0`.
- Blizzard UI source: [`Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`](https://github.com/Gethe/wow-ui-source/commit/d07eb00237d8891f153215db98a5df880a26cfe5), checked 2026-11-02.
- Engineering KB: [`wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/commit/b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83).
- Live-client validation: **NOT RUN**. Static tests and source inspection do not prove in-client behavior.

Read the pinned chat, security, lifecycle and performance material before changing restricted-value, taint, chat-frame or persistence boundaries. Preserve implementation provenance in `RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md` and file-level third-party provenance in `ThirdParty/ATTRIBUTIONS.md`.

## Load order and owners

`RothChat.toc` is authoritative. The runtime order is: bundled libraries; shared helpers/adapters; Core owners; feature modules; `Options.lua`.

- `Util.lua`: ordinary-value helpers, bounded scheduling and shared fades.
- `Platform.lua`: client adapters, access/restriction checks, diagnostics and frame discovery.
- `VisualPrimitives.lua`: applied decoration.
- `ChatText.lua`: timestamp, durable-text and copy boundaries.
- `Core.lua`: SavedVariables, module lifecycle, presets and keyed combat deferral.
- `CoreListeners.lua`: owner-aware internal event bus.
- `CoreDispatch.lua`: sole message-filter and displayed-message dispatch owner.
- `ChatLifecycle.lua`: coalesced native chat-frame lifecycle routing.
- `Modules/*.lua`: one feature each; no competing global dispatch systems.
- `Options.lua`: Blizzard Settings UI only.

`Modules/History.lua`, `StyleOwnership.lua` and `ControlsOwnership.lua` must remain absent. Restore is the sole addon persistence owner. Leave legacy `RothChatDB.history` and obsolete keys untouched; do not allocate replacement stores for removed features.

## Module lifecycle

- Configured state and active runtime state are different. Hot callbacks use `core:IsModuleActive(name)` or an equivalent active guard.
- `Init` runs once. `OnEnable` rebuilds registrations. `OnDisable` stops local work and restores only state still owned by the module.
- Core removes owner listeners, filters and displayed-message callbacks after disable.
- `OnLogin` is delivered once to active modules; later activation receives it after successful enable.
- Permanent post-hooks must recheck current active state.
- Use stable `core:DeferKeyed` keys and cancel stale work on teardown.
- Defaults apply only to missing settings; migrations preserve explicit user choices.

## Chat boundaries

`CoreDispatch.lua` is the only owner of Blizzard message filters and per-frame `AddMessage` observers.

Filter callback contract:

```lua
return false              -- unchanged
return true               -- discard
return false, replacement -- replace visible arg1 only
```

Core gates the complete synchronous tuple, preserves exact arity and `nil` positions, and returns it only when visible text changes. Never assume a fixed 14- or 19-field shape. Do not retain raw event tuples or opaque routing metadata.

Displayed-message callbacks receive only `(frame, accessibleText, safeR, safeG, safeB)`. A denied `AddMessage` hook attempt is terminal for that frame lifetime. Callback errors use bounded symbolic diagnostics; raw exceptions and chat content never enter reports or retained state.

## Accessibility and restrictions

- Call `NS.CanAccessValue` before type-dependent work or comparison; call `NS.CanAccessObject` before traversal.
- Chat messaging lockdown is distinct from ordinary value accessibility.
- Under lockdown, do not process, compare, format, animate, copy or retain chat content.
- Restriction entry discards pending content work. Never replay pre-restriction payloads after access returns.
- Restore persists only already displayed, sanitized and bounded text for permanent windows.
- Temporary whisper windows and Blizzard `HistoryKeeper` remain Blizzard-owned.
- Copy overlays and popups clear temporary text on restriction entry and disable.
- Do not retry denied or forbidden operations.

## Presentation ownership

Controls owns its wheel wrapper and restores wheel/clipping only while values still match its writes. Ticker owns immersion alpha/mouse state for one active permanent primary frame and restores only while its fade or last writes still own those properties. CopyOverlay emits visibility changes so active owners recompute final alpha. Restore never changes native fade policy or `SetMaxLines()`.

Alerts is a narrow policy extension, not a second animation owner. Blizzard owns whisper audio, tab alert state, animation and teardown. Alerts consults `ChatFrameUtil.IsTabAlerting`, requests `FCF_StartAlertFlash` only for ordinary messages on inactive docked tabs not already alerting, and never stops native flashes during teardown.

## Performance and validation

- Scheduler and fade update scripts run only while work exists.
- Coalesce layout/lifecycle work and cancel replaced jobs.
- `CHAT_FRAME_CLOSED` is terminal for the current coalesced flush.
- Ticker queue/text and Restore retention/replay remain bounded.
- Unknown newer persistence schemas remain untouched and suspended.
- Reuse one dispatcher per event and one `AddMessage` post-hook per frame.
- Do not claim performance improvement without measurement.

Run the full gate with:

```sh
python3 scripts/validate.py --lua lua5.1 --lua lua5.4
```

`.github/workflows/validate.yml` runs the same gate for pull requests and pushes to `main`, and also supports manual dispatch. Report the exact commit and checks that ran. Focused specs are not a full-suite pass; CI is not live-client validation.

The required client matrix and release evidence are in `docs/VALIDATION.md`.

## Third-party boundary

Do not edit or remove third-party notices without rechecking exact provenance. `Util.lua` contains a marked LS: Glass easing adaptation; `VisualPrimitives.lua` contains marked LS: Glass-derived presentation code. Apache-2.0, original Glass MIT assets and vendored-library notices remain separate and must ship with releases.
