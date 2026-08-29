# Third-party attributions

This file records the provenance of third-party material distributed with Roth Chat. Repository/commit/blob identifiers are included so future audits can verify exact matches without relying on file names alone.

## LS: Glass — Apache License 2.0

**Source:** `ls-/ls_Glass@2df600e7b3d6d9eaf8dd29128377cd45ba1d9f26`  
**Copyright notice:** Copyright 2022 Val Voronov  
**License:** Apache License 2.0; see [`LS_GLASS_LICENSE.txt`](LS_GLASS_LICENSE.txt).

Exact asset matches:

| Roth Chat path | LS: Glass path | Git blob SHA |
|---|---|---|
| `Assets/border-highlight.TGA` | `ls_Glass/assets/border-highlight.TGA` | `ae4d9aa4dd50ea16790009c986f24275c1c6515a` |
| `Assets/border.TGA` | `ls_Glass/assets/border.TGA` | `8c5aada40e24c107dfbd09a99c1c9748aa2a71d3` |
| `Assets/icons.TGA` | `ls_Glass/assets/icons.TGA` | `1206ddcedff0a8cb191dc8094a4ecdf561cca009` |
| `Assets/scroll-buttons.TGA` | `ls_Glass/assets/scroll-buttons.TGA` | `43be3a6b0a742a52f40309a64eb987a33cc13ab8` |

`Util.lua` also contains modified clean-room/adapted helper code and layout ideas explicitly marked in source comments as derived from or inspired by LS: Glass, including cubic fading, gradient backgrounds, backdrop handling and highlight texture layout. Roth Chat changed the implementation and integration for its own module/lifecycle model.

LS: Glass is retired for Midnight and its reviewed TOC targets Interface `110207`; it is retained here only as provenance and historical implementation evidence, not as a current Retail API authority.

## Original Glass — MIT License

**Source:** `mixxorz/Glass@d7d5fd6865b00c32ccfa40275b9924630e70b143`  
**Copyright notice:** Copyright (c) 2020 Mitchel Cabuloy  
**License:** MIT; see [`GLASS_LICENSE.txt`](GLASS_LICENSE.txt).

Exact asset matches:

| Roth Chat path | original Glass path | Git blob SHA |
|---|---|---|
| `Assets/overlayMask.tga` | `Glass/Assets/overlayMask.tga` | `48f0f1319903cdd1d7f1db43479984a30493c55e` |
| `Assets/snapToBottomIcon.tga` | `Glass/Assets/snapToBottomIcon.tga` | `c3397a06ee3c6635de5ecbba6927fb13a256b145` |

The original Glass project is abandoned and directs users to LS: Glass. Its MIT license remains applicable to the exact assets above.

## Roth Chat material

Files not listed above or under another notice are governed by Roth Chat's repository license unless their own headers or bundled dependency notices say otherwise. `Assets/resize_grip.tga` was not matched to either audited Glass repository during this provenance pass; do not assign it a third-party origin without evidence.
