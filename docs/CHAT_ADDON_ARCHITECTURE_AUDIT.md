# Clean-room chat-addon architecture audit

**Audit date:** 2026-08-29  
**Compared projects:** Chattynator, Prat 3.0, Roth Chat 1.1.1  
**Rule:** adopt contracts and failure boundaries; do not copy implementation code.

## Sources

- `Mrrosh/Chattynator`, current `main` snapshot fetched 2026-08-29.
- `Prat-3-0/Prat-3.0`, current `master` snapshot fetched 2026-08-29.
- Blizzard Retail UI source and the project engineering KB remain authoritative for 12.1 contracts.

Commit hashes and the complete file-level evidence map are retained in the generated audit artifact used for this pass. Branch freshness alone does not prove that every competitor path already follows Retail 12.1 restricted-value rules.

## Architectural comparison

### Chattynator

Chattynator owns substantially more of the rendering, scrolling, selection and history surface. That architecture can solve problems after Blizzard formatting because it controls the renderer, but importing one isolated implementation into Roth Chat would also require taking ownership of the surrounding scroll model, layout, edit selection and history lifecycle.

Useful clean-room lessons:

- treat message ingestion, normalized message state and rendering as separate boundaries;
- make dynamic/temporary windows first-class lifecycle objects;
- keep bounded caches and explicit invalidation;
- avoid mixing native and addon-owned history streams.

### Prat 3.0

Prat demonstrates mature feature modularity, explicit enable/disable boundaries and broad chat-event coverage. Some of its techniques originate from the legacy Blizzard chat architecture, including global format mutation and deep chat-frame integration. Those techniques are evidence of required behavior, not automatically safe implementation guidance for Retail 12.1.

Useful clean-room lessons:

- module-local ownership and reversible settings;
- comprehensive incoming/outgoing/channel event matrices;
- conservative coexistence with other chat addons;
- explicit cleanup of filters, hooks, timers and per-window state.

### Roth Chat boundary

Roth Chat intentionally remains a lightweight enhancement of Blizzard chat frames. It must therefore coexist with Blizzard HistoryKeeper and renderer ownership instead of partially behaving like a custom renderer.

## Findings applied in 1.1.2

### P0 — durable Restore window identity

The previous Restore schema keyed persistent text only by numeric chat-frame index. A permanent frame index can be reused after a window is closed or recreated with another name, message-group set or channel set. That can mix text from unrelated window configurations.

The new schema fingerprints:

- permanent frame identity;
- chat-window title;
- configured message groups;
- configured channels.

A fingerprint change replaces the bucket instead of merging histories. Legacy index-only buckets are discarded during the schema migration because they cannot be attributed safely.

### P0 — Blizzard HistoryKeeper coexistence

SimpleMessageFrame supports appending, not prepending. Replaying Roth Chat history into a frame already populated by Blizzard can duplicate lines and place older lines after newer lines.

Roth Chat now:

- retains its bounded bucket for CopyOverlay;
- injects saved lines only when the target frame is empty;
- leaves a non-empty Blizzard-restored frame untouched.

### P1 — mutation-safe dispatch

Callbacks can disable modules or unregister owners while Core is dispatching event listeners, message filters or displayed-message hooks. Removing an array element during a forward iteration can skip the next callback; adding one can execute it prematurely.

Core now uses runtime tombstones and deferred additions:

- removal is effective immediately for the current pass;
- unrelated later callbacks are not skipped;
- additions begin on the next pass;
- priority is preserved;
- the displayed-message hot path does not allocate a full snapshot per line.

### P1 — legacy Cleaner ownership

Removing sender brackets from Blizzard's final localized format cannot be expressed through the supported pre-format message-filter contract. Cleaner therefore mutates `CHAT_*_GET` globals, a legacy technique also seen in older chat addons.

Cleaner is now disabled by default on fresh profiles and remains an explicit compatibility option. Existing SavedVariables choices are preserved.

### P2 — URL event coverage

URL transformation now covers outgoing whispers, Battle.net outgoing whispers, instance chat, raid warnings, communities, emotes, system and achievement messages in addition to the prior event set. Existing hyperlinks and inaccessible values remain no-op paths.

## Rejected adoptions

- No custom renderer or replacement chat-frame stack.
- No copied Prat/Chattynator source or data structures.
- No competitor-derived relaxation of `canaccessvalue` gates.
- No unconditional second history replay over Blizzard HistoryKeeper.
- No permanent frame index treated as durable identity without configuration evidence.

## Remaining live-client gates

- close/recreate a permanent window and verify no cross-window Restore text;
- open/reuse temporary whisper windows and verify no persistent leakage;
- compare login with Blizzard native history enabled and empty/non-empty frames;
- disable modules from callbacks and confirm no skipped or duplicate behavior;
- verify Cleaner opt-in on non-English clients and under forced chat restrictions;
- run URL/timestamp combinations across outgoing whispers, instance chat, communities and raid warnings.
