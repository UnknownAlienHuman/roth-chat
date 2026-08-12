# RothChat TODO



Проблемы:

1) ~~Текст копируется не там, где выделяем~~ — ИСПРАВЛЕНО: убран ScrollingEditBoxTemplate (рассинхронизация scroll/selection), всегда используется UIPanelScrollFrameTemplate + plain EditBox; убрано автовыделение всего текста при открытии.
2) ~~В бою нельзя печатать~~ — ИСПРАВЛЕНО: добавлены хуки OnEditFocusGained/OnEditFocusLost на EditBox в Controls.lua — когда игрок нажимает Enter, Controls видит фокус и не прячет UI.

## Audit Summary

- `Options.lua` still uses a legacy canvas with `InterfaceOptions*` templates and old dropdown widgets. The addon is registered in `Settings`, but the controls themselves are not migrated to the modern Blizzard Settings API.
- The current UI removed manual style controls even though `Style.lua` still supports `styleBgTexture`, `styleBorderTexture`, `styleBackgroundColor`, and `styleBorderColor`.
- `Core.lua` still defaults to non-minimal presets (`glass`, `solid`) and exposes theme-preset plumbing the user no longer wants.
- Runtime overhead is concentrated in three places:
  - `Controls.lua`: delayed hover checks via repeated `C_Timer.After(delay, ...)` and next-frame work via `C_Timer.After(0, ...)`.
  - `Ticker.lua`: message queue uses `table.remove(q, 1)` and schedules a fresh `C_Timer.After(...)` after every animation step.
  - Addon-wide next-frame work is fragmented across `Core.lua`, `Controls.lua`, `Dock.lua`, `CopyOverlay.lua`, `Style.lua`, and `Ticker.lua`.
- A config bug exists today: `Controls.lua` reads `smoothScrollDuration`, but that key is never defaulted in `Core.lua`.

## Task 1 - Settings API migration and style feature restore

- [x] Replace the legacy custom options panel with Blizzard `Settings` vertical-layout categories/subcategories.
- [x] Keep a single visual baseline: `Minimal` is the default profile style.
- [x] Remove user-facing theme presets (`glass`, `solid`) from the settings UI.
- [x] Restore manual style controls:
  - [x] background on/off
  - [x] background alpha
  - [x] background fill color
  - [x] background texture selection
  - [x] border on/off
  - [x] border color
  - [x] border texture selection
  - [x] font selection
  - [x] font size
  - [x] text shadow
  - [x] timestamp toggle/color
  - [x] edit box position
- [x] Source background/border/font lists from LibSharedMedia when available.
- [x] Add fallback built-in media entries so the dropdowns still work without external shared media packs.
- [x] Stop calling `ApplyModuleEnablement()` for every non-module setting change; use targeted refresh/apply paths instead.
- [x] Preserve slash-command opening through `Settings.OpenToCategory(categoryID)`.

Commit target:
- `RothChat: migrate settings and restore manual style controls`

## Task 2 - Scheduler and hot-path optimization

- [x] Add one shared next-frame scheduler utility and replace addon-local `C_Timer.After(0, ...)` fan-out with it.
- [x] Fix missing `smoothScrollDuration` default in `Core.lua`.
- [x] Replace `Controls.lua` hover-delay timer spam with one lightweight scheduler/driver.
- [x] Replace `Controls.lua` hotspot-bounds next-frame timer with the shared next-frame scheduler.
- [x] Keep `Controls.lua` smooth-scroll animation behavior, but avoid unnecessary per-frame config lookups where possible.
- [x] Convert `Ticker.lua` queue from `table.remove(q, 1)` to indexed queue bookkeeping.
- [x] Remove per-message `C_Timer.After(...)` chaining in `Ticker.lua`; keep the animation/hold cycle inside ticker state.
- [x] Ensure ticker fade/hold behavior still matches current UX when chat is hidden.
- [x] Replace remaining zero-delay timers in `Dock.lua`, `CopyOverlay.lua`, `Style.lua`, and `Core.lua` with the shared scheduler.

