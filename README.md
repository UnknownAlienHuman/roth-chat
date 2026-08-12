# Roth Chat

Modular immersive Diablo-style chat UI for WoW Midnight. It provides fading chat windows, a ticker, docked controls, channel shortcuts, copy overlays, URL handling, history/restore helpers and optional styling integrations.

## Compatibility

- Interface: `120001`, `120005`
- Version: `1.0.1`
- SavedVariables: `RothChatDB`
- Author field in TOC: Roth Team

## Installation and usage

Copy `RothChat` into `World of Warcraft/_retail_/Interface/AddOns/`, enable it, then reload the UI. Open the options panel with `/rothchat`. The existing text documentation is preserved in [`README.txt`](README.txt).

## Dependencies

The addon vendors LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 under `ThirdParty/`. Their license notices must remain with the repository.

## Development status

Current open validation is listed in [`TODO.md`](TODO.md): chat styling/settings, copy overlay, ticker/dock/whisper behavior, syntax validation and HistoryKeeper taint checks. Its opening audit notes are historical context; the checked tasks below them record the completed migrations.

## License

Licensed under the [MIT License](LICENSE.md). Third-party notices are kept
under [`ThirdParty/`](ThirdParty/).

### Acknowledgements

The visual glass aesthetic and textures are inspired by and directly use
assets from the original **Glass** addon by **Wowuidev**. Glass is also MIT
licensed; its full notice remains in
[`ThirdParty/GLASS_LICENSE.txt`](ThirdParty/GLASS_LICENSE.txt).
