# Roth Chat architecture

## Runtime owners

Roth Chat is an adapter around Blizzard's chat system. The client owns chat event production, message formatting and routing, rendered history, and `ScrollingMessageFrame` behavior. Roth Chat adds module lifecycle, presentation, controls, limited transformations, and bounded durable restore for permanent windows.

| File | Owns |
|---|---|
| `Util.lua` | Ordinary-value access helpers, safe numbers/text, keyed scheduling and cancellation, fade drivers, bounded data helpers. |
| `Platform.lua` | Current-client diagnostics, frame/API adapters, frame discovery and identity, native chat-history collection, and restriction queries. |
| `VisualPrimitives.lua` | Applied visual decoration: glass gradients, backdrops, borders, highlights, sizing, and cleanup. |
| `ChatText.lua` | Accessible-text timestamp, durable-storage, and copy transformations. It does not declassify inaccessible content. |
| `Core.lua` | SavedVariables/configuration, module registration and lifecycle, feature presets, and keyed combat deferral. |
| `CoreListeners.lua` | Mutation-safe internal event bus and owner cleanup. |
| `CoreDispatch.lua` | Sole owner of message-event filters and displayed-message `AddMessage` observers. |
| `ChatLifecycle.lua` | Coalesced chat-frame lifecycle router around native frame events and stable `FCF_*` post-hooks. |
| `Options.lua` | Blizzard Settings categories, controls, module toggles, and configuration UI. |
| `Modules/*.lua` | Independent feature behavior registered through Core and shared adapters. |

`Modules/StyleOwnership.lua` and `Modules/ControlsOwnership.lua` are no longer separate runtime files; their ownership is folded into the owning feature modules. The former `Modules/History.lua` has been removed. `Modules/Restore.lua` is the sole addon persistence owner. No new `RothChatDB.history` table is allocated, and pre-existing history data is left untouched.

Bundled LibStub, CallbackHandler, and LibSharedMedia are loaded before Roth Chat's runtime files. The active file order is declared in `RothChat.toc`; keep the TOC synchronized when adding or moving a runtime owner.

## Startup and module state

1. Blizzard loads libraries, shared helpers, adapters, Core owners, feature modules, and settings in TOC order.
2. Modules register their definitions. Core initializes `RothChatDB`, applies defaults only for missing values, and initializes configured modules.
3. Successful `OnEnable` completion marks a module active. Core delivers `OnLogin` once after login; a module activated later receives its one-time notification after activation.
4. Disable transitions make the module inactive, run module cleanup, and remove owner listeners, filters, and `AddMessage` callbacks.
5. Native update events and `FCF_*` post-hooks enqueue chat lifecycle work. `ChatLifecycle.lua` coalesces the work into a single next-frame refresh.

Configured state and runtime-active state differ. Hot callbacks must use `core:IsModuleActive(name)` or the module's established active guard; a checked settings box alone does not establish that `OnEnable` succeeded.

Core's frame event handler translates `ADDON_RESTRICTION_STATE_CHANGED` into the internal `CHAT_RESTRICTION_CHANGED` event with a plain boolean. Modules clear temporary content when restriction begins and do not retain opaque payloads for replay when access returns.

## Chat message flow

Blizzard's native chat history and rendering remain enabled. Roth Chat registers a single dispatcher per message event through the client adapter. The dispatcher gates the entire synchronous tuple before any module callback, packs exactly the received tuple, and calls priority-ordered feature filters. A no-op returns `false` only; a discard returns `true` only; a text change replaces only `arg1` and returns the exact received arity with interior and trailing `nil` values preserved. Unchanged secure tuples are left to Blizzard.

The displayed-message path installs one post-hook per active chat frame. Before invoking feature callbacks, Core rejects chat lockdown, inaccessible frames, and inaccessible/non-string text, and clamps RGB values. It forwards only `(frame, text, safeR, safeG, safeB)`; line IDs, access IDs, and unknown trailing metadata do not enter feature state. Restore, Ticker, Alerts, and Controls consume this optional display feed according to their own policy. Filter and display callbacks are not guaranteed when the client blocks access.

## Persistence and text boundaries

`ChatText.lua` is the shared boundary for timestamp removal/formatting, stable durable text, and copy normalization. Durable text is sanitized before retention so session-only account-name, Battle.net, and censored-message handles do not become SavedVariables content. The original Blizzard display remains responsible for live rendering.

Restore stores bounded records for permanent indexed chat windows. Its current row shape keeps timestamp metadata, timestamp-free durable text, sanitized RGB, and a schema marker in separate slots. Temporary whisper windows are excluded because Blizzard can reuse them. Unknown newer or invalid schema versions suspend Restore history access while leaving the store untouched. Unavailable identity data or message counts never stand in for an empty window. Restore snapshots the fade properties it owns and restores the snapshots when disabled. It does not eagerly rewrite the full database.

