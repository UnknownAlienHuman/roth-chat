# Chat addon implementation review — 2026-08-29

## Scope and evidence boundary

This review compares Roth Chat with four targeted implementation references:

- **Chattynator 222** — current release status was verified on CurseForge for Retail 12.1.0. Its changelog points to `TheMouseNest/Chattynator`, but that repository/tag is not publicly accessible. Implementation details below therefore use the explicitly non-authoritative snapshot `dawsze/Chattynator@2c357fe8be3f0780b85cd84b231779b6e4f08218` and are not treated as current upstream behavior.
- **Prat 3.0 3.9.105** — current release status and source link were verified on CurseForge. Implementation details use `Legacy-of-Sylvanaar/prat-3-0@90781a51d1d048a244922de8d76d043cb65a626a`.
- **LS: Glass** — implementation evidence uses `ls-/ls_Glass@2df600e7b3d6d9eaf8dd29128377cd45ba1d9f26`. Its TOC targets Interface `110207`, and the project README states that it is retired for Midnight. It is not current 12.1 API evidence.
- **Original Glass** — provenance and historical implementation evidence use `mixxorz/Glass@d7d5fd6865b00c32ccfa40275b9924630e70b143`. The project is abandoned and directs users to LS: Glass.

Third-party code is implementation evidence only. Blizzard source/generated docs and the project engineering KB remain authoritative. No Chattynator or Prat source code was copied. Existing Glass-derived material already distributed by Roth Chat was audited by exact Git blob SHA and given corrected dual-license attribution.

## Chattynator snapshot trace

### Load and ownership

- `Chattynator_fork.toc` loads a full replacement chat stack and owns `CHATTYNATOR_MESSAGE_LOG`.
- `Core/Messages.lua` owns a structured current/historical message store.
- `Display/ScrollingMessages.lua` renders only visible rows with pooled FontStrings and textures.
- `Display/CopyChat.lua` builds copy text from structured message records.
- `Modifiers/URLs.lua` applies URL formatting as a live modifier.
- `Core/Overrides.lua` replaces or suppresses substantial Blizzard chat-frame behavior.

### Useful patterns

1. **Timestamp is metadata, not message text.** Message time, type, color and text are retained separately; display and copy surfaces format the timestamp at render/export time.
2. **Durable storage is sanitized.** Session/context handles such as account-name tokens, BNet links and censored-message links are removed or replaced before long-term retention.
3. **History is bounded and migrated incrementally.** The snapshot separates recent and historical storage and time-slices larger conversions.
4. **Custom rendering uses pools.** FontString/texture pooling is appropriate because Chattynator owns a complete renderer.
5. **Copy is derived from the message model.** Copy timestamp inclusion is independent from how the visible line was rendered.

### Patterns rejected for Roth Chat

1. Replacing `ChatFrameUtil` scroll functions, unregistering Blizzard chat-frame events or suppressing Blizzard frames conflicts with Roth Chat's narrow-adapter and taint-minimization policy.
2. A custom renderer and processed-message cache are unjustified while Roth Chat deliberately retains Blizzard rendering.
3. Stack inspection in a per-message path is too expensive and fragile for Roth Chat's lightweight scope.
4. The snapshot is not current upstream and Chattynator is All Rights Reserved; only independently reasoned architecture lessons may be used.

## Prat trace

### Load and ownership

- `Prat-3.0.toc` loads a large modular Ace3-based framework.
- `addon/MessageEventHandler.lua` contains a maintained copy/derivative of Blizzard message-event handling.
- `modules/Timestamps.lua` hooks `AddMessage` and mutates the newest history-buffer entry.
- `modules/History.lua` owns chat-line limits and edit-box command history.
- `modules/CopyChat.lua` copies from the selected chat frame and adds its own copy UI.

### Useful patterns

1. **Features are independently activatable.** Hook and event cleanup is associated with module enable/disable.
2. **Dynamic frame updates are explicit.** Modules react when chat frames are added or removed.
3. **History limits are bounded.** Both chat-line and command-history counts have explicit limits.
4. **High-cost features are optional.** Users can disable modules they do not need.

### Risks not adopted

1. `MessageEventHandler.lua` still forwards only `arg1` through `arg14` to `ChatFrameUtil.ProcessMessageEventFilters` in the reviewed current commit. This demonstrates the contract-drift risk of copying Blizzard's handler instead of adapting around it.
2. Deep ownership of edit-box command history and tell/channel target state expands the protected/restricted surface. Roth Chat will not adopt it without a current Retail contract and dedicated runtime matrix.
3. Timestamp mutation inside Blizzard history buffers couples presentation and retained data.
4. Prat is GPLv3; Roth Chat is MIT. Source code cannot be transplanted into Roth Chat.

## LS: Glass trace

### Load and renderer ownership

