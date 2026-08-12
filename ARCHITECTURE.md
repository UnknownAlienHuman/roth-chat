# Roth Chat architecture

`Util.lua` supplies protected-call, scheduling and safe-string helpers. `Core.lua` initializes the namespace and event bus. The module layer owns separate concerns: Dock, Style, Controls, ChatBar, Restore, CopyOverlay, URL copy, Resize, Ticker, Timestamps, Cleaner, Alerts and Sticky. `Options.lua` exposes configuration.

The TOC intentionally leaves the legacy `Modules/History.lua` disabled; persistence is handled by Restore in the current load order. Changes involving chat text or protected operations should preserve the deferred scheduler and safe-string boundary.
