# Package Workflow

The package index is checked in and managed by the scripts in [`scripts/`](scripts/). Run commands from the
repository root. Do not create wrappers or edit `_Index/default.project.json` manually.

## Create a package

```bash
python3 scripts/package_manager.py create example
```

This creates `src/_Index/quenty_example@0.0.1/package.json` and registers the logical package
`quenty/example@0.0.1`. Then:

1. Add strict implementation modules inside that directory.
2. Add consumer-facing entries to the manifest's `exports` map, for example:

   ```json
   "exports": {
     "Example": "Example",
     "ExampleUtils": "ExampleUtils"
   }
   ```

3. Use relative imports between modules in the package and flat `@game/ReplicatedStorage/Packages/<Export>`
   imports for other packages.
4. Add the package to `PKGINFO.md`, including its directory row, package card, and production submodules.
5. Run `python3 scripts/sync_packages.py` to generate typed surface modules and dependency metadata.

## Update a package

Edit its indexed implementation, tests, README, export map, and `PKGINFO.md` entry. Afterward run:

```bash
python3 scripts/sync_packages.py
stylua src
selene src
python3 scripts/sync_packages.py --check
```

When publishing a new indexed revision, update its version with:

```bash
python3 scripts/package_manager.py set-version example 0.1.0
```

Use patch versions for compatible fixes, minor versions for compatible features, and major versions for breaking
public API changes. The command renames the backing directory and updates wrappers, dependency versions, and the
Rojo index map. It also rewrites that package's versioned paths in `PKGINFO.md`.

## Remove a package

First remove its imports from dependents and remove its `PKGINFO.md` directory row and package card. Then verify the
tree with `python3 scripts/sync_packages.py` and remove the package explicitly with:

```bash
python3 scripts/package_manager.py remove example --yes
```

Removal is refused while another indexed package still declares the target as a dependency. Successful removal
also deletes obsolete generated surface wrappers.

## CI verification

```bash
python3 scripts/sync_packages.py --check
stylua --check src
selene src
rojo build default.project.json --output /tmp/nevermore.rbxm
```

`sync_packages.py --check` fails when wrappers, forwarded types, manifests, dependency versions, or the logical
`quenty/<package>@<version>` Rojo mapping have drifted. It also verifies that `PKGINFO.md` has exactly one card for
every indexed package and an accurate coverage count.