- `ls_Glass/ls_Glass.toc` targets Interface `110207`.
- `core/components/slidingmessageframe.lua` captures Blizzard chat frames, hides their `FontStringContainer`, disables their `OnUpdate`, reads their `historyBuffer`, and renders through an addon-owned sliding message frame.
- The component owns its own message-line pool, smooth-scroll driver, fade state, alert state and scroll-to-bottom controls.
- Blizzard remains the source of history entries, but LS: Glass replaces the visible renderer.

### Useful patterns

1. **One active smoother.** A single updater owns all active smooth-scroll jobs and removes `OnUpdate` when the active map becomes empty.
2. **Dirty-layout flags.** Size/history changes mark layout/display dirty and coalesce a later refresh instead of rebuilding continuously.
3. **Attach/release mapping.** Chat-frame-to-renderer ownership is explicit, and frame release clears pooled/display state.
4. **Avoid double rendering.** The default `FontStringContainer` and default frame work are disabled when the custom renderer takes ownership.

### Why Roth Chat does not adopt the renderer

1. LS: Glass is retired for Midnight and is not current 12.1 contract evidence.
2. A second renderer would dramatically expand hyperlink, selection, history-buffer, accessibility and lifecycle responsibility.
3. Roth Chat already uses Blizzard rendering; adding a custom renderer only for smooth fade/scroll would duplicate work and increase measured CPU attribution.
4. The reviewed current master contains a concrete drift defect: two global hooks target `ChatFrameUtil.ChatPageUp`; the second routes a downward movement and appears intended for `ChatPageDown`. Mature custom renderers remain vulnerable to small integration drift.

### Provenance result

Four Roth Chat assets are exact Git-blob matches to LS: Glass and therefore require Apache-2.0 attribution:

- `Assets/border-highlight.TGA` — `ae4d9aa4dd50ea16790009c986f24275c1c6515a`;
- `Assets/border.TGA` — `8c5aada40e24c107dfbd09a99c1c9748aa2a71d3`;
- `Assets/icons.TGA` — `1206ddcedff0a8cb191dc8094a4ecdf561cca009`;
- `Assets/scroll-buttons.TGA` — `43be3a6b0a742a52f40309a64eb987a33cc13ab8`.

`Util.lua` also contains explicitly marked modified/adapted fading and texture-layout helpers. The pre-existing MIT-only notice was insufficient for this material. `ThirdParty/LS_GLASS_LICENSE.txt` and `ThirdParty/ATTRIBUTIONS.md` now record the correct Apache-2.0 provenance.

## Original Glass trace and provenance

Original Glass is the abandoned MIT-licensed addon by Mitchel Cabuloy. Its architecture is a historical full-replacement renderer and is not usable as current Retail evidence.

Two Roth Chat assets are exact Git-blob matches to the original project:

- `Assets/overlayMask.tga` — `48f0f1319903cdd1d7f1db43479984a30493c55e`;
- `Assets/snapToBottomIcon.tga` — `c3397a06ee3c6635de5ecbba6927fb13a256b145`.

The existing `ThirdParty/GLASS_LICENSE.txt` correctly applies to those two assets, but not to LS: Glass material. The two projects and licenses must remain separate in release packages.

## Roth Chat decisions

### Adopted in the current audit branch

- Added `ChatText.lua` as a small shared boundary for accessible text, timestamp formatting, durable sanitation and copy normalization.
- Changed Restore storage to schema v2: `{timestamp, baseText, r, g, b, version}`.
- Removed Roth's rendered timestamp before persistence and reconstruct it only for replay when the Timestamps module is currently active.
- Made copy/export timestamps independent from rendered text, preventing duplicate timestamps and making `copyIncludeTimestamps=false` authoritative for Restore and frame fallbacks.
- Sanitized BNet/account-name/censored-message handles before SavedVariables retention.
- Preserved backward compatibility with legacy v1 Restore rows without a destructive migration.
- Added executable contracts for shared text handling, timestamp integration and Restore schema/replay.
- Added the previously omitted Restore test to the validation workflow and added `workflow_dispatch` for exact-head verification.
- Added exact third-party asset provenance and the missing Apache-2.0 license.

### Explicitly not adopted

- No Blizzard chat global replacement.
- No copied Blizzard message handler.
- No custom full renderer.
- No raw event-payload persistence.
- No command-history/edit-box synchronization.
- No new Chattynator, Prat or Glass code/assets were copied during this audit.

## Remaining audit items

- Add rate-limited error diagnostics for hot per-message callback failures; current `NS.SafeCall` and the core multi-return filter reporter can still produce an error storm.
- Verify schema-v2 replay and copy behavior in the live Retail client with timestamps enabled/disabled and with legacy SavedVariables.
- Verify BNet/censored-message behavior without attempting to serialize inaccessible values.
- Recheck Prat's 14/19 forwarding path and the Blizzard source discrepancy after the next exported UI-source update.
- Remove unused legacy assets from the eventual runtime ZIP only after confirming they have no live references.