Commit target:
- `RothChat: optimize chat schedulers and ticker queue`

## Task 3 - Verification and cleanup

- [ ] Verify `Style.lua` still applies restored background and border media correctly.
- [ ] Verify settings changes update live without duplicate module enable paths.
- [ ] Verify copy overlay still opens on double-click and restores prior chat alpha/state.
- [ ] Verify primary chat ticker still works and non-primary frames stay visible.
- [ ] Run a syntax pass against changed Lua files if a Lua compiler is available in the workspace.
- [x] Update this `todo.md` with completed items.

Verification notes:

- Local static pass completed:
  - `git diff --check` is clean.
  - `C_Timer.After(...)` and `table.remove(q, 1)` are gone from the addon.
  - `Options.lua` now registers through Blizzard `Settings` vertical layout categories/subcategories.
  - `CopyOverlay.lua` now exposes `Refresh`, so font/style changes can propagate to existing overlays.
- Runtime verification is still required in the WoW client for:
  - live style media changes
  - double-click copy overlay behavior
  - ticker visibility/hold timing
  - interaction between `Controls`, `Ticker`, and `CopyOverlay`
- Lua compiler check was not possible here because `lua`/`luac` is not installed in this workspace.

Commit target:
- `RothChat: finalize settings and performance pass`

## Task 4 - Chat taint hotfix

- [x] Trace the `HistoryKeeper.lua` secret-string error to `RothChat` chat-path taint.
- [x] Remove the direct `ChatFrameUtil.ResolvePrefixedChannelName` overwrite from `Modules/Cleaner.lua`.
- [x] Keep Cleaner limited to safe chat format-string customization.
- [ ] Verify in the WoW client that `CHAT_MSG_MONSTER_YELL` no longer throws `HistoryKeeper` taint errors.
- [ ] Verify Cleaner formatting remains acceptable with `Shorten Channels` enabled.

Verification notes:

- Blizzard chat source shows `ChatFrameOverrides.lua` now routes `MONSTER_YELL` through `ChatHistory_GetAccessID(infoType, chatTarget, arg12 or arg13)`.
- Overwriting `ChatFrameUtil.ResolvePrefixedChannelName` taints the shared `ChatFrameUtil` table and is not a safe hook strategy for this path.
- Local static verification completed:
  - no `ResolvePrefixedChannelName =` assignment remains in `RothChat` Lua sources
  - `git diff --check -- _Addons/RothChat` is clean
- Runtime validation is still required because secret-value taint is runtime-only.

Commit target:
- `RothChat: stop tainting chat history routing`

## Task 5 - Chat restriction guards

- [x] Add a shared helper for `C_ChatInfo.InChatMessagingLockdown()`.
- [x] Guard `/rothchat` settings opening against restricted chat/settings surfaces.
- [x] Guard `ChatBar` channel buttons against chat messaging lockdown.
- [x] Run static verification for the new guards.

Verification notes:

- Added `NS.IsChatMessagingRestricted()` and `NS.IsSettingsOpenRestricted()` for shared guard logic.
- `/rothchat` now exits early instead of calling `Settings.OpenToCategory` during combat/chat restriction surfaces.
- `ChatBar` now exits early instead of calling `ChatFrame_OpenChat` during chat messaging lockdown, with a small print throttle.
- `git diff --check -- _Addons/RothChat` is clean.

Commit target:
- `RothChat: guard chat lockdown surfaces`

## Task 6 - Chat filter taint and docked ChatBar

- [x] Stop tainting non-message chat event args in the shared message-filter dispatcher.
- [x] Update message-filter users to return a replacement only when the visible message actually changes.
- [x] Make ChatBar follow the active dock tab instead of sticking to the original chat frame.
- [x] Run static verification for the dispatcher and ChatBar fixes.