Blizzard's `HistoryKeeper` remains available to the native chat input/history path. Roth Chat neither replaces it nor treats it as the addon scrollback store. Copy tools prefer eligible Restore data and can use native/frame text fallbacks; they apply the current copy timestamp setting once. CopyOverlay and the URL popup clear their edit-box contents and close on restriction entry.

## Frame lifecycle and presentation

`ChatLifecycle.lua` coalesces native update signals and stable post-hooks such as window open, close, selection, docking, and reset. It discovers active frames, installs missing `AddMessage` observers, then emits internal ready/closed/layout events. Feature modules subscribe through the owner-aware Core bus rather than adding competing global frame scans.

Each observed frame installs subscription-mutation post-hooks once, before message observation. Native group/channel changes and `FCF_SetWindowName` invalidate the layout revision synchronously, while presentation refresh remains coalesced. Restore rechecks current name/list accessibility before consulting the fingerprint cache; `GetChatLayoutRevision(frame)` declines caching if the frame's invalidation hooks are incomplete. These boundaries follow the selected [ChatFrame mixin](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrame.lua) and [FloatingChatFrame setters](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua).

Controls owns its chat mouse-wheel script while active and delegates to the captured original when inactive. ChatBar transfers accessory hover ownership as the selected frame changes. Style applies its own appearance and restores owned state when disabled. Resize and Dock cancel interrupted work and schedule bounded follow-up work. Restore owns its fade settings. Ticker owns the primary frame's immersion alpha, while Controls owns hover alpha; CopyOverlay snapshots/restores its temporary modal state and emits a visibility event so active owners can recompute the final alpha.

Controls restores wheel/clipping values only while they still match its writes. Cleaner relinquishes a format changed by another owner. Alerts tracks only flashes it started and leaves pre-existing native flashes alone on teardown.

`VisualPrimitives.lua` contains the decoration actually applied by modules. It is distinct from `Platform.lua`: the latter adapts current client APIs and does not own presentation. Existing provenance comments identify LS: Glass-derived material; see `ThirdParty/ATTRIBUTIONS.md` and the bundled Apache-2.0 license.

## Scheduling, restrictions, and performance

The shared scheduler coalesces keyed jobs and removes its update driver when idle. Fade updates likewise run only while work is pending and validate completion identity after reentrant cancellation or replacement. Ticker uses a 100-slot ring with preview text capped at 1,024 UTF-8 characters plus a truncation marker. Restore retention is bounded; chat lifecycle updates coalesce; callbacks do not scan the entire retained history per message. Combat-deferred operations use stable keys and preserve required argument arity. Callback result forwarding allocates no result table, and registries compact only after removals.

`NS.CanAccessValue` is the operational gate for values; object/table access uses `NS.CanAccessObject`. Check accessibility before comparison, formatting, concatenation, retention, or table traversal. Chat messaging lockdown is a separate boundary: when active, modules drop processing and discard pending content work rather than replaying content after the transition.

## Settings and themes

Blizzard Settings expose **Minimal**, **Obsidian**, and **Ember** appearance presets, along with font and size presets. Composite preset setters persist through Core, then notify the dependent registered Settings variables. The rest of the settings cover appearance, chat fading, hover behavior, ticker animation, controls, timestamps, cleaner behavior, copy policy, and Restore limits. The values and defaults live in Core; controls and presentation live in `Options.lua` and the owning modules. Keep user choices during migrations: defaults apply only to missing values.

## External implementation and license boundary

Roth Chat selectively reuses design concepts from the PR5 work based at `main@3c995183626002965043e38a837346fb290acd8a` and reviewed in `40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f`; its current implementation remains separately owned and should be audited against the current APIs. The pinned external implementation review is retained in `RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md`. It documents why Roth Chat does not replace Blizzard rendering, copy Blizzard message handlers, or transplant third-party code. Chattynator implementation evidence in that review comes from a non-authoritative public fork snapshot. Prat and glass projects have separate source and license boundaries.

Exact third-party file provenance is in `ThirdParty/ATTRIBUTIONS.md`. LS: Glass-derived assets/adaptations remain Apache-2.0; original Glass assets remain MIT; vendored libraries retain their own notices. Do not merge the two Glass attributions or remove licenses from a release package.

## Validation status

The expected target is Retail `12.1.5.70688`, interface `120105`, addon `1.2.0`; the checked source export and reference pins are dated 2026-11-02. Automated checks are defined in `.github/workflows/validate.yml`. **Live-client validation is NOT RUN.** See [docs/VALIDATION.md](docs/VALIDATION.md) for evidence, commands, and the remaining runtime matrix.
