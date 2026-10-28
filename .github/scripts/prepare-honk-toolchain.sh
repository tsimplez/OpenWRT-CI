#!/bin/bash
# Install honk's own pinned Rust and eBPF tools alongside the normal feed toolchain.
set -euo pipefail

grep -qE '^CONFIG_PACKAGE_honk=(y|m)$' .config || exit 0
HONK_SRC="$PWD/package/honk/src"
if grep -qx 'CONFIG_aarch64=y' .config; then
	HONK_TARGET=aarch64-unknown-linux-musl
elif grep -qx 'CONFIG_x86_64=y' .config; then
	HONK_TARGET=x86_64-unknown-linux-musl
else
	echo "honk: only aarch64 and x86_64 are supported" >&2
	exit 1
fi

RUSTUP_BIN=$(command -v rustup || true)
if [ -z "$RUSTUP_BIN" ] && [ -x "$HOME/.cargo/bin/rustup" ]; then
	RUSTUP_BIN="$HOME/.cargo/bin/rustup"
fi
test -x "$RUSTUP_BIN"
STABLE=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["toolchain"]["channel"])' "$HONK_SRC/rust-toolchain.toml")
NIGHTLY=$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["toolchain"]["channel"])' "$HONK_SRC/crates/honk-ebpf/rust-toolchain.toml")
"$RUSTUP_BIN" toolchain install "$STABLE" --profile minimal --target "$HONK_TARGET"
"$RUSTUP_BIN" toolchain install "$NIGHTLY" --profile minimal --component rust-src --component llvm-tools

# A dedicated directory keeps bpf-linker and rustup proxies ahead of OpenWrt's PATH.
HONK_TOOLCHAIN_BIN="${RUNNER_TEMP:-/tmp}/honk-toolchain/bin"
mkdir -p "$HONK_TOOLCHAIN_BIN"
for tool in rustup cargo rustc rustdoc; do
	ln -sf "$RUSTUP_BIN" "$HONK_TOOLCHAIN_BIN/$tool"
done
BPF_LINKER_VERSION=$(sed -n 's/^BPF_LINKER_VERSION=//p' "$HONK_SRC/.github/ci/pins.env")
BPF_LINKER_SHA256=$(sed -n 's/^BPF_LINKER_SHA256=//p' "$HONK_SRC/.github/ci/pins.env")
test -n "$BPF_LINKER_VERSION"
[[ "$BPF_LINKER_SHA256" =~ ^[0-9a-f]{64}$ ]]
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
curl -fL --retry 3 -o "$TEMP_DIR/bpf-linker.tar.zst" \
	"https://github.com/aya-rs/bpf-linker/releases/download/v${BPF_LINKER_VERSION}/bpf-linker-x86_64-unknown-linux-musl.tar.zst"
echo "$BPF_LINKER_SHA256  $TEMP_DIR/bpf-linker.tar.zst" | sha256sum -c -
tar --zstd -xf "$TEMP_DIR/bpf-linker.tar.zst" -C "$HONK_TOOLCHAIN_BIN"
"$HONK_TOOLCHAIN_BIN/bpf-linker" --version

echo "HONK_TOOLCHAIN_BIN=$HONK_TOOLCHAIN_BIN" >> "${GITHUB_ENV:?GITHUB_ENV is required}"
REPORT_DIR="${GITHUB_WORKSPACE:-$PWD}/build-reports"
mkdir -p "$REPORT_DIR"
{
	printf 'Rust: %s\neBPF Rust: %s\nTarget: %s\n' "$STABLE" "$NIGHTLY" "$HONK_TARGET"
	grep -E '^(DOONA_|BPF_LINKER_)' "$HONK_SRC/.github/ci/pins.env"
} | tee "$REPORT_DIR/honk-toolchain.txt"
