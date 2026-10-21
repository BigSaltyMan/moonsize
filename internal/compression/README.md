# Pinned synchronous gzip implementation

This directory contains the runtime-only gzip/flate/checksum packages from
`bikallem/compress@0.3.4` and the byte helpers from `bikallem/blit@0.2.2`.
Both upstream module manifests declare Apache-2.0. The upstream ZIPs do not
include a license text; the unmodified Apache-2.0 text is supplied as LICENSE.
Attribution and origins remain here; this is not original moonsize code.

Sources:

- https://github.com/bikallem/compress
- https://download.mooncakes.io/user/bikallem/compress/0.3.4.zip
- https://github.com/bikallem/blit
- https://download.mooncakes.io/user/bikallem/blit/0.2.2.zip

The registry packages still use moon.mod.json, which the Mooncakes documentation
builder now rejects. Vendoring this bounded synchronous subset removes that
dependency chain without replacing the compressor or changing its defaults.
Async adapters, unrelated compression algorithms and upstream tests are not copied.
Existing moonsize compression/round-trip tests exercise this implementation.

Import paths, native C symbol names, formatting and equivalent deprecated syntax
are adapted; explicit Show rendering is retained for errors. Namespacing avoids
collisions when a consumer also uses the upstream packages. `provenance.json`
records the exact archive hashes, original per-file hashes and adapted hashes.
All package configurations use moon.pkg. No nested moon.mod or old JSON manifest
is shipped. Other files retain their original content and comments.

To update, download and hash the pinned registry ZIPs, select only the immediate
runtime .mbt/.c and moon.pkg files in gzip/flate/checksum and blit/src, rewrite
the imports to this directory and prefix native symbols with moonsize_vendor_.
Update provenance deliberately, then run the integrity check, compression tests,
both supported toolchain checks and native documentation generation. Do not
silently change compression defaults or rewrite historical measured examples.
