# Roth Chat engineering guide

## Evidence and target

- selected Retail build: `12.1.5.70688`;
- latest reviewed post-selected source: `12.1.5.70783`;
- interface: `120105`; addon: `1.2.0`;
- Blizzard source: `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, with delta through `297d7aaaa736f346b3e036f38ee088eaf7f8c07f` reviewed;
- engineering KB: `UnknownAlienHuman/wow-addon-engineering-kb@c2a630aa186de401262663cc8568a77988be69df`;
- live-client validation: **NOT RUN**.

Read the pinned chat, security, lifecycle, persistence, performance and release material before changing those boundaries. Other addons are donor evidence, not authority; current decisions are in the two `RESEARCH_*.md` files.

## Runtime owners

`RothChat.toc` is authoritative. Load order is bundled libraries; shared helpers/adapters; Core owners; feature modules; Settings UI/bootstrap.

- `Util.lua`: ordinary-value helpers, bounded scheduling and shared fades.
- `Platform.lua`: client adapters, access/restriction checks, diagnostics and frame discovery.
- `VisualPrimitives.lua`: applied decoration.
- `ChatText.lua`: timestamp, durable-text and copy boundaries.
- `Core.lua`: SavedVariables, module lifecycle, presets and keyed combat deferral.
- `CoreListeners.lua`: mutation-safe internal event bus.
- `CoreDispatch.lua`: sole message-filter and displayed-message dispatch owner.
- `ChatLifecycle.lua`: coalesced native chat-frame lifecycle owner.
- `Modules/*.lua`: one feature each; no competing global dispatch systems.
- `Options.lua`: sole Settings category/control builder.
- `OptionsBootstrap.lua`: bounded `Blizzard_Settings` availability handshake only.

`Modules/History.lua`, `StyleOwnership.lua` and `ControlsOwnership.lua` must remain absent. Restore is the sole addon persistence owner. Leave legacy `RothChatDB.history` and obsolete keys untouched.

## Lifecycle and ownership

- Configured enablement and active runtime state are different; hot callbacks use `IsModuleActive` or an established active guard.
- `Init` runs once; `OnEnable` rebuilds registrations; `OnDisable` stops work and restores only state still owned by the module.
- Core removes owner listeners, filters and displayed-message callbacks after disable.
- Permanent post-hooks recheck active state and are attempted once; denied hooks are not retried in update loops.
- Use stable keyed jobs and cancel stale work on teardown.
- Defaults apply only to missing settings; migrations preserve explicit choices.

## Chat and access boundaries

`CoreDispatch.lua` is the only owner of Blizzard message filters and per-frame `AddMessage` observers.

```lua
return false              -- unchanged
return true               -- discard
return false, replacement -- replace visible arg1 only
```

Preserve exact tuple arity and `nil` positions. Never assume 14 or 19 fields. Do not retain raw tuples, opaque routing fields, raw exceptions or inaccessible values.

Displayed-message callbacks receive only `(frame, accessibleText, safeR, safeG, safeB)`. Listener/filter/observer diagnostics use stable ordinary registration identities.

Call `CanAccessValue` before type-dependent work and `CanAccessObject` before traversal. Chat messaging lockdown is separate: do not process, compare, format, animate, copy or retain content under restriction. Restriction entry discards pending content; never replay it after access returns.

## Presentation and persistence

- Controls restores wheel/clipping only while values still match its writes.
- Ticker owns alpha/mouse state for one active permanent primary frame and yields to later writes/fades.
- CopyOverlay owns only its active fade and matching last alpha write; later foreign state survives teardown.
- Alerts requests native flashes but never owns Blizzard alert state, animation or sound.
- Restore owns only bounded durable buckets and one-shot replay; it never changes native capacity or fade policy.
- Blizzard `HistoryKeeper`, temporary whisper windows and rendered history remain Blizzard-owned.

## Validation and release

Run:

```sh
python3 scripts/validate.py --lua lua5.1 --lua lua5.4
python3 scripts/package.py /tmp/RothChat-a.zip
python3 scripts/package.py /tmp/RothChat-b.zip
cmp /tmp/RothChat-a.zip /tmp/RothChat-b.zip
python3 scripts/package.py --verify /tmp/RothChat-a.zip
```

`scripts/project.py` is the sole TOC metadata and recursive TOC/XML graph owner. Do not duplicate that parser. `scripts/package.py` builds one deterministic `RothChat/` root from the runtime graph, retained assets and required release notices; tests, scripts, workflows, research and agent files do not ship.

The workflow runs on PRs and pushes to `main`. Report the exact commit/tree, Lua counts, spec counts, package file count and SHA-256. A green workflow is not a Retail client pass. The required live matrix and release gate are in `docs/VALIDATION.md`.

## Third-party boundary

Do not remove or merge third-party notices without rechecking exact provenance. LS: Glass-derived assets/adaptations are Apache-2.0; original Glass assets are MIT; vendored libraries retain their own notices. Every release archive must include `ThirdParty/ATTRIBUTIONS.md`, `ThirdParty/LS_GLASS_LICENSE.txt` and `ThirdParty/GLASS_LICENSE.txt`.
