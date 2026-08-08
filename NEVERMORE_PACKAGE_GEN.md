# Nevermore package generator

`nevermore_package_gen.py` creates loader-free package folders for a project. It follows imports from each selected package, includes every transitive dependency, rewrites imports to `require(Packages.<Package>.<Module>)`, and writes the result to `roblox_packages`.

Copy `.nevermore.toml.example` to `.nevermore.toml`, select the package folders you need, then run:

```bash
python3 nevermore_package_gen.py
```

The output folder is safe to delete and regenerate. Change `source` or `output` in the `[nevermore]` table when using a different checkout or destination. Dependencies that are supplied by another package repository can be listed with `external`.
