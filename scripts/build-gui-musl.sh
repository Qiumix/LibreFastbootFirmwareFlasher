#!/bin/sh
# Build lfff-gui as a dynamically linked musl binary, for Void, Alpine and
# other distributions without glibc. Runs inside the rust:alpine image; CI and
# local builds use it the same way:
#
#   docker run --rm -v "$PWD":/src -w /src rust:alpine \
#       scripts/build-gui-musl.sh "$(id -u):$(id -g)"
#
# The optional argument hands the build tree back to that user afterwards,
# since the container runs as root.
#
# Why these particular choices:
#   - Dynamic, not static. The window and GPU libraries are dlopen'd, and
#     dlopen always fails in a static musl binary, so a static GUI could never
#     open a window. It also matters for the build scripts: bindgen loads
#     libclang through dlopen.
#   - Alpine, because rust-skia's musl support is written against it
#     (build_support/platform/alpine.rs), and rust-skia publishes no prebuilt
#     musl skia — so skia compiles from source, which is what makes this slow.
#   - System gn and ninja, because the ones bundled with skia-bindings are
#     glibc binaries and do not run here.
set -eu

owner="${1:-}"
if [ -n "$owner" ]; then
    trap 'chown -R "$owner" "$CARGO_TARGET_DIR" "$CARGO_HOME" 2>/dev/null || true' EXIT
fi

: "${CARGO_TARGET_DIR:=$PWD/target/musl}"
: "${CARGO_HOME:=$PWD/target/musl-cargo}"
export CARGO_TARGET_DIR CARGO_HOME
export RUSTFLAGS="-C target-feature=-crt-static"

apk add --no-cache \
    build-base clang-dev llvm-dev python3 gn samurai git curl cmake perl \
    pkgconf linux-headers file fontconfig-dev freetype-dev libxkbcommon-dev \
    wayland-dev mesa-dev libx11-dev libxcursor-dev libxi-dev libxrandr-dev \
    libxcb-dev >/dev/null

SKIA_GN_COMMAND="$(command -v gn)"
SKIA_NINJA_COMMAND="$(command -v ninja)"
export SKIA_GN_COMMAND SKIA_NINJA_COMMAND

echo "rustc $(rustc --version | cut -d' ' -f2), g++ $(g++ -dumpversion)"
cargo build --release -p lfff-gui

bin="$CARGO_TARGET_DIR/release/lfff-gui"
file "$bin"
# Must be dynamic, and against musl — see the top of this file.
readelf -l "$bin" | grep -q 'ld-musl-' || {
    echo "error: $bin is not a dynamically linked musl binary" >&2
    exit 1
}
