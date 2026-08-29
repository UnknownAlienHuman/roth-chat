# Chat addon implementation review — 2026-08-29

## Scope and evidence boundary

This review compares Roth Chat with two targeted implementation references:

- **Chattynator 222** — current release status was verified on CurseForge for Retail 12.1.0. Its changelog points to `TheMouseNest/Chattynator`, but that repository/tag is not publicly accessible. Implementation details below therefore use the explicitly non-authoritative snapshot `dawsze/Chattynator@2c357fe8be3f0780b85cd84b231779b6e4f08218` and are not treated as current upstream behavior.
- **Prat 3.0 3.9.105** — current release status and source link were verified on CurseForge. Implementation details use `Legacy-of-Sylvanaar/prat-3-0@90781a51d1d048a244922de8d76d043cb65a626a`.

Third-party code is implementation evidence only. Blizzard source/generated docs and the project engineering KB remain authoritative. No source code from either addon was copied.

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

### Explicitly not adopted

- No Blizzard chat global replacement.
- No copied Blizzard message handler.
- No custom full renderer.
- No raw event-payload persistence.
- No command-history/edit-box synchronization.
- No third-party code or assets.

## Remaining audit items

- Add rate-limited error diagnostics for hot per-message callback failures; current `NS.SafeCall` and the core multi-return filter reporter can still produce an error storm.
- Verify schema-v2 replay and copy behavior in the live Retail client with timestamps enabled/disabled and with legacy SavedVariables.
- Verify BNet/censored-message behavior without attempting to serialize inaccessible values.
- Recheck Prat's 14/19 forwarding path and the Blizzard source discrepancy after the next exported UI-source update.
