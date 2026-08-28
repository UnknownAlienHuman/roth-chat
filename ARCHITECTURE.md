# Roth Chat architecture

## Core layers

`Util.lua` supplies protected calls, scheduling, animation, chat-frame discovery, access gates, safe string conversion, text collection, and UI helpers. `Core.lua` initializes the namespace, SavedVariables, module lifecycle, internal event bus, chat lifecycle router, centralized message-filter registry, and unified `AddMessage` dispatcher.

The module layer owns separate concerns: Dock, Style, Controls, ChatBar, Restore, CopyOverlay, UrlCopy, Colors, Resize, Ticker, Timestamps, Cleaner, Alerts, and Sticky. `Options.lua` exposes configuration through Blizzard's Settings API.

The TOC deliberately leaves legacy `Modules/History.lua` disabled. `Modules/Restore.lua` owns current persistent scrollback.

## Retail 12.1 chat boundary

Blizzard's Retail 12.1 message-filter callback uses a 19-argument tuple. Roth Chat's dispatcher preserves and returns all 19 fields. Module filters may discard a message or replace only `arg1`, the visible message string; they must not rewrite routing, sender, line-ID, access-ID, or metadata fields.

Before an addon filter is called, the complete tuple is checked through `NS.CanAccessAllValues`. If access is denied, Roth Chat returns without inspecting or copying any payload value and Blizzard continues with its original data.

The post-render `AddMessage` dispatcher is a separate boundary. It forwards only accessible rendered text plus accessible color primitives. Trailing varargs are intentionally not propagated to addon modules. Restore, ticker, alerts, and copy features therefore consume access-normalized display data rather than raw chat-event payloads.

## State rules

`RothChatDB.profile` stores settings, module flags, and the addon version. Upgrades add missing defaults but preserve explicit user choices. `RothChatDB.history` stores only ordinary render-facing text records managed by Restore; raw filter tuples and opaque metadata must never enter SavedVariables.

Changes involving chat text or restricted operations must preserve the access gate before every Lua operation, the full 19-field pass-through contract, the shared deferred scheduler, and the one-hook-per-chat-frame architecture.
