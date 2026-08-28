# Roth Chat Retail 12.1 migration record

**Addon version:** `1.1.1`  
**Target:** Retail `12.1.0` / Interface `120100`  
**Verified Blizzard source:** build `12.1.0.69497`, `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`  
**Engineering baseline:** `UnknownAlienHuman/wow-addon-engineering-kb`, reviewed 2026-08-28

## Scope

Roth Chat does not consume the new aura APIs. Its 12.1 work is concentrated in chat/security contracts, module and frame lifecycle, persistence ownership, combat-safe UI mutation and release validation.

Version `1.1.0` corrected the fixed-width chat-filter adapter. Version `1.1.1` is the second runtime-hardening pass over every active module.

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

The second pass found that configured enablement and actual activation were conflated. Several modules could lose listeners after re-enable, retain post-hook callbacks after disable, miss `OnLogin` when enabled late or continue acting through permanent hooks while inactive.

The `1.1.1` lifecycle now provides:

- separate configured and runtime-active state;
- one-shot `Init`;
- idempotent `OnEnable` / `OnDisable` transitions;
- one-time `OnLogin`, including late activation after login;
- defensive owner cleanup for event-bus listeners, message filters and `AddMessage` callbacks;
- no feature-module initialization when the whole addon profile is disabled;
- exact deferred-argument arity, including `nil` positions.

## Accessibility boundary

Retail 12.1 requires operational gating by current accessibility, not only by whether a value is labelled secret.

`1.1.1` adds a `canaccessvalue`-compatible boundary and applies it before chat text is compared, formatted, linked, copied, animated or retained. This covers the core filter and displayed-message adapters, Timestamps, UrlCopy, Ticker, Restore, CopyOverlay and Alerts.

Callbacks remain optional. No feature treats a filter or displayed-message callback as a guaranteed audit stream or state machine.

## Module findings and corrections

### Controls and ChatBar

- Rebuilt Controls lifecycle listeners after runtime re-enable.
- Replaced additive mouse-wheel hooking with an owned script so Blizzard and Roth Chat do not process the same gesture twice.
- Preserved and delegated to the captured original wheel script while Controls is inactive.
- Added explicit accessory-hover unregister support.
- Transferred ChatBar ownership when the selected dock frame changes.

### Ticker and CopyOverlay

- Replaced unbounded/replay-prone behavior with a bounded indexed queue.
- Accepted only messages received while the primary chat frame is hidden.
- Reset fade, hold and animation state deterministically across cancellation and module/primary-frame changes.
- Changed CopyOverlay close ordering so its snapshot is restored first and Controls/Ticker then determine the authoritative final alpha.

### Restore

- Persisted accessible text only for permanent indexed chat windows.
- Excluded temporary whisper frames because Blizzard reuses those runtime surfaces for different correspondents.
- Snapshotted Blizzard `fading`, `timeVisible` and `fadeDuration` values before changing them and restored prior values on disable.
- Applied fade ownership to chat frames created after login.
- Guaranteed restore flags are cleared after a protected restoration loop, including an error path.

### Style, Resize and Dock

- Corrected the `FCFTab_UpdateAlpha` post-hook argument from tab frame to chat frame.
- Removed recursive/invalid tab positioning and the invalid empty-atlas call.
- Added runtime-active guards to permanent Style hooks.
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

## SavedVariables migration

Version migrations initialize absent legacy fields, infer missing preset metadata and record the new addon version. They do not flip an explicitly stored feature or module boolean.

No destructive schema migration is required from `1.1.0` to `1.1.1`.

## Source-contract discrepancy to recheck

The 12.1 API-change record states that the chat filter bug was fixed from 14 to all 19 parameters. The verified `12.1.0.69497` source snapshot still contains a Mainline `ChatFrameOverrides.lua` path that destructures more fields but calls `ChatFrameUtil.ProcessMessageEventFilters` with `arg1` through `arg14`.

This record does **not** assert a confirmed live-client regression. Source export timing, another dispatch path or runtime glue may account for the discrepancy. Roth Chat therefore avoids depending on either width and preserves whatever tuple the client supplies. The engineering KB tracks the mismatch as `WOWUI-2026-011`.

## Automated validation definition

`.github/workflows/validate.yml` is configured to perform:

- Lua syntax parsing for every `.lua` file;
- `tests/core_chat_filter_spec.lua`;
- `tests/core_module_lifecycle_spec.lua`;
- `tests/url_copy_spec.lua`;
- `tests/cleaner_spec.lua`;
- exact TOC checks for Interface `120100`, author `Neomorph` and version `1.1.1`;
- existence checks for every active TOC path.

Coverage includes complete 19-field tuples with an interior `nil`, no-op/transform/discard/unregister paths, module owner cleanup, late activation after login, profile-disabled startup, balanced URL punctuation, existing hyperlinks, inaccessible chat text and Russian localized Cleaner formats.

**Current branch status:** the validation workflow is defined, but a successful run for the exact `1.1.1` head must be recorded before merge/release. Do not inherit the successful `1.1.0` result as evidence for this code.

## Retail runtime matrix

Static checks are necessary but not sufficient. The detailed actionable list is maintained in [`TODO.md`](TODO.md).

### Required areas

- startup, upgrade, reload and logout/login persistence;
- runtime module disable/re-enable before and after login;
- complete chat event and URL/timestamp combinations;
- forced chat and challenge-mode restrictions;
- combat interruption of Resize, Dock and Style work;
- permanent, temporary, docked and reused chat-frame lifecycle;
- Controls mouse-wheel ownership;
- Ticker hidden-state-only delivery and fade cancellation;
- CopyOverlay/Controls/Ticker alpha arbitration;
- Restore fade restoration and temporary-frame exclusion;
- localized Cleaner behavior;
- zero repeating taint, secret-value or forbidden-operation errors.

## Release gate

- [ ] Successful validation workflow for the exact release commit.
- [ ] No Lua errors with only Roth Chat enabled.
- [ ] No repeating taint/secret/forbidden errors in combat or restricted chat.
- [ ] Runtime matrix results and tested build recorded here.
- [ ] Package reviewed for intended runtime files, documentation and licenses only.

## Runtime result

**Status:** `IMPLEMENTATION_REVIEWED; CURRENT_HEAD_CI_PENDING; LIVE_CLIENT_TEST_PENDING`  
**Last updated:** 2026-08-28