Verification notes:

- `Core.lua` message filters now only allow `arg1` replacement, which avoids tainting channel/sender routing args used by Blizzard `HistoryKeeper`.
- `Timestamps.lua` and `UrlCopy.lua` now return no replacement when the rendered message text does not change.
- `ChatBar.lua` now resolves the active dock frame and re-applies itself on `CHAT_LAYOUT_CHANGED` / `CHAT_FRAME_READY`.
- `git diff --check -- _Addons/RothChat` is clean.

Commit target:
- `RothChat: fix chat filter taint and docked chat bar`

## Task 7 - Restore unread tab glow

- [x] Trace the missing new-message tab highlight to `Style.lua` suppressing `ChatFrameXTabGlow`.
- [x] Stop forcing the Blizzard tab glow alpha to `0` so whisper unread flash can render again.
- [ ] Verify in the WoW client that inactive whisper tabs glow again on incoming whispers.

Verification notes:

- Blizzard `FloatingChatFrame.xml` defines `$parentGlow` with `parentKey="glow"` and `alphaMode="ADD"` for chat tabs.
- Blizzard `FCF_StartAlertFlash` drives unread tab flash through `UIFrameFlash(chatTab.glow, ...)`.
- Blizzard `ChatFrameUtil.FlashTabIfNotShown` only starts this flash for whisper-style message types (`WHISPER`, `BN_WHISPER`, `MONSTER_WHISPER`), so ordinary chat tabs still will not flash unless custom logic is added later.

Commit target:
- `RothChat: restore unread chat tab glow`

## Task 8 - General inactive-tab alerting

- [x] Reuse Blizzard `FCF_StartAlertFlash` / `FCF_StopAlertFlash` for RothChat inactive dock tabs.
- [x] Drive the alert from the shared `AddMessage` hook instead of replacing Blizzard chat routing.
- [x] Clear alert state when the tab becomes the selected dock frame.
- [x] Update the settings copy so the module reflects both whisper sound and inactive-tab glow behavior.
- [ ] Verify in the WoW client that any new message in a non-selected dock tab starts the tab glow and stops when the tab is selected.

Verification notes:

- `FCF_StartAlertFlash` / `FCF_StopAlertFlash` are confirmed in Blizzard `FloatingChatFrame.lua` for the current build, even though they are not indexed by the `wow-api` lookup dataset.
- RothChat now calls those Blizzard functions from the existing safe post-`AddMessage` dispatcher in `Core.lua`, which avoids replacing chat handlers or filters.
- The module remains dock-tab scoped; it does not add custom flashing for visible/selected frames.

Commit target:
- `RothChat: alert inactive chat tabs on new messages`

## Task 9 - Temporary whisper window header/edit box fix

- [x] Trace the missing whisper target name to RothChat restyling the chat edit box after Blizzard `UpdateHeader()`.
- [x] Preserve Blizzard-calculated edit box left/right insets for temporary whisper windows instead of forcing fixed insets.
- [x] Re-run the inset adjustment after edit box header updates so new temporary chat windows keep the target name visible.
- [ ] Verify in the WoW client that new whisper popout windows show the interlocutor name in the header and no longer display a blank rectangular edit box.

Verification notes:

- Blizzard `FloatingChatFrame.lua` sets the temporary whisper window name from `chatTarget` via `FCF_SetWindowName(chatFrame, name)` and assigns the edit box tell target via `chatFrame.editBox:SetTellTarget(chatTarget)`.
- Blizzard `ChatFrameEditBoxMixin:UpdateHeader()` then computes the left text inset from the whisper header width; overriding it with fixed `SetTextInsets(8, 8, 4, 4)` hides the target label.
- `Style.lua` now hooks `UpdateHeader()` and only clamps padding while preserving Blizzard's computed header space.

Commit target:
- `RothChat: fix temporary whisper header and edit box`
