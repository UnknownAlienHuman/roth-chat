# Roth Chat

Modular immersive Diablo-style chat UI for World of Warcraft Retail / Midnight. Roth Chat provides fading chat windows, a ticker, docked controls, channel shortcuts, copy overlays, clickable URLs, persistent scrollback, alerts, and optional visual styling.

## Compatibility

- Game/API target: **Retail 12.1.0**
- Interface: `120100`
- Addon version: `1.1.0`
- SavedVariables: `RothChatDB`
- Author: **Neomorph**

## Retail 12.1 migration

Version 1.1.0 updates the chat integration for Blizzard's current 19-argument message-filter contract. The shared dispatcher preserves the complete tuple, limits Roth Chat transformations to the visible message text, and skips addon processing when the payload is not accessible.

Secret-capable values are gated with `canaccessvalue` / `canaccessallvalues` before inspection, comparison, formatting, table use, or persistence. The render-facing `AddMessage` integration forwards only accessible text and color primitives to Roth Chat modules and does not retain trailing opaque metadata.

Profile migration is additive: upgrading the addon no longer re-enables modules or features that the user explicitly disabled.

## Installation and usage

Copy `RothChat` into `World of Warcraft/_retail_/Interface/AddOns/`, enable it, and reload the UI. Open the options panel with `/rothchat`. The extended feature overview remains in [`README.txt`](README.txt).

## Dependencies

The addon vendors LibStub, CallbackHandler-1.0, and LibSharedMedia-3.0 under `ThirdParty/`. Their license notices must remain with the repository.

## Validation status

The 12.1 source migration and static review are complete. A live-client smoke pass is still required before release, especially for chat filters, restricted chat states, temporary whisper windows, inactive-tab alerts, copy overlay behavior, and reload persistence. The active checklist is maintained in [`TODO.md`](TODO.md).

## License

Licensed under the [MIT License](LICENSE.md). Third-party notices are kept under [`ThirdParty/`](ThirdParty/).

### Acknowledgements

The visual glass aesthetic and textures are inspired by and directly use assets from the original **Glass** addon by **Wowuidev**. Glass is also MIT licensed; its full notice remains in [`ThirdParty/GLASS_LICENSE.txt`](ThirdParty/GLASS_LICENSE.txt).
