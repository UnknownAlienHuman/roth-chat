# Roth Chat Retail 12.1 migration record

**Addon version:** `1.1.1` plus unreleased 2026-08-29 audit changes  
**Target:** Retail `12.1.0` / Interface `120100`  
**Verified Blizzard source:** build `12.1.0.69497`, `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`  
**Engineering baseline:** `UnknownAlienHuman/wow-addon-engineering-kb`, reviewed 2026-08-29

## Scope

Roth Chat does not consume the new aura APIs. Its 12.1 work is concentrated in chat/security contracts, module and frame lifecycle, persistence ownership, combat-safe UI mutation, licensing provenance and release validation.

Version `1.1.0` corrected the fixed-width chat-filter adapter. Version `1.1.1` hardened runtime module/frame ownership. The 2026-08-29 audit adds a structured durable-text boundary after comparing current/pinned Blizzard source with Chattynator, Prat, LS: Glass and original Glass implementation evidence.

## Message-filter contract

The dispatcher is variadic and count-preserving.

```text
incoming tuple -> PackValues(n + values)
               -> visible arg1 accessibility gate
               -> ordered module callbacks
               -> no change: return false
               -> discard: return true
               -> arg1 change: return false + complete packed tuple
```

Properties:

1. The implementation mirrors the arity actually received instead of assuming 14 or 19 fields.
2. Interior and trailing `nil` positions are retained through an explicit `n` field.
3. Module callbacks can only discard or propose a replacement visible `arg1`.
4. Later Roth Chat filters see the latest transformed `arg1`.
5. A no-op does not activate Blizzard's replacement-tuple path.
6. A callback error degrades to no transformation and does not corrupt dispatcher state.
7. Removing the last owner unregisters the single Blizzard dispatcher for that event.

## Runtime lifecycle hardening

Configured enablement and actual activation are tracked separately.

The `1.1.1` lifecycle provides:

- separate configured and runtime-active state;
- one-shot `Init`;
- idempotent `OnEnable` / `OnDisable` transitions;
- one-time `OnLogin`, including late activation after login;
- teardown callbacks that already observe the module as inactive;
- defensive owner cleanup for event-bus listeners, message filters and `AddMessage` callbacks;
- no feature-module initialization when the whole addon profile is disabled;
- exact deferred-argument arity, including `nil` positions.

## Accessibility boundary

Retail 12.1 requires operational gating by current accessibility, not only by whether a value is labelled secret.

`NS.CanAccessValue` is applied before chat text is compared, formatted, linked, copied, animated or retained. This covers the core filter and displayed-message adapters, Timestamps, UrlCopy, Ticker, Restore, CopyOverlay and Alerts.

Callbacks remain optional. No feature treats a filter or displayed-message callback as a guaranteed audit stream or state machine.

## Structured durable-text boundary

The audit found that Roth Chat previously persisted its rendered colored timestamp as part of the message string. Restore copy/export could then prepend a second timestamp, and `copyIncludeTimestamps=false` could not reliably remove timestamps from every fallback source.

`ChatText.lua` now owns clean-room transformations over already accessible displayed text:

- Roth timestamp formatting and recognition;
- timestamp-prefix removal;
- stable color normalization;
- replacement of session-only account-name, BNet and censored/report-censored handles;
- copy-surface markup normalization;
- optional removal of plain leading timestamps from every line.

It is not a declassification API and does not receive raw chat-event tuples.

## Restore schema v2

New rows are stored as:

```text
{ timestamp, timestampFreeDurableText, r, g, b, 2 }
```

### Ingest

```text
already displayed AddMessage text
-> core accessibility gate
-> permanent-frame identity check
-> bounded truncation
-> durable session-handle sanitation
-> remove Roth rendered timestamp
-> append bounded schema-v2 row
```

### Replay

- Timestamps active: reconstruct one colored minute-resolution timestamp from metadata.
- Timestamps inactive: replay timestamp-free durable text.
- `__rothRestoring` prevents Restore from re-ingesting its own replay.
- Temporary whisper frames remain excluded because Blizzard reuses those runtime surfaces for different correspondents.

### Copy/export

- `copyIncludeTimestamps=true`: Restore adds exactly one plain second-resolution timestamp.
- `copyIncludeTimestamps=false`: no leading Roth/plain timestamp survives Restore, `GetMessageInfo` or FontString fallback normalization.
- Ordinary item/spell hyperlinks remain in durable replay data and are flattened only for the copy EditBox.

