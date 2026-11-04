# In-house addon implementation review — 2026-11-04

## Scope and evidence boundary

This is a task-relevant audit of public repositories under `UnknownAlienHuman`, not a claim that every line of every addon was reviewed. World of Warcraft client contracts and the engineering KB remain authoritative; sibling addons are donor evidence only.

Reviewed references:

- engineering KB: `UnknownAlienHuman/wow-addon-engineering-kb@c2a630aa186de401262663cc8568a77988be69df`;
- Roth UI: `UnknownAlienHuman/roth-ui@97a5534d3fd8bd28d870c7dc3968ce16d3a70c71`;
- Roth Tooltip: `UnknownAlienHuman/roth-tooltip@5ace4eee2dd0cca1d763e35603065e28ca1b7d8d`;
- Roth Dev Lib: `UnknownAlienHuman/roth-dev-lib@9f1e2bbfe1b7bcf33a28d7981605f80d1977ca64`;
- Roth Secret Tester: `UnknownAlienHuman/roth-secret-tester@861167b778a4aa1d23e690a00a54cd86562398e4`;
- WoW Dev Framework: `UnknownAlienHuman/WoW-Dev-Framework@336345324265a299f1ad7c177ff541e5ff00b730`;
- Sudden Doom Glow: `UnknownAlienHuman/sudden-doom-glow@f693bee6384f2ca8911892e9d8bd3026c77183f9`.

External chat-addon evidence is maintained separately in `RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md`.

## Roth UI

Inspected task-relevant safety, Settings and release paths, especially `core/safety.lua`, `core/settings_main.lua` and `tools/package_release.py`.

Useful patterns:

- script-object capability checks protect method lookup, invocation and returned booleans independently;
- constrained objects fail closed unless current context explicitly authorizes access;
- Settings construction has one owner, while a small adapter waits for `Blizzard_Settings`;
- release contents are derived from the actual TOC/XML load graph;
- deterministic ZIP entries use fixed timestamps, sorted paths and exact byte verification;
- the package contains one addon root and rejects service/development files.

Applied to Roth Chat:

- `CanAccessObject` protects optional security-method lookup and gates every result;
- table access has a separate fail-closed boundary;
- `Options.lua` remains the sole category/control owner;
- `OptionsBootstrap.lua` performs the bounded late-load handshake;
- `scripts/project.py` is the single TOC/XML graph owner for validation and packaging;
- `scripts/package.py` creates and verifies a deterministic single-root install archive.

## Roth Tooltip

Inspected `Engine/Safe.lua` and its integration boundary.

Useful patterns:

- validate values at the use site rather than relying on an earlier observation;
- isolate callback failure with symbolic ordinary labels;
- avoid retaining raw failures or opaque values in diagnostics.

Applied to Roth Chat:

- message-filter, displayed-message and internal-listener failures are isolated per stable registration;
- raw callback exceptions and chat tuples remain uninspected and unretained;
- repeated failures use bounded suppression rather than hot-path output storms.

## Sudden Doom Glow

Inspected `scripts/package.py` and its release documentation.

Useful patterns:

- use an explicit package allowlist rather than zipping the repository;
- use fixed ZIP metadata and permissions;
- fail if TOC runtime entries diverge from the release model;
- build a single installable root and keep tests/scripts out of the archive.

Roth Chat adopts the deterministic archive discipline but derives runtime files recursively from its TOC/XML graph because its library load graph is larger and already validated centrally.

## Roth Dev Lib

Roth Dev Lib is an explicit diagnostic product with broader capture responsibilities. No organization-wide production dependency was proven during this audit.

Decision:

- do not add a hidden or mandatory Roth Dev Lib dependency;
- keep Roth Chat diagnostics narrow, symbolic, bounded and content-free;
- use Roth Dev Lib separately during deliberate live investigation.

## Roth Secret Tester

Useful boundary:

- high-risk access experiments belong in a dedicated diagnostic addon;
- retained evidence needs strict caps and explicit purge behavior;
- absence of an error is not proof of safe access.

Decision: keep speculative SecretValue probes out of production Roth Chat and require Retail validation for actual access/taint claims.

## WoW Dev Framework

Useful workflow patterns:

- verify the actual repository and permissions before edits;
- keep implementation, validation evidence and release claims separate;
- use exact commit/tree identities for gates.

Decision: adopt the workflow discipline, not another runtime framework layer.

## Resulting completed Roth Chat passes

### Access and diagnostics

PR #21 produced tree `93efec74db855d1b177f576bf725e4ff2c0b679d`, merged as `98a671173f6a127f04d10730989a85d7af3d8e98`.

It added fail-closed table access, atomic table snapshot copying, ordinary-only scheduler metadata, protected security-method lookup and independent bounded diagnostics for each `AddMessage` observer.

### Settings load order

PR #22 produced tree `1881a5bf8c7aa19aa644f48adb69f060dc972b5b`, merged as `fa853d7210947f2035933196983fef374c8df390`.

It added one late-load Settings handshake, `EventUtil.ContinueOnAddOnLoaded` integration with a bounded fallback, listener retirement and idempotent category registration without eager `Blizzard_Settings` loading.

## Explicitly rejected

- no mandatory shared diagnostic-library dependency;
- no generic framework copied into addon runtime;
- no second Settings or message-dispatch owner;
- no raw callback errors, chat tuples or inaccessible values in diagnostics;
- no full custom chat renderer or copied Blizzard message handler;
- no repository-wide ZIP containing tests, workflows, research or agent files;
- no performance or live-client claim without measurement.

## Remaining boundary

Static contracts cover the adopted patterns on Lua 5.1 and Lua 5.4. Live Retail behavior, taint, actual restricted-value transitions, Settings load timing and interaction with other installed addons remain **NOT RUN** until the in-client matrix is executed.
