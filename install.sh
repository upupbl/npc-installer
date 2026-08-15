#!/bin/sh
set -eu

VERSION="${NPC_VERSION:-0.26.10}"
RELEASE_BASE="${NPC_RELEASE_BASE:-https://github.com/ehang-io/nps/releases/download}"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"

case "$OS" in
  Linux) ;;
  *) die "This installer currently supports Linux/NAS. Detected OS: $OS" ;;
esac

case "$ARCH" in
  x86_64|amd64)      PKG="linux_amd64_client.tar.gz" ;;
  i386|i486|i586|i686|x86) PKG="linux_386_client.tar.gz" ;;
  aarch64|arm64)     PKG="linux_arm64_client.tar.gz" ;;
  armv7l|armv7*)     PKG="linux_arm_v7_client.tar.gz" ;;
  armv6l|armv6*)     PKG="linux_arm_v6_client.tar.gz" ;;
  armv5l|armv5*)     PKG="linux_arm_v5_client.tar.gz" ;;
  mips64el|mips64le) PKG="linux_mips64le_client.tar.gz" ;;
  mips64)            PKG="linux_mips64_client.tar.gz" ;;
  mipsel|mipsle)     PKG="linux_mipsle_client.tar.gz" ;;
  mips)              PKG="linux_mips_client.tar.gz" ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac

IS_ROOT=0
[ "$(id -u 2>/dev/null || echo 1)" = "0" ] && IS_ROOT=1

TMP_BASE="${TMPDIR:-/tmp}"
TMP_DIR="$TMP_BASE/npc-install-$$"
ARCHIVE="$TMP_DIR/$PKG"
URL="$RELEASE_BASE/v$VERSION/$PKG"

cleanup() { rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
mkdir -p "$TMP_DIR"

say "[NPC] OS: $OS"
say "[NPC] Architecture: $ARCH"
say "[NPC] Package: $PKG"
say "[NPC] Version: $VERSION"
say "[NPC] Download: $URL"

if command -v curl >/dev/null 2>&1; then
  curl -kfsSL --retry 2 --connect-timeout 15 -o "$ARCHIVE" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget --no-check-certificate -O "$ARCHIVE" "$URL"
else
  die "curl or wget is required"
fi

command -v tar >/dev/null 2>&1 || die "tar is required"
tar -xzf "$ARCHIVE" -C "$TMP_DIR"
[ -f "$TMP_DIR/npc" ] || die "npc binary was not found after extraction"

INSTALL_DIR=""
if [ -n "${NPC_INSTALL_DIR:-}" ]; then
  CANDIDATES="$NPC_INSTALL_DIR"
elif [ "$IS_ROOT" = "1" ]; then
  CANDIDATES="/usr/local/npc /opt/npc $HOME/npc"
else
  CANDIDATES="$HOME/.local/npc $HOME/npc"
fi

for dir in $CANDIDATES; do
  if mkdir -p "$dir" 2>/dev/null && cp "$TMP_DIR/npc" "$dir/npc" 2>/dev/null && chmod 755 "$dir/npc" 2>/dev/null; then
    # Many NAS mount /tmp (and occasionally other paths) with noexec, so verify execution.
    if "$dir/npc" -version >/dev/null 2>&1; then
      INSTALL_DIR="$dir"
      break
    fi
  fi
done

[ -n "$INSTALL_DIR" ] || die "Could not find a writable and executable install directory. Set NPC_INSTALL_DIR to a persistent executable path."

say "[NPC] Installed successfully: $INSTALL_DIR/npc"
"$INSTALL_DIR/npc" -version

if [ "$IS_ROOT" = "1" ] && [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
  ln -sf "$INSTALL_DIR/npc" /usr/local/bin/npc 2>/dev/null || true
fi

cat <<EOF2

Usage:
  $INSTALL_DIR/npc -server=SERVER_IP:PORT -vkey=YOUR_VKEY -type=tcp

Example:
  $INSTALL_DIR/npc -server=1.2.3.4:8024 -vkey=YOUR_VKEY -type=tcp
EOF2
