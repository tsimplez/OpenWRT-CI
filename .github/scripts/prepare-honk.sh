#!/bin/bash
# Import the official source recipes without replacing the existing dae/daed/BTF packages.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
test -d ./package
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
# Refresh versions for every build, then keep that selection throughout the build.
VERSIONS_FILE="$TEMP_DIR/honk-versions.json"
python3 "$SCRIPT_DIR/resolve-honk-versions.py" "$VERSIONS_FILE"
HONK_TAG=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["honk"]["tag"])' "$VERSIONS_FILE")

git -C "$TEMP_DIR" init -q
git -C "$TEMP_DIR" remote add origin https://github.com/daeuniverse/openwrt-packages.git
git -C "$TEMP_DIR" fetch --depth=1 origin HEAD
git -C "$TEMP_DIR" checkout -q --detach FETCH_HEAD
FEED_COMMIT=$(git -C "$TEMP_DIR" rev-parse HEAD)

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

python3 - "$PROJECT_DIR/Config/honk.dae" "${WRT_IP:?WRT_IP is required}" "$VERSIONS_FILE" "$FEED_COMMIT" <<'PY'
import ipaddress
import json
from pathlib import Path
import re
import subprocess
import sys

def replace_once(path, before, after):
    text = path.read_text()
    count = text.count(before)
    if count != 1:
        raise SystemExit(f"honk: expected one occurrence in {path}, found {count}: {before!r}")
    path.write_text(text.replace(before, after))

def replace_setting(path, key, separator, value):
    text, count = re.subn(rf"^{re.escape(key)}{re.escape(separator)}.*$",
                          f"{key}{separator}{value}", path.read_text(), flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"honk: expected one {key} setting in {path}, found {count}")
    path.write_text(text)

versions_path = Path(sys.argv[3])
versions = json.loads(versions_path.read_text())
versions["feed_revision"] = sys.argv[4]
package = Path("package/honk")
makefile = package / "Makefile"
source = package / "src"
revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
if revision != versions["honk"]["revision"]:
    raise SystemExit("honk: release tag changed during version resolution")
# Keep the package metadata and the binary's embedded version aligned with the checkout.
replace_setting(makefile, "PKG_VERSION", ":=", versions["honk"]["package_version"])
replace_setting(makefile, "HONK_GIT_TAG", ":=", versions["honk"]["tag"])
# Use the newest published UI, retaining upstream's checksum/notice verification.
pins = source / ".github/ci/pins.env"
for key, field in (("DOONA_VERSION", "version"), ("DOONA_REVISION", "revision"),
                   ("DOONA_SHA256", "sha256"), ("DOONA_LITE_SHA256", "lite_sha256")):
    replace_setting(pins, key, "=", versions["doona"][field])
versions_path.write_text(json.dumps(versions, indent=2) + "\n")

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

# Anchor to the dae guard in start_service: reload_service also declares config_file.
dae_guard = '\tif ubus call service list \'{"name":"dae"}\' 2>/dev/null |\n'
replace_once(package / "files/honk.init", dae_guard, '''\tif ubus call service list '{"name":"daed"}' 2>/dev/null |
\t\tjsonfilter -q -e '@.daed.instances[*].running' | grep -q true; then
\t\tlogger -t honk "daed is running; disable and stop daed before starting honk"
\t\treturn 1
\tfi

\tmkdir -p /etc/honk/data
\tchmod 0700 /etc/honk /etc/honk/data

''' + dae_guard)
lan_ip = ipaddress.IPv4Address(sys.argv[2])
config = Path(sys.argv[1]).read_text().replace("@LAN_IP@", str(lan_ip))
(package / "files/config.dae").write_text(config)
PY

echo "honk: official feed $FEED_COMMIT; backend $HONK_TAG"
grep '^DOONA_' ./package/honk/src/.github/ci/pins.env
# Upstream now uses rc.d for autostart; its first-boot script disables fresh installs.
grep -qF '/etc/init.d/honk disable' ./package/honk/files/honk.uci-defaults
REPORT_DIR="${GITHUB_WORKSPACE:-$PROJECT_DIR}/build-reports"
mkdir -p "$REPORT_DIR"
cp "$VERSIONS_FILE" "$REPORT_DIR/honk-versions.json"
