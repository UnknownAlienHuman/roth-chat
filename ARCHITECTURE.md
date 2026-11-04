# Roth Chat architecture

Roth Chat is an additive adapter around Blizzard's native chat stack. Blizzard remains the owner of chat event production, routing, message formatting, live `ScrollingMessageFrame` history, whisper audio, tab-alert state and native frame lifecycle. Roth Chat adds bounded feature modules without replacing those owners.

## Runtime owners

| File | Responsibility |
|---|---|
| `Util.lua` | Ordinary-value helpers, bounded keyed scheduling and owner-aware fades. |
| `Platform.lua` | Current-client adapters, diagnostics, access/restriction checks and frame discovery. |
| `VisualPrimitives.lua` | Applied glass decoration and cleanup. |
| `ChatText.lua` | Accessible timestamp, durable-text and copy transformations. |
| `Core.lua` | SavedVariables, module lifecycle, defaults/presets and combat deferral. |
| `CoreListeners.lua` | Mutation-safe owner-aware internal event bus. |
| `CoreDispatch.lua` | Sole message-filter and displayed-message callback dispatcher. |
| `ChatLifecycle.lua` | Coalesced native chat-frame lifecycle routing. |
| `Modules/*.lua` | One independently togglable feature each. |
| `Options.lua` | Blizzard Settings controls only. |

`Modules/History.lua`, `StyleOwnership.lua` and `ControlsOwnership.lua` are removed. Restore is the sole addon persistence owner; legacy `RothChatDB.history` data is left untouched.

## Startup and lifecycle

1. TOC order loads libraries, shared owners, Core, modules and Settings.
2. Modules register definitions. Core applies defaults only to missing settings.
3. Successful `OnEnable` marks a module active; configured state alone is not runtime state.
4. `OnDisable` stops local work and restores only state still owned by that module.
5. Core removes owner listeners, filters and displayed-message callbacks.
6. Native chat updates are coalesced into next-frame lifecycle work.

Permanent post-hooks recheck active state. Combat work uses stable owner/action keys and stale continuations are cancelled.

## Message flow

### Synchronous filters

Core registers one dispatcher per Blizzard message event. It gates the entire received tuple, preserves exact arity and interior/trailing `nil` values, and calls priority-ordered module callbacks.

```lua
return false              -- unchanged
return true               -- discard
return false, replacement -- replace arg1 only
```

Unchanged tuples stay Blizzard-owned. Modules do not retain raw event tuples, routing handles, line IDs or access IDs. Callback failures are isolated per registration, rate-limited and reported only through bounded symbolic labels.

### Displayed-message observers

Core installs at most one `AddMessage` post-hook per active frame and forwards only `(frame, accessibleText, safeR, safeG, safeB)`. Unknown trailing metadata never enters module state. A denied hook attempt is terminal for that frame lifetime.

Restore, Ticker and Alerts consume this optional feed. They must tolerate callbacks being unavailable under client restrictions.

## Persistence

`ChatText.lua` sanitizes durable text before retention. Session-only account, Battle.net, Discord routing and censored-message handles are flattened or removed while ordinary stable links remain.

Restore stores bounded records only for permanent indexed windows. Bucket identity uses the current permanent-window configuration fingerprint. Temporary whisper frames are excluded. Unknown newer database versions suspend reading/writing without mutation; unknown row versions are skipped. Replay occurs only into an empty native frame, is capped by current `GetMaxLines()`, and never changes native capacity or fade properties.

Blizzard `HistoryKeeper` remains untouched.

## Frame lifecycle

`ChatLifecycle.lua` observes stable native update events and `FCF_*` post-hooks, then emits coalesced READY/CLOSED/LAYOUT signals. A close is terminal for the current flush even if Blizzard's fixed pool still reports the slot active; reuse is announced only by a later native generation.

Subscription mutations and renames invalidate Restore identity synchronously. Incomplete native invalidation hooks disable fingerprint caching rather than authorizing stale identity reuse.

## Presentation ownership

- Style owns only its applied decoration and restores matching snapshots.
- Controls owns its wheel wrapper and hover/clipping writes while active.
- Ticker owns immersion alpha/mouse state for one active permanent primary frame. Owner-aware fades and last-write checks preserve later foreign changes during teardown.
- CopyOverlay owns only its modal presentation and emits visibility changes so active owners recompute final alpha.
- Cleaner relinquishes formatting changed by another owner.
- Alerts does not own alert animation. It consults `ChatFrameUtil.IsTabAlerting` and requests the native `FCF_StartAlertFlash` only for ordinary displayed messages on inactive docked tabs that are not already alerting. Blizzard retains whisper audio, state, animation and teardown.

Restriction entry discards pending content, stops local presentation and releases feature-owned state. Pre-restriction content is never replayed after access returns.

## Bounded work

- Scheduler and fade drivers remove `OnUpdate` when idle.
- Ticker uses a fixed 100-slot ring and caps retained preview text at 1,024 UTF-8 characters plus its marker.
- Restore retention and replay are bounded.
- Lifecycle and combat work are coalesced by stable keys.
- Registries compact after removals rather than during active iteration.
- No performance claim is made without measurement.

## Settings and external code

Minimal, Obsidian and Ember presets persist through Core. Font/size presets remain separate. Settings UI does not own feature behavior.

Exact third-party provenance is recorded in `ThirdParty/ATTRIBUTIONS.md`; Apache-2.0 LS: Glass material, original Glass MIT assets and vendored-library notices remain separate.

## Validation

The target is Retail `12.1.5.70688`, Interface `120105`, addon `1.2.0`. Pull requests and pushes to `main` run the complete Lua 5.1/Lua 5.4 validator. Live-client status remains **NOT RUN**. See `docs/VALIDATION.md` for the exact gate and runtime matrix.
