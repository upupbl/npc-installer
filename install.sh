#!/bin/sh
set -eu

VERSION="${NPC_VERSION:-0.26.10}"
RELEASE_BASE="${NPC_RELEASE_BASE:-https://github.com/ehang-io/nps/releases/download}"
DEFAULT_SERVER="${NPC_DEFAULT_SERVER:-23.141.12.66:8024}"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"

case "$OS" in
  Linux) ;;
  *) die "This installer currently supports Linux/NAS. Detected OS: $OS" ;;
esac

case "$ARCH" in
  x86_64|amd64)            PKG="linux_amd64_client.tar.gz" ;;
  i386|i486|i586|i686|x86) PKG="linux_386_client.tar.gz" ;;
  aarch64|arm64)           PKG="linux_arm64_client.tar.gz" ;;
  armv7l|armv7*)           PKG="linux_arm_v7_client.tar.gz" ;;
  armv6l|armv6*)           PKG="linux_arm_v6_client.tar.gz" ;;
  armv5l|armv5*)           PKG="linux_arm_v5_client.tar.gz" ;;
  mips64el|mips64le)       PKG="linux_mips64le_client.tar.gz" ;;
  mips64)                  PKG="linux_mips64_client.tar.gz" ;;
  mipsel|mipsle)           PKG="linux_mipsle_client.tar.gz" ;;
  mips)                    PKG="linux_mips_client.tar.gz" ;;
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

NPC_BIN="$INSTALL_DIR/npc"
LOG_FILE="$INSTALL_DIR/npc.log"

say "[NPC] Installed successfully: $NPC_BIN"
"$NPC_BIN" -version

if [ "$IS_ROOT" = "1" ] && [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
  ln -sf "$NPC_BIN" /usr/local/bin/npc 2>/dev/null || true
fi

SERVER="${NPC_SERVER:-}"
VKEY="${NPC_VKEY:-}"
TYPE="${NPC_TYPE:-tcp}"

if [ -z "$SERVER" ]; then
  if [ -t 0 ]; then
    printf '\nNPS server [%s]: ' "$DEFAULT_SERVER"
    read -r SERVER_INPUT || true
    SERVER="${SERVER_INPUT:-$DEFAULT_SERVER}"
  else
    SERVER="$DEFAULT_SERVER"
  fi
fi

if [ -z "$VKEY" ]; then
  if [ -t 0 ]; then
    printf 'VKey: '
    if command -v stty >/dev/null 2>&1; then
      stty -echo 2>/dev/null || true
      read -r VKEY || true
      stty echo 2>/dev/null || true
      printf '\n'
    else
      read -r VKEY || true
    fi
  fi
fi

if [ -z "$VKEY" ]; then
  cat <<EOF2

[NPC] Installation finished. VKey was not supplied, so NPC was not started.
Run manually:
  $NPC_BIN -server=$SERVER -vkey=YOUR_VKEY -type=$TYPE

Or install/start non-interactively:
  NPC_SERVER='$SERVER' NPC_VKEY='YOUR_VKEY' sh -c "\$(curl -kfsSL https://raw.githubusercontent.com/upupbl/npc-installer/main/install.sh)"
EOF2
  exit 0
fi

# Avoid starting a second exact npc process when one is already running.
if command -v pidof >/dev/null 2>&1 && pidof npc >/dev/null 2>&1; then
  say "[NPC] An npc process is already running. Installation completed; no second process was started."
  say "[NPC] Check with: pidof npc"
  exit 0
fi

: > "$LOG_FILE" 2>/dev/null || true

if command -v setsid >/dev/null 2>&1; then
  setsid "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="setsid"
elif command -v nohup >/dev/null 2>&1; then
  nohup "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="nohup"
elif command -v busybox >/dev/null 2>&1 && busybox nohup true >/dev/null 2>&1; then
  busybox nohup "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="busybox nohup"
else
  "$NPC_BIN" -server="$SERVER" -vkey="$VKEY" -type="$TYPE" </dev/null >>"$LOG_FILE" 2>&1 &
  NPC_PID=$!
  DETACH_METHOD="shell background (may stop after logout on some systems)"
fi

sleep 2

if kill -0 "$NPC_PID" 2>/dev/null; then
  say "[NPC] Started successfully in background."
  say "[NPC] PID: $NPC_PID"
  say "[NPC] Server: $SERVER"
  say "[NPC] Detach: $DETACH_METHOD"
  say "[NPC] Log: $LOG_FILE"
  if command -v tail >/dev/null 2>&1; then
    tail -n 10 "$LOG_FILE" 2>/dev/null || true
  fi
else
  say "[NPC] Process exited shortly after start. Log follows:"
  cat "$LOG_FILE" 2>/dev/null || true
  exit 1
fi
