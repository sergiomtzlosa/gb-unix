# Bundled RGBDS

Prebuilt RGBDS v1.0.4 binaries, grouped by host platform. The top-level
Makefile picks the directory matching `uname -s` and `uname -m`, lowercased,
with `amd64` normalized to `x86_64` and `aarch64` normalized to `arm64`:

| Directory | Host |
|---|---|
| `linux-x86_64/` | Linux on x86-64 |
| `darwin-arm64/` | macOS on Apple Silicon |
| `darwin-x86_64/` | macOS on Intel (or Apple Silicon under Rosetta) |

Each directory contains `rgbasm`, `rgblink`, `rgbfix`, and `rgbgfx`.

The Linux binaries are statically linked ELF builds. The macOS binaries were
compiled from the RGBDS v1.0.4 source with Apple clang against a static
libpng 1.6.59, so `rgbgfx` only depends on the system `libz`, `libc++`, and
`libSystem`.

If no bundled directory matches the host, the Makefile falls back to
`rgbasm`, `rgblink`, and `rgbfix` from `PATH`. To force a specific directory:

```sh
make RGBDS_DIR=/path/to/rgbds/bin
```

RGBDS is distributed under the MIT license; see `LICENSE`. The macOS
`rgbgfx` binaries statically link libpng; see `LICENSE.libpng`.