### Legacy compatibility

Schema-v1 rows remain readable. Rows without marker `2` are normalized lazily by removing Roth's old colored timestamp before replay/export. There is no unbounded destructive login-time migration.

## Module findings and corrections

### Controls and ChatBar

- Rebuilt Controls lifecycle listeners after runtime re-enable.
- Replaced additive mouse-wheel hooking with an owned script so Blizzard and Roth Chat do not process the same gesture twice.
- Preserved and delegated to the captured original wheel script while Controls is inactive.
- Added explicit accessory-hover unregister support.
- Re-emitted chat-frame readiness when Controls is enabled after accessory modules.
- Transferred ChatBar ownership when the selected dock frame changes.

### Ticker and CopyOverlay

- Replaced unbounded/replay-prone behavior with a bounded indexed queue.
- Accepted only messages received while the primary chat frame is hidden.
- Reset fade, hold and animation state deterministically across cancellation and module/primary-frame changes.
- Changed CopyOverlay close ordering so its snapshot is restored first and Controls/Ticker then determine the authoritative final alpha.
- Applied copy timestamp inclusion consistently across Restore and frame fallbacks.

### Restore

- Persisted accessible, sanitized text only for permanent indexed chat windows.
- Excluded temporary whisper frames.
- Snapshotted Blizzard `fading`, `timeVisible` and `fadeDuration` values and restored them on disable, including an explicit `false` fading state.
- Applied fade ownership to chat frames created after login.
- Guaranteed restore flags are cleared after a protected restoration loop, including an error path.

### Style, Resize and Dock

- Corrected the `FCFTab_UpdateAlpha` post-hook argument from tab frame to chat frame.
- Removed recursive/invalid tab positioning and the invalid empty-atlas call.
- Added runtime-active guards to permanent Style hooks.
- Cleared stale CopyOverlay suppression state when Style is disabled.
- Made Resize cancel and defer one continuation when combat begins during snap animation.
- Cancelled frame-specific resize work on close/disable.
- Made Dock and Style coalesce layout work and preserve one continuation through combat.

### UrlCopy, Cleaner and Alerts

- Preserved balanced closing parentheses inside URLs while stripping unmatched sentence closers.
- Preserved existing Blizzard hyperlinks during URL transformation.
- Preserved the client's localized Cleaner format strings in normal mode.
- Limited compact tags to the explicit `cleanerShorten` setting and restored snapshots conservatively.
- Applied accessibility handling to whisper line IDs and cleared active tab flashes on Alerts disable.

### Settings

- Derived module reset defaults from `module.defaultEnabled`.
- Activated or deactivated only the target module for a module checkbox.
- Routed smooth-scroll and immersion changes to the actual owning modules.

## External implementation review

Pinned evidence and adoption decisions are recorded in `RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md`.

### Adopted concepts

- Chattynator snapshot: timestamp metadata separated from rendered text; bounded history; durable session-handle sanitation; copy derived from structured records.
- Prat: explicit feature-module lifecycle and bounded optional history features.
- LS: Glass: one active smoother, dirty-layout coalescing and explicit attach/release ownership when an addon owns a renderer.

### Rejected architecture

- full `ChatFrameUtil` replacement;
- copied Blizzard message handler;
- unregistering Blizzard chat-frame events;
- custom full renderer while Blizzard rendering remains active;
- command-history/edit-box synchronization;
- raw event-payload persistence;
- third-party source transplantation.

The reviewed current Prat handler still forwards only `arg1` through `arg14`, demonstrating copied-handler contract drift. The reviewed LS: Glass project is retired for Midnight and targets Interface `110207`; it is historical evidence only.

## Third-party provenance correction

Exact Git blob comparison found two distinct Glass sources in Roth Chat.

### LS: Glass / Apache-2.0

Exact matches at `ls-/ls_Glass@2df600e7b3d6d9eaf8dd29128377cd45ba1d9f26`:

- `Assets/border-highlight.TGA` — `ae4d9aa4dd50ea16790009c986f24275c1c6515a`;
- `Assets/border.TGA` — `8c5aada40e24c107dfbd09a99c1c9748aa2a71d3`;
- `Assets/icons.TGA` — `1206ddcedff0a8cb191dc8094a4ecdf561cca009`;
- `Assets/scroll-buttons.TGA` — `43be3a6b0a742a52f40309a64eb987a33cc13ab8`.

