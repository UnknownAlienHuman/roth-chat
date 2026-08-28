# Roth Chat release gates

This file contains only unresolved validation and release work. Completed engineering work belongs in `CHANGELOG.md`; durable technical rules belong in `AGENT_GUIDE.md` and `ARCHITECTURE.md`.

## Current candidate

- Version: `1.1.1`
- Retail target: `12.1.0`
- Interface: `120100`
- Source baseline: `12.1.0.69497` / `Gethe/wow-ui-source@027d26c3406d`
- Status: implementation complete for review; current-branch validation and live-client matrix still required

## Automated release gate

- [ ] Current head parses every Lua file with `luac`.
- [ ] `tests/core_chat_filter_spec.lua` passes.
- [ ] `tests/core_module_lifecycle_spec.lua` passes.
- [ ] `tests/url_copy_spec.lua` passes.
- [ ] `tests/cleaner_spec.lua` passes.
- [ ] TOC metadata and every active TOC path pass validation.
- [ ] The successful workflow run belongs to the exact commit being merged or released.

## Live Retail startup and module lifecycle

- [ ] Fresh login with no `RothChatDB` produces no Lua error.
- [ ] Upgrade from `1.1.0` preserves explicitly disabled modules and feature values.
- [ ] Disable and re-enable every exposed module after `PLAYER_LOGIN`; no duplicate listener, filter, `AddMessage` callback, ticker line, tab flash or hover surface appears.
- [ ] `/reload` produces no duplicate hooks or restored messages.
- [ ] Logout/login keeps bounded Restore data for permanent windows only.
- [ ] Starting with `profile.enabled = false` leaves feature modules inactive.

## Chat and restriction matrix

- [ ] Say, yell, emote and text emote.
- [ ] Party/leader, raid/leader/warning and instance/leader.
- [ ] Guild and officer.
- [ ] Whisper, whisper inform, `/r`, Battle.net whisper and Battle.net whisper inform.
- [ ] Numbered public channels, channel notices, system and achievement messages.
- [ ] URL and timestamp transformations independently and together.
- [ ] URL ending in balanced `)`, unmatched `)`, sentence punctuation and an existing item/spell hyperlink.
- [ ] Forced addon chat restrictions and forced challenge-mode restrictions.
- [ ] Enter and leave restriction state without reload.
- [ ] No secret/inaccessible value comparison, concatenation, persistence or repeated error loop.
- [ ] No `HistoryKeeper` taint on monster yell, channel routing, whisper/reply or report/context-menu paths.

## Dynamic chat-frame matrix

- [ ] Create a permanent chat window.
- [ ] Open, close and reopen temporary whisper windows; no prior correspondent's restored text leaks into the reused frame.
- [ ] Temporary whisper edit box retains Blizzard's target header and computed text inset.
- [ ] Select, dock, undock and redock windows.
- [ ] ChatBar follows the selected dock frame and no longer contributes hover ownership to the prior frame.
- [ ] Controls, Style, Resize, Restore and CopyOverlay attach once to each new frame.
- [ ] Closing a frame cancels its resize timer/animation and closes its overlay.
- [ ] Inactive dock-tab flash starts on a new message, stops on selection and is cleared when Alerts is disabled.

## Controls, ticker and copy ownership

- [ ] One mouse-wheel gesture produces one scroll action; Shift+wheel reaches top/bottom once.
- [ ] Disabling Controls delegates scrolling to Blizzard without duplicate movement.
- [ ] Re-enabling Controls restores smooth scrolling and lifecycle listeners.
- [ ] Messages received while chat is visible never replay after chat hides.
- [ ] Messages received while chat is hidden appear once in ticker order.
- [ ] New messages during ticker fade-out do not leave `isAnimating` stuck.
- [ ] Switching primary chat frame restores the old frame's alpha and queue state.
- [ ] Opening and closing CopyOverlay while chat is visible, hidden and mid-fade leaves the final alpha consistent with current Controls/Ticker state.

## Combat and visual ownership

- [ ] Enter combat during Resize snap animation; animation stops and one continuation runs after combat.
- [ ] Trigger Dock or Style refresh in combat; one deferred apply runs after combat.
- [ ] Disable Restore and verify original `fading`, `timeVisible` and `fadeDuration` values are restored.
- [ ] Enable/disable Style; permanent hooks become no-ops while inactive and produce no repeated geometry changes.
- [ ] Background, border, font and edit-box position settings update without duplicate module activation.
- [ ] Cleaner normal mode preserves the active client locale.
- [ ] Cleaner compact mode changes only the intended channel tags and restores the original strings on disable.

## Source contract recheck

- [ ] Record actual callback arity for accessible say, whisper, channel and system filters on the current Retail build without serializing restricted values.
- [ ] Compare live behavior with the exported `ChatFrameOverrides.lua` path tracked as `WOWUI-2026-011` in the engineering KB.
- [ ] Update or retire the KB issue only when runtime and current exported source agree.

## Packaging gate

- [ ] Record the tested Retail build and results in `MIGRATION_12_1.md`.
- [ ] No Lua, taint, secret-value or forbidden-operation errors with only Roth Chat enabled.
- [ ] Review the final diff for runtime files, metadata, licenses and intended documentation/tests only.
- [ ] Produce a clean addon ZIP without repository-only planning/audit artifacts unless the release workflow explicitly excludes them.
