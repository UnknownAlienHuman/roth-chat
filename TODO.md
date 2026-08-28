# RothChat TODO

## Current target

- World of Warcraft Retail / Midnight `12.1.0`
- Interface `120100`
- Roth Chat `1.1.0`
- Blizzard source baseline: build `12.1.0.69497`, commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`

## Retail 12.1 migration

Implemented on `update/retail-12.1.0-chat-contract` and reviewed in draft PR #2:

- [x] Update TOC metadata to Interface `120100`, version `1.1.0`, author Neomorph.
- [x] Expand the centralized message-filter dispatcher from the obsolete 14-field shape to Blizzard's full 19-argument contract.
- [x] Preserve and return every routing, sender, line-ID, access-ID, and metadata field unchanged.
- [x] Restrict Roth Chat filter transformations to `arg1`, the visible message text.
- [x] Gate the complete incoming filter tuple with `canaccessallvalues` before addon callbacks.
- [x] Add shared `canaccessvalue` / `canaccessallvalues` wrappers with conservative fallback behavior.
- [x] Gate string conversion, truncation, UTF-8 work, chat text collection, URL parsing, timestamps, copy extraction, and whisper `lineID` use before any Lua inspection.
- [x] Stop forwarding trailing `AddMessage` varargs into addon modules; expose only accessible rendered text and color primitives.
- [x] Keep inaccessible filter callbacks fail-closed without copying or retaining their payload.
- [x] Make profile migration additive so upgrades preserve explicitly disabled modules and features.
- [x] Remove the pre-existing UTF-8 BOM from `Modules/Resize.lua` after it was caught by `luac5.1`.
- [x] Update README, architecture, code index/graph, agent guide, and extended feature documentation.
- [x] Add a GitHub Actions Lua 5.1 syntax gate for first-party addon files.

## Release-blocking live-client validation

These items cannot be certified by static source review and must be run in the target WoW client before publishing 1.1.0:

### Installation and profile migration

- [ ] Clean install with no `RothChatDB`.
- [ ] Upgrade an existing 1.0.1 profile and confirm explicitly disabled modules remain disabled.
- [ ] Reload and relog; confirm settings and restored scrollback remain valid.

### Chat message matrix

- [ ] Say, yell, emote, text emote.
- [ ] Party / party leader.
- [ ] Raid / raid leader / raid warning.
- [ ] Instance chat / instance leader.
- [ ] Guild / officer.
- [ ] Numbered channels.
- [ ] Whisper, outgoing whisper, Battle.net whisper, outgoing Battle.net whisper.
- [ ] System, achievement, guild achievement.
- [ ] Monster say/yell/whisper and encounter-generated messages.
- [ ] Confirm timestamps and URL conversion affect only visible text and never corrupt sender/channel metadata.

### Restrictions and taint

- [ ] Enter and leave combat while the edit box, ChatBar, copy overlay, and settings are used.
- [ ] Exercise chat messaging lockdown/restricted contexts.
- [ ] Confirm inaccessible callbacks are skipped silently.
- [ ] Confirm no `HistoryKeeper`, secret-value, taint, forbidden-action, or repeating Lua errors.
- [ ] Confirm no malformed access ID, line ID, sender, or channel routing after filters run.

### Chat-frame lifecycle

- [ ] Create, select, undock, redock, and close normal chat windows.
- [ ] Open and close temporary whisper windows.
- [ ] Confirm temporary whisper target headers and edit-box insets remain visible.
- [ ] Confirm ChatBar follows the active dock tab.
- [ ] Confirm inactive-tab alerts start on new messages and stop when the tab is selected.

### Interaction and presentation

- [ ] `/rothchat` opens outside restricted state and degrades cleanly inside restricted state.
- [ ] Style background, border, fonts, shadow, and edit-box position update live.
- [ ] Double-click copy overlay selects/copies the intended text and restores prior chat alpha.
- [ ] URL popup copies the expected target.
- [ ] Ticker/immersion behavior is correct for the primary frame and does not hide non-primary frames.
- [ ] Smooth scrolling and resize snap-back remain correct.

### Performance

- [ ] Confirm no permanent scheduler/fader `OnUpdate` after work completes.
- [ ] Stress incoming chat, scrolling, hover transitions, ticker playback, and temporary-window creation.
- [ ] Compare CPU/FPS with modules enabled and disabled; investigate any repeating callback or allocation spike.

## Static validation

- [x] Branch is based directly on `main` and contains only scoped addon, documentation, and CI changes.
- [x] Review confirms the dispatcher signature and return path contain all 19 arguments.
- [x] Review confirms Blizzard treats a callback return of `false` with no second return as “keep the existing transformed tuple”.
- [x] Review confirms first-party filters replace only `arg1`.
- [x] Review confirms direct whisper `lineID` use is access-gated before type, comparison, arithmetic, or table-key use.
- [x] Review confirms render-facing consumers no longer receive opaque `AddMessage` trailing metadata.
- [x] GitHub Actions Lua 5.1 syntax workflow passes for the PR head.
- [x] Full pull-request diff and whitespace review contains only scoped code, documentation, metadata, BOM cleanup, and CI changes.

Static validation does not substitute for the live-client matrix above.

## Previously completed engineering work

The following work predates the 12.1 migration and remains part of the current design:

- [x] Replace legacy options UI with Blizzard Settings vertical-layout categories and subcategories.
- [x] Restore manual font, background, border, color, alpha, timestamp, and edit-box controls.
- [x] Add targeted module refreshes instead of re-enabling every module for ordinary setting changes.
- [x] Consolidate next-frame and delayed work in the shared scheduler.
- [x] Replace ticker front-removal and chained timer behavior with indexed queue/state processing.
- [x] Remove direct replacement of `ChatFrameUtil.ResolvePrefixedChannelName`.
- [x] Add shared chat-lockdown/settings guards.
- [x] Make ChatBar follow the selected dock frame.
- [x] Restore Blizzard unread whisper-tab glow.
- [x] Add general inactive dock-tab alerting through Blizzard `FCF_StartAlertFlash` / `FCF_StopAlertFlash` from the post-render hook.
- [x] Preserve Blizzard-computed temporary whisper edit-box header insets.
- [x] Fix copy-overlay selection/scroll synchronization by using `UIPanelScrollFrameTemplate` with a plain multiline EditBox.
- [x] Keep chat controls visible while the edit box has focus.

## Design decisions

- `Modules/History.lua` remains disabled. `Modules/Restore.lua` is the sole persistence path.
- One core message-filter registry and one post-`AddMessage` dispatcher are preferred over module-owned hooks on every chat frame.
- Blizzard shared chat globals and `ChatFrameUtil` functions must not be replaced.
- Raw event/filter tuples and opaque metadata must not enter feature state, queues, timers, closures, logs, or SavedVariables.
- Only access-normalized rendered text and ordinary primitives may cross from the chat boundary into Roth Chat modules.
