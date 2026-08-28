# Roth Chat code graph

```mermaid
flowchart TD
  T["RothChat.toc"] --> U["Util.lua"]
  T --> C["Core.lua"]
  U -->|"access gates / scheduler / frame helpers"| C

  BF["Blizzard ChatFrameUtil filter\n19-argument tuple"] -->|"canaccessallvalues"| C
  C -->|"arg1-only callback input"| F["Timestamps / UrlCopy / other filters"]
  F -->|"discard or optional arg1 replacement"| C
  C -->|"no-op: false\ntext changed: full 19-field tuple"| BF

  BA["ChatFrame:AddMessage"] -->|"accessible rendered text + numeric colors"| C
  C --> R["Restore"]
  C --> K["Ticker"]
  C --> A["Alerts"]
  C --> X["CopyOverlay consumers"]

  C --> P["Style / Colors / Resize"]
  C --> I["Dock / Controls / ChatBar"]
  C --> B["Cleaner / Sticky"]

  T --> O["Options.lua"]
  O --> C
  T --> L["ThirdParty libraries"]
  T -. "disabled" .-> H["Legacy History.lua"]
```

The filter path and post-render `AddMessage` path are separate trust boundaries. No-op filters leave Blizzard's current secure tuple in place; a changed `arg1` is returned with all remaining fields preserved. Raw filter tuples and trailing opaque render metadata must not enter module state or SavedVariables.
