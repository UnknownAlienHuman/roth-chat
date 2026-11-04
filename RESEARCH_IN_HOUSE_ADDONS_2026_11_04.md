# In-house addon implementation review — 2026-11-04

## Scope and evidence boundary

This review was performed after inventorying the public repositories under `UnknownAlienHuman`. It is a task-relevant implementation audit for Roth Chat, not a claim that every line of every addon was reviewed.

Authoritative product rules remain the World of Warcraft client contracts and the engineering KB. Other addons are donor evidence only: patterns are adopted only after they fit Roth Chat's ownership, security, performance, and license boundaries.

Reviewed references:

- engineering KB: `UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`;
- Roth UI: `UnknownAlienHuman/roth-ui@97a5534d3fd8bd28d870c7dc3968ce16d3a70c71`;
- Roth Tooltip: `UnknownAlienHuman/roth-tooltip@5ace4eee2dd0cca1d763e35603065e28ca1b7d8d`;
- Roth Dev Lib: `UnknownAlienHuman/roth-dev-lib@9f1e2bbfe1b7bcf33a28d7981605f80d1977ca64`;
- Roth Secret Tester: `UnknownAlienHuman/roth-secret-tester@861167b778a4aa1d23e690a00a54cd86562398e4`;
- WoW Dev Framework: `UnknownAlienHuman/WoW-Dev-Framework@336345324265a299f1ad7c177ff541e5ff00b730`.

The existing external review remains in `RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md`. It covers source-pinned Chattynator, Prat, LS: Glass, and original Glass evidence; those third-party snapshots are not silently treated as current upstream behavior.

## Roth UI

Inspected task-relevant safety and Settings paths, especially `core/safety.lua` and `core/settings_main.lua`.

Useful patterns:

- script-object capability checks protect method lookup, method invocation, and returned booleans independently;
- constrained objects fail closed unless the current context explicitly authorizes access;
- Settings construction has one owner, while a small load-order adapter waits for `Blizzard_Settings`;
- normal login does not eagerly load a large Blizzard UI addon solely to construct settings.

Applied to Roth Chat:

- `CanAccessObject` now protects optional security-method lookup and gates every result;
- table access has a separate fail-closed boundary;
- `Options.lua` remains the sole category/control owner;
- `OptionsBootstrap.lua` performs the bounded late-load handshake.

## Roth Tooltip

Inspected `Engine/Safe.lua` and its integration boundary.

Useful patterns:

- validate values at the use site rather than relying on an earlier observation;
- isolate callback failure with symbolic ordinary labels;
- avoid retaining raw failures or opaque values in diagnostics.

Applied to Roth Chat:

- message-filter and displayed-message observer failures are isolated per stable registration;
- raw callback exceptions and chat tuples remain uninspected and unretained;
- repeated failures use bounded suppression rather than repeated hot-path output.

## Roth Dev Lib

Inspected the agent guide, code index, and repository-wide integration references.

Classification:

- Roth Dev Lib is an explicit diagnostic product with broader, higher-risk capture responsibilities;
- no consumer of `RDL:InitAddon` was found in the organization-wide code search during this audit;
- it is not a proven shared runtime substrate for production addons.

Decision:

- do not add a hidden or mandatory Roth Dev Lib dependency to Roth Chat;
- keep Roth Chat's production diagnostics narrow, symbolic, bounded, and content-free;
- use Roth Dev Lib separately during live investigation when its explicit diagnostic scope is desired.

## Roth Secret Tester

Inspected its project guidance and bounded evidence model.

Useful patterns:

- high-risk access experiments belong in a dedicated diagnostic addon, not production feature code;
- retained evidence needs strict caps and explicit purge behavior;
- absence of an error is not proof of safe access.

Decision:

- keep speculative SecretValue probes out of Roth Chat;
- use executable mocks only for local contracts and require Retail validation for actual access/taint claims.

## WoW Dev Framework

Inspected project instructions and connected-path workflow conventions.

Useful patterns:

- verify the actual repository path and permissions before edits;
- keep implementation, validation evidence, and release claims separate;
- use exact commit/tree identities for gates.

Decision:

- adopt the workflow discipline, not the framework as runtime addon code;
- retain Roth Chat's small first-party owners instead of introducing another abstraction layer.

## Resulting Roth Chat changes

### Access and diagnostics pass

PR #21 produced tree `93efec74db855d1b177f576bf725e4ff2c0b679d`, merged as `98a671173f6a127f04d10730989a85d7af3d8e98`.

It added:

- fail-closed table-access probing;
- atomic table snapshot copying after successful traversal;
- ordinary-only scheduler identity and retained job metadata;
- protected object security-method lookup and result gating;
- independent bounded diagnostics for each `AddMessage` observer.

### Settings load-order pass

PR #22 produced tree `1881a5bf8c7aa19aa644f48adb69f060dc972b5b`, merged as `fa853d7210947f2035933196983fef374c8df390`.

It added:

- one late-load Settings handshake without a second `InitOptions` owner;
- `EventUtil.ContinueOnAddOnLoaded` integration with a bounded `ADDON_LOADED` fallback;
- listener retirement and idempotent category registration;
- no eager `Blizzard_Settings` load during normal login.

## Explicitly rejected

- no mandatory shared diagnostic-library dependency;
- no generic framework copied into addon runtime;
- no second Settings category owner;
- no raw callback errors, chat tuples, or inaccessible values in diagnostics;
- no full custom chat renderer or copied Blizzard message handler;
- no performance claim without measurement.

## Remaining boundary

Static contracts now cover the adopted patterns on Lua 5.1 and Lua 5.4. Live Retail behavior, taint, actual restricted-value transitions, Blizzard Settings load timing, and interaction with other installed addons remain **NOT RUN** until the in-client matrix is executed.
