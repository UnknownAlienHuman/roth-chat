Roth Chat (RothChat) v0.6.0

A modular and immersive chat addon inspired by the aesthetics of Glass and the modularity of Prat.

---

### Core Philosophy
- **Immersive:** The chat should be there when you need it and disappear when you don't. By default, the chat window fades out when not in use, leaving only a "ticker" line with the latest message.
- **Modern & Efficient:** Built with a clean, modular architecture. Uses modern WoW API features like AnimationGroups to avoid performance-heavy OnUpdate scripts.
- **Intuitive:** Interaction is designed to be simple and discoverable.

---

### Key Features

**1. Glass-like Design & Immersion**
- Chat windows have a clean, borderless, semi-transparent background.
- **Immersive Mode:** When the chat is not active (no mouse-over, not pinned), the main window fades out.
- **Ticker:** A single, scrolling line of the last message remains visible at the bottom of the chat, even when the main window is hidden.
- **Hover-to-Reveal:** All controls (Blizzard buttons, ChatBar) smoothly fade in when you move your mouse over the chat area and fade out when you leave.
- **Pin Button:** A small button allows you to "pin" the chat controls, keeping them visible.

**2. Double-Click to Copy**
- Simply **double-click** anywhere on the chat frame (or its surrounding hover area) to open a copy-friendly overlay.
- The overlay contains the recent chat history in a selectable `EditBox`, making it easy to copy text with `Ctrl+C`.
- Press `ESC` to close the overlay.

**3. ChatBar**
- A compact bar of buttons for quickly switching to different chat channels (`/say`, `/party`, `/guild`, etc.).
- Appears and disappears with the other controls.
- Its position and button size are configurable in the options.

**4. Persistent Scrollback**
- The addon saves your chat history for each window across sessions.
- When you log in, your chat windows are restored with their recent messages.
- This saved history is also used as the source for the copy overlay, ensuring you can copy more than what's currently visible.

---

### Engineering Notes
- **Modular Core:** The addon is split into independent modules (Style, Controls, Ticker, etc.) that communicate through a central event bus. This makes the code clean, maintainable, and resilient to errors in any single module.
- **Combat & Taint Safe:** Uses safe practices to avoid errors during combat, including a deferred-call mechanism for protected actions and careful handling of potentially "secret" values from the API.
- **No Copied Code:** While inspired by great addons like Prat and Glass, the implementation is a 100% clean-room project.

---

### Slash Command
`/rothchat` - Opens the addon's options panel.
