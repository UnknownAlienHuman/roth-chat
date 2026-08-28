# Roth Chat Retail 12.1 migration record

**Addon version:** `1.1.0`  
**Target:** Retail `12.1.0` / Interface `120100`  
**Verified Blizzard source:** build `12.1.0.69497`, `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`  
**Engineering baseline:** `UnknownAlienHuman/wow-addon-engineering-kb`, reviewed 2026-08-27

## Scope

Roth Chat does not consume the new aura APIs, so the 12.1 migration is concentrated in the chat/security contract, metadata and release validation.

The critical defect in `1.0.1` was a fixed-width dispatcher:

- `SafeCallMulti` captured only 14 callback returns;
- the central message filter accepted and returned only `arg1` through `arg14`;
- any additional fields supplied by Blizzard could be dropped on a transformed path;
- every no-op still returned a full addon-generated tuple, unnecessarily widening the taint surface.

## Implemented contract

The `1.1.0` dispatcher is variadic and count-preserving.

```text
incoming tuple -> PackValues(n + values)
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
7. Removing the last module filter unregisters the single Blizzard dispatcher for that event.

## SavedVariables migration correction

Before `1.1.0`, any addon version change force-enabled several features and modules. Raising the version for 12.1 would therefore override stored user choices.

The migration now:

- initializes only absent legacy fields;
- keeps History disabled only when its flag is missing;
- infers missing preset metadata;
- records the new version;
- never flips an explicitly stored feature/module boolean.

## Source-contract discrepancy to recheck

The 12.1 API-change record states that the chat filter bug was fixed from 14 to all 19 parameters. The verified `12.1.0.69497` source snapshot still contains a Mainline `ChatFrameOverrides.lua` path that destructures more fields but calls `ChatFrameUtil.ProcessMessageEventFilters` with `arg1` through `arg14`.

This record does **not** assert a confirmed live-client regression. Source export timing, another dispatch path or runtime glue may account for the discrepancy. Roth Chat therefore avoids depending on either width and preserves whatever tuple the client supplies. The engineering KB tracks the mismatch for runtime verification.

## Automated validation

`.github/workflows/validate.yml` performs:

- Lua syntax parsing for every `.lua` file;
- `tests/core_chat_filter_spec.lua`;
- exact TOC checks for Interface `120100`, author `Neomorph` and version `1.1.0`;
- existence checks for every active TOC path.

The contract test covers:

- a 19-field payload;
- an interior `nil` value;
- no-op behavior returning only `false`;
- replacement behavior returning discard plus all 19 fields;
- chained filters seeing transformed `arg1`;
- discard behavior;
- last-owner unregister cleanup.

The branch workflow passed all static checks before review. Any later code change must produce another successful run before merge or release.

## Retail runtime matrix

Static checks are necessary but not sufficient. Do not mark the release runtime-verified until these are completed on the current Retail client.

### Startup and persistence

- [ ] Fresh login with an empty `RothChatDB`.
- [ ] Upgrade from a `1.0.1` profile with several modules disabled; choices remain disabled.
- [ ] `/reload` with no duplicate filters, hooks, ticker lines or restored messages.
- [ ] Logout/login with bounded Restore data and correct per-window ownership.

### Chat events

- [ ] Say, yell, emote and text emote.
- [ ] Party/leader, raid/leader/warning and instance/leader.
- [ ] Guild and officer.
- [ ] Whisper, whisper inform, `/r`, Battle.net whisper and Battle.net whisper inform.
- [ ] Numbered public channels and channel notices.
- [ ] System, achievement and guild-achievement messages.
- [ ] Messages with no URL/timestamp transformation.
- [ ] Messages transformed by URL copy, timestamps and both modules together.
- [ ] Sender, channel routing, clickable names, line IDs and report/context-menu behavior remain intact.

### Restrictions and combat

- [ ] Forced addon chat restrictions.
- [ ] Forced challenge-mode restrictions.
- [ ] Transition into and out of restriction state without reload.
- [ ] Combat entry/exit while settings or deferred layout work is pending.
- [ ] No secret-value arithmetic, comparison, concatenation or repeated error loop.
- [ ] A skipped Blizzard filter callback causes no stale state or missing cleanup.

### Chat-frame lifecycle

- [ ] Create a new permanent window.
- [ ] Open a temporary whisper window.
- [ ] Select, dock, undock and redock windows.
- [ ] Close a temporary and permanent window.
- [ ] Controls, ChatBar, Style, Resize, ticker and copy overlay attach once to the correct frame.

### Release gate

- [x] Static CI passed for the reviewed implementation.
- [ ] No Lua errors with only Roth Chat enabled.
- [ ] No repeating taint/secret/forbidden errors in combat or restricted chat.
- [ ] Runtime matrix results and tested build are recorded here.
- [ ] Package contains only addon runtime files, documentation, licenses and intended tests/workflows.

## Runtime result

**Status:** `STATIC_VALIDATION_PASSED; LIVE_CLIENT_TEST_PENDING`  
**Last updated:** 2026-08-27