`Util.lua` also contains explicitly marked modified/adapted helper material. `ThirdParty/LS_GLASS_LICENSE.txt` now contains the applicable Apache-2.0 license.

### Original Glass / MIT

Exact matches at `mixxorz/Glass@d7d5fd6865b00c32ccfa40275b9924630e70b143`:

- `Assets/overlayMask.tga` — `48f0f1319903cdd1d7f1db43479984a30493c55e`;
- `Assets/snapToBottomIcon.tga` — `c3397a06ee3c6635de5ecbba6927fb13a256b145`.

The existing `ThirdParty/GLASS_LICENSE.txt` remains applicable to those MIT assets only. `ThirdParty/ATTRIBUTIONS.md` records both projects, commits, paths and exact blob hashes. Roth Chat's `LICENSE.md` now explicitly excludes attributed third-party material from its repository-wide MIT grant.

## Source-contract discrepancy to recheck

The 12.1 API-change record states that the chat filter bug was fixed from 14 to all 19 parameters. The verified `12.1.0.69497` source snapshot still contains a Mainline `ChatFrameOverrides.lua` path that destructures more fields but calls `ChatFrameUtil.ProcessMessageEventFilters` with `arg1` through `arg14`.

This record does **not** assert a confirmed live-client regression. Source export timing, another dispatch path or runtime glue may account for the discrepancy. Roth Chat preserves whatever tuple the client supplies. The engineering KB tracks the mismatch as `WOWUI-2026-011`.

## Automated validation definition

`.github/workflows/validate.yml` is configured for push, pull request and manual dispatch and performs:

- Lua syntax parsing for every `.lua` file;
- `tests/core_chat_filter_spec.lua`;
- `tests/core_module_lifecycle_spec.lua`;
- `tests/chat_text_spec.lua`;
- `tests/timestamps_spec.lua`;
- `tests/url_copy_spec.lua`;
- `tests/cleaner_spec.lua`;
- `tests/restore_spec.lua`;
- exact TOC checks for Interface `120100`, author `Neomorph` and version `1.1.1`;
- existence checks for every active TOC path.

Local Lua 5.4 execution has passed the new `chat_text_spec`, `timestamps_spec` and expanded `restore_spec`. A successful GitHub Actions run for the exact audit head is still required before merge/release; the old successful run for the prior `1.1.0` commit is not inherited as evidence.

## Retail runtime matrix

Static checks are necessary but not sufficient. The detailed actionable list is maintained in [`TODO.md`](TODO.md).

Required areas include:

- startup, upgrade, reload and logout/login persistence;
- schema-v1 and schema-v2 replay/copy with timestamps enabled and disabled;
- BNet/account-name/censored-link sanitation without reading inaccessible values;
- runtime module disable/re-enable before and after login;
- complete chat event and URL/timestamp combinations;
- forced chat and challenge-mode restrictions;
- combat interruption of Resize, Dock and Style work;
- permanent, temporary, docked and reused chat-frame lifecycle;
- Controls mouse-wheel ownership;
- Ticker hidden-state-only delivery and fade cancellation;
- CopyOverlay/Controls/Ticker alpha arbitration;
- localized Cleaner behavior;
- zero repeating taint, secret-value or forbidden-operation errors.

## Open engineering item

Hot-path error reporting remains unbounded: `NS.SafeCall` and the core multi-return filter reporter can repeat the same stack for every message. This must be rate-limited/deduplicated or explicitly deferred to the next patch after live validation; it is not silently considered complete.

## Release gate

- [ ] Successful validation workflow for the exact audit/release commit.
- [ ] No Lua errors with only Roth Chat enabled.
- [ ] No repeating taint/secret/forbidden errors in combat or restricted chat.
- [ ] Runtime matrix results and tested build recorded here.
- [ ] Package includes both applicable Glass licenses and exact attribution.
- [ ] Package reviewed for intended runtime files only; research/agent/TODO/workflow files excluded unless intentionally shipped.

## Runtime result

**Status:** `AUDIT_IMPLEMENTATION_COMPLETE; EXACT_HEAD_CI_PENDING; LIVE_CLIENT_TEST_PENDING`  
**Last updated:** 2026-08-29
