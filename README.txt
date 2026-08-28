Roth Chat (RothChat) v1.1.0
Retail / Midnight 12.1.0 — Interface 120100
Author: Neomorph

A modular and immersive chat addon inspired by the aesthetics of Glass and the modularity of Prat.

---

### Core Philosophy

- **Immersive:** Chat remains available when needed and fades when idle. The optional ticker can show recent messages while the primary chat frame is hidden.
- **Modular:** Styling, controls, persistence, copying, URLs, timestamps, alerts, resizing, and channel behavior are isolated modules connected through a central core.
- **Efficient:** Chat-frame hooks are consolidated, scheduling is shared, queues avoid front-removal churn, and update drivers run only while work is active.
- **Restriction-aware:** Chat messaging lockdown, combat-sensitive surfaces, and inaccessible values degrade safely instead of being probed or retained.

---

### Key Features

**1. Immersive Chat**
- Fading primary chat window.
- Optional latest-message ticker.
- Hover-to-reveal controls.
- Pin button for persistent controls.

**2. Double-Click to Copy**
- Double-click a chat frame or its hover area to open a selectable copy overlay.
- Recent accessible render text is available for normal selection and `Ctrl+C`.
- Press `ESC` to close the overlay.

**3. ChatBar**
- Compact shortcuts for `/say`, `/party`, `/raid`, `/instance`, `/guild`, `/officer`, channels, whisper, and reply.
- Follows the active docked chat frame.
- Respects chat messaging lockdown.

**4. Persistent Scrollback**
- Restore keeps accessible rendered chat lines per window across reloads and sessions.
- Legacy `Modules/History.lua` remains disabled to avoid duplicate persistence paths.

**5. Formatting and Alerts**
- Optional timestamps and compact channel formatting.
- Clickable URL links with a copy popup.
- Class-colored names where Blizzard supports them.
- Whisper sound and inactive dock-tab alerting.

**6. Styling and Interaction**
- Fonts, shadows, background fill, border, and edit-box positioning.
- Smooth scrolling and resize grip.
- Temporary whisper-window and dock lifecycle handling.

---

### Retail 12.1 Engineering Notes

- The centralized chat filter accepts Blizzard's complete 19-argument callback tuple.
- Roth Chat filters may replace only the visible message string (`arg1`).
- No-op paths return only `false`, leaving Blizzard's current secure tuple in place.
- A real text replacement returns `arg1` plus all remaining 18 fields unchanged.
- `canaccessvalue` / `canaccessallvalues` are checked before inspection, comparison, formatting, table use, or storage.
- If the tuple is inaccessible, Roth Chat skips its filter callbacks and leaves Blizzard's payload untouched.
- The post-render `AddMessage` hook forwards only accessible text and numeric color primitives; trailing opaque metadata is not retained.
- Addon upgrades add missing defaults but preserve modules and features explicitly disabled by the user.

---

### Slash Command

`/rothchat` — opens the Roth Chat settings panel when the current combat/chat restriction state permits it.

---

### Validation

Static migration review is complete. Live-client verification is still required for all chat types, temporary windows, restrictions, alerts, copying, ticker behavior, and reload persistence before publishing the release.
