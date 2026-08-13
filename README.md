# Nevermore Fork

This repository mounts its package tree at `ReplicatedStorage.Packages`.

Consumer-facing modules are flat exports:

```luau
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
```

Implementations live in the flat `_Index` hierarchy. Rojo maps filesystem-safe directories such as
`src/_Index/quenty_maid@0.0.1` to direct `_Index` children named `quenty/maid@0.0.1`. There is no
intermediate `quenty` folder.

Each indexed package contains a `package.json` manifest with:

- its logical `quenty/<package>` name and version;
- the flat modules it exports;
- dependencies on other indexed packages; and
- external modules that must be supplied by a consuming game or test environment.

An `init.luau` package module imports its children through `@self/<Child>`; ordinary modules use `./` and `../`
paths for siblings and parent siblings. Cross-package imports go through the flat
`ReplicatedStorage.Packages` exports. The old recursive Loader is not part of this layout.

Tests and private implementation modules stay inside their indexed package and do not receive flat wrappers.

See [PACKAGE_WORKFLOW.md](PACKAGE_WORKFLOW.md) for the create, update, version, removal, and CI workflows.
