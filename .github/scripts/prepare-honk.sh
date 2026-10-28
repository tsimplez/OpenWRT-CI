#!/bin/bash
# Import the official source recipes without replacing the existing dae/daed/BTF packages.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
# Keep the recipe, backend and its embedded doona version reproducible.
FEED_COMMIT=fcbc57abdec03713f877ed855d2c56a17429f35c
HONK_TAG=v0.1.0-beta.1

test -d ./package
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
git -C "$TEMP_DIR" init -q
git -C "$TEMP_DIR" remote add origin https://github.com/daeuniverse/openwrt-packages.git
git -C "$TEMP_DIR" fetch --depth=1 origin "$FEED_COMMIT"
git -C "$TEMP_DIR" checkout -q --detach FETCH_HEAD

for name in honk luci-app-honk luci-lib-daeuniverse; do
	# Remove only exact-name feed recipes; substring matching would also remove daed.
	find ./feeds/packages/ ./feeds/luci/ -mindepth 1 -maxdepth 3 -type d -name "$name" \
		-prune -exec rm -rf {} +
	if [ -e "./package/$name" ]; then
		echo "honk: package/$name already exists" >&2
		exit 1
	fi
	cp -a "$TEMP_DIR/$name" ./package/
done

git clone --depth=1 --single-branch --branch "$HONK_TAG" \
	https://github.com/daeuniverse/honk.git ./package/honk/src

python3 - "$PROJECT_DIR/Config/honk.dae" "${WRT_IP:?WRT_IP is required}" <<'PY'
import ipaddress
from pathlib import Path
import sys

def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise SystemExit(f"honk: unexpected upstream content in {path}: {before!r}")
    path.write_text(text.replace(before, after))

package = Path("package/honk")
makefile = package / "Makefile"
# This firmware builds its own BTF; detached BTF is only needed without it.
replace_once(makefile, "DEPENDS:=+libstdcpp", "DEPENDS:=@(aarch64||x86_64) +libstdcpp")
replace_once(makefile, "+vmlinux-btf", "+!KERNEL_DEBUG_INFO_BTF:vmlinux-btf")
replace_once(makefile, "/etc/honk/config.dae\nendef", "/etc/honk/\nendef")
# OpenWrt prepends staging_dir/host/bin, whose bare Cargo cannot select +nightly.
# Use rustup proxies for honk and its nested eBPF build only.
replace_once(package / "build.sh", "set -eu\n", '''set -eu
PATH="${HONK_TOOLCHAIN_BIN:?run prepare-honk-toolchain.sh before building}:$PATH"
export PATH
unset RUSTUP_TOOLCHAIN
''')
replace_once(package / "build.sh", "cargo build --release", "cargo build --locked --release")

# The official init script checks dae; this firmware also includes daed.
replace_once(package / "files/honk.init", '\tlocal config_file\n', '''\tif ubus call service list '{"name":"daed"}' 2>/dev/null |
\t\tjsonfilter -q -e '@.daed.instances[*].running' | grep -q true; then
\t\tlogger -t honk "daed is running; disable and stop daed before starting honk"
\t\treturn 1
\tfi

\tmkdir -p /etc/honk/data
\tchmod 0700 /etc/honk /etc/honk/data

\tlocal config_file
''')
lan_ip = ipaddress.IPv4Address(sys.argv[2])
config = Path(sys.argv[1]).read_text().replace("@LAN_IP@", str(lan_ip))
(package / "files/config.dae").write_text(config)
PY

echo "honk: official feed $FEED_COMMIT; backend $HONK_TAG"
grep '^DOONA_' ./package/honk/src/.github/ci/pins.env
grep -q "option enabled '0'" ./package/honk/files/honk.config
